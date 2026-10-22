"""
train_posture_cnn_64ch_dummy.py  (8종 버전, 2026-10-15)

모델 구조(PostureCNN64)와 학습 루프는 원본 train_posture_cnn_64ch.py 와 같다.
8종 라벨(p0~p7, 앱 순서)로 바뀌면서 달라진 점:

  1. 클래스는 항상 8개(p0~p7)로 고정이다. 데이터에 없는 클래스가 있어도 번호가
     밀리지 않는다. (예전에는 LabelEncoder 가 데이터에 있는 라벨만 정렬해서
     번호를 붙였기 때문에, 클래스가 빠지면 앱·서버와 번호가 어긋났다.)
  2. 정규화 mean/std 는 학습 데이터로만 계산한다 (테스트 데이터가 섞이지 않게).
     std 는 1.0 아래로 내려가지 않게 바닥을 둔다 (한 번도 안 눌린 채널에
     값이 들어왔을 때 z-score 가 폭주하는 것을 막기 위해). 바닥값이 적용된
     std 가 norm_stats 에 그대로 저장되므로 서버·앱도 같은 값을 쓴다.
  3. CSV 에 Person 컬럼이 있으면 --holdout-persons 로 사람 단위 평가를 할 수 있다.
     (윈도우/프레임을 무작위로 섞어 나누면 같은 사람의 거의 같은 프레임이 학습과
      테스트에 같이 들어가서 점수가 부풀려진다.)
  4. norm_stats 에 label_names(코드->한글 이름)를 같이 저장한다. 서버·리포트·
     시뮬레이터가 이 이름표를 읽는다 (posture_names.py).
  5. 자세별 정확도와 혼동행렬을 출력한다.

사용법
------
    python train_posture_cnn_64ch_dummy.py --data chair_64ch_posture_data_real.csv --out-suffix real
    # 사람 단위 평가 (예: 아로·예원으로 학습, 다혜로 테스트)
    python train_posture_cnn_64ch_dummy.py --data chair_64ch_posture_data_real.csv --out-suffix real --holdout-persons dahye

결과: posture_model_64ch_<suffix>.pt / norm_stats_64ch_<suffix>.json
      (서버가 읽는 posture_model_64ch.pt / norm_stats_64ch.json 은 덮어쓰지 않는다)
"""

import argparse
import json
import sys

import numpy as np
import pandas as pd
import torch
import torch.nn as nn
import torch.optim as optim
from sklearn.model_selection import train_test_split

from posture_names import CODES, NEW_NAMES, POSTURE_ORDER

NUM_CLASSES = len(CODES)  # 8
STD_FLOOR = 1.0


# =====================================================================
# 1. 1D-CNN 모델 정의 — 원본과 동일
# =====================================================================
class PostureCNN64(nn.Module):
    def __init__(self, num_classes: int):
        super(PostureCNN64, self).__init__()
        self.conv1 = nn.Conv1d(in_channels=1, out_channels=32, kernel_size=3, padding=1)
        self.pool = nn.MaxPool1d(kernel_size=2)
        self.fc1 = nn.Linear(1024, 128)
        self.fc2 = nn.Linear(128, num_classes)

    def forward(self, x):
        x = torch.relu(self.conv1(x))
        x = self.pool(x)
        x = x.view(x.size(0), -1)
        x = torch.relu(self.fc1(x))
        x = self.fc2(x)
        return x


def split_data(df, y, holdout_persons):
    """(train_idx, test_idx, 설명 문자열) 반환."""
    if holdout_persons:
        if "Person" not in df.columns:
            sys.exit("이 CSV 에는 Person 컬럼이 없어서 --holdout-persons 를 쓸 수 없습니다. "
                     "collect_back.py 로 모은 raw CSV 를 prepare_chair_data 로 변환해서 다시 만드세요.")
        persons = set(df["Person"].astype(str).unique())
        unknown = [p for p in holdout_persons if p not in persons]
        if unknown:
            sys.exit(f"CSV 에 없는 참가자: {unknown}. 있는 참가자: {sorted(persons)}")
        test_mask = df["Person"].astype(str).isin(holdout_persons).values
        if test_mask.all():
            sys.exit("모든 참가자를 테스트로 빼면 학습할 데이터가 없습니다.")
        return np.where(~test_mask)[0], np.where(test_mask)[0], \
            f"사람 단위 분리 (테스트 참가자: {holdout_persons})"

    idx = np.arange(len(df))
    try:
        tr, te = train_test_split(idx, test_size=0.2, random_state=42, stratify=y)
    except ValueError:
        tr, te = train_test_split(idx, test_size=0.2, random_state=42)
    note = "프레임 무작위 분리 (원본 방식)"
    if "Person" in df.columns and df["Person"].nunique() > 1:
        note += (f"\n  ⚠️ 참가자가 {df['Person'].nunique()}명인데 프레임을 섞어서 나누고 있습니다. "
                 "점수가 실제보다 높게 나옵니다. --holdout-persons 로 사람 단위 평가를 하세요.")
    return tr, te, note


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", default="chair_64ch_posture_data_real.csv")
    ap.add_argument("--out-suffix", default="real")
    ap.add_argument("--epochs", type=int, default=30)
    ap.add_argument("--holdout-persons", default="",
                    help="테스트로만 쓸 참가자 이름 (쉼표로 여러 명). 예: dahye 또는 yewon,aro")
    ap.add_argument("--force", action="store_true",
                    help="p0(앉지 않음)이 없는 CSV 도 그대로 학습 (예전 7종 CSV 가 아님을 확신할 때만)")
    args = ap.parse_args()
    holdout = [p.strip() for p in args.holdout_persons.split(",") if p.strip()]

    # =================================================================
    # 2. 데이터 로드 + 라벨 검증
    # =================================================================
    df = pd.read_csv(args.data)
    SEAT_COLS = [f"seat_{i+1}" for i in range(32)]
    BACK_COLS = [f"back_{i+1}" for i in range(32)]
    SENSOR_COLS = SEAT_COLS + BACK_COLS

    labels_present = sorted(df["Label"].astype(str).unique())
    unknown = [c for c in labels_present if c not in CODES]
    if unknown:
        sys.exit(f"알 수 없는 Label 값 {unknown}. p0~p7 만 쓸 수 있습니다.")
    if "p0" not in labels_present and not args.force:
        sys.exit("이 CSV 에는 p0(앉지 않음)이 없습니다. 예전 7종 CSV(p1~p7, p7=앉지않음)로 보입니다.\n"
                 "8종에서는 p7 이 거북목이라 의미가 달라졌습니다. prepare_chair_data.py 로 새로 만드세요.\n"
                 "(정말 이 CSV 가 8종 라벨이 맞다면 --force)")

    code_to_idx = {c: i for i, c in enumerate(CODES)}
    y = df["Label"].astype(str).map(code_to_idx).values.astype(np.int64)

    # =================================================================
    # 3. 학습/테스트 분리 후, 학습 데이터로만 정규화 통계 계산
    # =================================================================
    train_idx, test_idx, split_note = split_data(df, y, holdout)

    X_raw = df[SENSOR_COLS].values.astype(np.float32)
    sensor_mean = X_raw[train_idx].mean(axis=0)
    sensor_std = np.maximum(X_raw[train_idx].std(axis=0, ddof=1), STD_FLOOR)
    X = (X_raw - sensor_mean) / (sensor_std + 1e-7)

    X_train, y_train = X[train_idx], y[train_idx]
    X_test, y_test = X[test_idx], y[test_idx]

    print("=" * 60)
    print(f"데이터: {args.data}")
    print(f"총 {len(X):,}행 (학습 {len(X_train):,} / 테스트 {len(X_test):,}), 입력 채널 {len(SENSOR_COLS)}개")
    print(f"분리 방식: {split_note}")
    print(f"출력 클래스: {NUM_CLASSES}개 고정")
    for i, c in enumerate(CODES):
        print(f"  {i} {c} {NEW_NAMES[c]:<8} 학습 {int((y_train == i).sum()):>8,}  테스트 {int((y_test == i).sum()):>8,}")
    print("=" * 60)

    missing_train = [CODES[i] for i in range(NUM_CLASSES) if (y_train == i).sum() == 0]
    if missing_train:
        print("⚠️  학습 데이터에 없는 클래스: "
              + ", ".join(f"{c}({NEW_NAMES[c]})" for c in missing_train)
              + " → 모델이 이 클래스를 예측하지 못합니다.")

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model = PostureCNN64(num_classes=NUM_CLASSES).to(device)
    criterion = nn.CrossEntropyLoss()
    optimizer = optim.Adam(model.parameters(), lr=0.001)

    train_inputs = torch.tensor(X_train).float().unsqueeze(1).to(device)
    train_labels = torch.tensor(y_train).long().to(device)
    test_inputs = torch.tensor(X_test).float().unsqueeze(1).to(device)

    # =================================================================
    # 4. 학습 루프 — 원본과 동일
    # =================================================================
    EPOCHS = args.epochs
    BATCH_SIZE = 64
    n_samples = train_inputs.size(0)

    print("\n학습을 시작합니다...")
    model.train()
    for epoch in range(EPOCHS):
        perm = torch.randperm(n_samples)
        epoch_loss = 0.0
        for i in range(0, n_samples, BATCH_SIZE):
            idx = perm[i:i + BATCH_SIZE]
            batch_x = train_inputs[idx]
            batch_y = train_labels[idx]

            optimizer.zero_grad()
            outputs = model(batch_x)
            loss = criterion(outputs, batch_y)
            loss.backward()
            optimizer.step()
            epoch_loss += loss.item() * batch_x.size(0)

        if (epoch + 1) % 5 == 0 or epoch == 0:
            print(f"Epoch {epoch+1:02d}/{EPOCHS}, Loss: {epoch_loss / n_samples:.4f}")

    # =================================================================
    # 5. 평가: 전체 정확도 + 자세별 정확도 + 혼동행렬
    # =================================================================
    model.eval()
    with torch.no_grad():
        preds = torch.argmax(model(test_inputs), dim=1).cpu().numpy()
    accuracy = float((preds == y_test).mean())

    conf = np.zeros((NUM_CLASSES, NUM_CLASSES), dtype=int)
    for t, p in zip(y_test, preds):
        conf[t, p] += 1

    print("\n" + "=" * 60)
    print(f"🎯 테스트셋 정확도: {accuracy * 100:.2f}%")
    print("=" * 60)
    print("자세별 정확도 (테스트 데이터가 있는 클래스만):")
    for i, c in enumerate(CODES):
        n = conf[i].sum()
        if n:
            print(f"  {c} {NEW_NAMES[c]:<8} {conf[i, i] / n * 100:6.1f}%  ({conf[i, i]}/{n})")
    print("\n혼동행렬 (행=정답, 열=예측):")
    print("      " + " ".join(f"{c:>6}" for c in CODES))
    for i, c in enumerate(CODES):
        if conf[i].sum():
            print(f"  {c}  " + " ".join(f"{v:>6}" for v in conf[i]))

    if "Person" in df.columns and not holdout:
        print("\n⚠️  이 점수는 같은 사람의 프레임이 학습·테스트에 섞인 값입니다. 일반화 성능이 아닙니다.")
    if accuracy < 0.85:
        print("⚠️  목표 정확도(85%) 미달입니다. 데이터 품질/에폭/모델 구조를 점검하세요.")

    # =================================================================
    # 6. 가중치 + 정규화 통계 + 라벨 정보 저장 (서버가 쓰는 파일은 덮어쓰지 않음)
    # =================================================================
    pt_path = f"posture_model_64ch_{args.out_suffix}.pt"
    json_path = f"norm_stats_64ch_{args.out_suffix}.json"

    torch.save(model.state_dict(), pt_path)
    print(f"\n✅ {pt_path} 저장 완료")

    norm_stats = {
        "seat_cols_order": SEAT_COLS,
        "back_cols_order": BACK_COLS,
        "sensor_cols_order": SENSOR_COLS,
        "mean": sensor_mean.tolist(),
        "std": sensor_std.tolist(),
        "label_classes": list(CODES),
        "label_order": list(POSTURE_ORDER),   # 앱(PosturePreprocessor)이 읽는 키
        "class_index": {name: i for i, name in enumerate(POSTURE_ORDER)},
        "label_names": dict(NEW_NAMES),
        "num_classes": NUM_CLASSES,
        "test_accuracy": accuracy,
        "holdout_persons": holdout,
        "train_classes_missing": missing_train,
    }
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(norm_stats, f, ensure_ascii=False, indent=2)
    print(f"✅ {json_path} 저장 완료")

    print("\n다음 단계: 결과가 마음에 들면 서버 파일로 교체하세요.")
    print(f"  copy {pt_path} posture_model_64ch.pt")
    print(f"  copy {json_path} norm_stats_64ch.json")
    print("  (personal_stats.json 이 있으면 이름을 바꿔 치우고, 서버를 다시 켜세요)")


if __name__ == "__main__":
    main()
