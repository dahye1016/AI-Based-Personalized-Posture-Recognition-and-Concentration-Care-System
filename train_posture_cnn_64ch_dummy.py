"""
train_posture_cnn_64ch_dummy.py

원본 train_posture_cnn_64ch.py와 완전히 동일한 모델 구조·학습 루프다.
바뀐 건 딱 세 가지뿐이다:
  1. DATA_PATH -> chair_64ch_posture_data_dummy.csv (또는 --data로 지정)
     (ml/prepare_chair_data.py로 우리 posture 데이터를 이 스키마로 변환한 파일)
  2. 저장 파일 이름 -> *_dummy.pt / *_dummy.json
     (원본 posture_model_64ch.pt / norm_stats_64ch.json은 서버가 쓰는 진짜 파일이라
      실수로 덮어쓰지 않도록 분리해뒀다. 결과가 마음에 들면 이 파일들을
      posture_model_64ch.pt / norm_stats_64ch.json으로 이름만 바꿔서 교체하면 된다.)
  3. num_classes가 7로 나온다 (원본 8 -> 7). Label 종류가 데이터에서 자동으로
     정해지기 때문에(LabelEncoder), 모델 구조 코드는 손댈 필요가 없다. p8(등받이
     밀착 자세)은 등받이 실측 센서가 없어서 이 데이터에 없다.

사용법
------
    python train_posture_cnn_64ch_dummy.py
    python train_posture_cnn_64ch_dummy.py --data chair_64ch_posture_data_real.csv --out-suffix real
"""

import argparse
import json
import numpy as np
import pandas as pd
import torch
import torch.nn as nn
import torch.optim as optim
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder


# =====================================================================
# 1. 1D-CNN 모델 정의 — 원본 train_posture_cnn_64ch.py와 완전히 동일
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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", default="chair_64ch_posture_data_dummy.csv")
    ap.add_argument("--out-suffix", default="dummy")
    ap.add_argument("--epochs", type=int, default=30)
    args = ap.parse_args()

    # =================================================================
    # 2. 데이터 로드 및 Z-Score 정규화 — 원본과 동일한 절차
    # =================================================================
    df = pd.read_csv(args.data)

    SEAT_COLS = [f"seat_{i+1}" for i in range(32)]
    BACK_COLS = [f"back_{i+1}" for i in range(32)]
    SENSOR_COLS = SEAT_COLS + BACK_COLS

    df_X = df[SENSOR_COLS]
    y_raw = df["Label"].values

    sensor_mean = df_X.mean().values
    sensor_std = df_X.std().values

    def z_score_normalize(x, mean, std):
        return (x - mean) / (std + 1e-7)

    X = z_score_normalize(df_X.values, sensor_mean, sensor_std)

    le = LabelEncoder()
    y = le.fit_transform(y_raw)
    num_classes = len(le.classes_)

    print("=" * 60)
    print(f"데이터: {args.data}")
    print(f"총 데이터 개수: {len(X)}개, 입력 채널: {len(SENSOR_COLS)}개")
    print(f"분류할 자세 종류 ({num_classes}종): {list(le.classes_)}")
    print("=" * 60)

    # =================================================================
    # 3. 학습/테스트 분리 — 원본과 동일 (test_size=0.2, stratify)
    # =================================================================
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model = PostureCNN64(num_classes=num_classes).to(device)
    criterion = nn.CrossEntropyLoss()
    optimizer = optim.Adam(model.parameters(), lr=0.001)

    train_inputs = torch.tensor(X_train).float().unsqueeze(1).to(device)
    train_labels = torch.tensor(y_train).long().to(device)
    test_inputs = torch.tensor(X_test).float().unsqueeze(1).to(device)
    test_labels = torch.tensor(y_test).long().to(device)

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
    # 5. 테스트셋 정확도 평가 — 원본과 동일
    # =================================================================
    model.eval()
    with torch.no_grad():
        test_outputs = model(test_inputs)
        preds = torch.argmax(test_outputs, dim=1)
        accuracy = (preds == test_labels).float().mean().item()

    print("\n" + "=" * 60)
    print(f"🎯 테스트셋 정확도: {accuracy * 100:.2f}%")
    print("=" * 60)

    if accuracy < 0.85:
        print("⚠️  목표 정확도(85%) 미달입니다. 데이터 품질/에폭/모델 구조를 점검하세요.")

    # =================================================================
    # 6. 가중치 + 정규화 통계 + 라벨 순서 저장
    #    ⚠️ 원본 posture_model_64ch.pt / norm_stats_64ch.json을 덮어쓰지
    #       않도록 suffix를 붙여서 저장한다.
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
        "label_classes": list(le.classes_),
        "num_classes": num_classes,
        "test_accuracy": accuracy,
    }
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(norm_stats, f, ensure_ascii=False, indent=2)
    print(f"✅ {json_path} 저장 완료")

    print(f"\n다음 단계: 결과가 마음에 들면 아래처럼 이름을 바꿔서 실제 서버가"
          f" 쓰는 파일로 교체하세요.")
    print(f"  copy {pt_path} posture_model_64ch.pt")
    print(f"  copy {json_path} norm_stats_64ch.json")
    print(f"  (서버 재시작 필요: uvicorn server_64ch:app --reload)")
    print(f"\n⚠️  num_classes가 {num_classes}로 바뀌었으니, server_64ch.py의 DISPLAY_NAMES"
          f"(자세 8종 표시용)가 8종 그대로 하드코딩되어 있다면 p8(등받이 밀착 자세) 표시"
          f"부분을 손봐야 할 수 있습니다. 이 스크립트는 학습만 하고 서버 코드는 안 건드립니다.")


if __name__ == "__main__":
    main()
