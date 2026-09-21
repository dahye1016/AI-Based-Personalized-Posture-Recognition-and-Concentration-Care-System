"""
train_posture_cnn.py — 32ch 실측(data/raw) 자세 분류 1D-CNN 학습

앱(lib/models/posture_class.dart)의 출력 인덱스와 라벨 순서를 고정한다.
sklearn LabelEncoder 는 알파벳순으로 번호를 매겨 앱과 어긋나므로 쓰지 않는다.

  0 not_sitting / 1 sitting_straight / 2 lean_forward / 3 cross_leg_right
  4 cross_leg_left / 5 lean_right / 6 lean_left

입력은 프레임 하나: 정규화한 ch0~31 + 0 패딩 32개 = 64.
(등받이 매트가 없어 뒤 32개는 항상 0. 64채널 구조는 유지한다.)

평가는 사람 단위: 한 명을 통째로 빼고 나머지로 학습해 그 사람으로 테스트(3-fold).
앱에 넘기는 최종 모델은 3명 전체로 학습한다.

실행 (저장소 루트에서):
    python ml/train_posture_cnn.py
결과: ml/posture_model.pt, ml/norm_stats.json
"""

import json
import random
from pathlib import Path

import numpy as np
import pandas as pd
import torch
import torch.nn as nn
import torch.optim as optim

ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = ROOT / "data" / "raw"
OUT_PT = ROOT / "ml" / "posture_model.pt"
OUT_JSON = ROOT / "ml" / "norm_stats.json"

LABEL_ORDER = [
    "not_sitting",
    "sitting_straight",
    "lean_forward",
    "cross_leg_right",
    "cross_leg_left",
    "lean_right",
    "lean_left",
]
LABEL_TO_IDX = {name: i for i, name in enumerate(LABEL_ORDER)}

N_CH = 32          # 실측 채널 (방석)
N_INPUT = 64       # 모델 입력 (방석 32 + 등받이 32 자리, 등받이는 0)
CH_COLS = [f"ch{i}" for i in range(N_CH)]
STD_FLOOR = 1.0    # 항상 0인 채널에서 0 으로 나누는 것을 막는다. 앱은 (x-mean)/std 만 하면 된다.

EPOCHS = 30
BATCH_SIZE = 64
LR = 0.001
SEED = 42


class PostureCNN64(nn.Module):
    def __init__(self, num_classes: int):
        super().__init__()
        self.conv1 = nn.Conv1d(1, 32, kernel_size=3, padding=1)
        self.pool = nn.MaxPool1d(kernel_size=2)
        self.fc1 = nn.Linear(1024, 128)
        self.fc2 = nn.Linear(128, num_classes)

    def forward(self, x):
        x = self.pool(torch.relu(self.conv1(x)))
        x = x.view(x.size(0), -1)
        x = torch.relu(self.fc1(x))
        return self.fc2(x)


def load_raw() -> pd.DataFrame:
    files = sorted(RAW_DIR.glob("*.csv"))
    if not files:
        raise SystemExit(f"{RAW_DIR} 에 CSV 가 없습니다.")
    df = pd.concat([pd.read_csv(f) for f in files], ignore_index=True)
    unknown = set(df["posture"]) - set(LABEL_ORDER)
    if unknown:
        raise SystemExit(f"LABEL_ORDER 에 없는 자세 이름: {sorted(unknown)}")
    return df


def fit_norm(x_raw: np.ndarray):
    mean = x_raw.mean(axis=0)
    std = np.maximum(x_raw.std(axis=0), STD_FLOOR)
    return mean, std


def to_input(x_raw: np.ndarray, mean, std) -> np.ndarray:
    """ch0~31 정규화 후 뒤에 0 패딩 32개를 붙여 (N, 64) 로 만든다."""
    x = ((x_raw - mean) / std).astype(np.float32)
    pad = np.zeros((len(x), N_INPUT - N_CH), dtype=np.float32)
    return np.concatenate([x, pad], axis=1)


def train(x: np.ndarray, y: np.ndarray) -> PostureCNN64:
    torch.manual_seed(SEED)
    model = PostureCNN64(len(LABEL_ORDER))
    criterion = nn.CrossEntropyLoss()
    optimizer = optim.Adam(model.parameters(), lr=LR)
    xt = torch.tensor(x).unsqueeze(1)
    yt = torch.tensor(y).long()
    n = len(xt)
    model.train()
    for _ in range(EPOCHS):
        perm = torch.randperm(n)
        for i in range(0, n, BATCH_SIZE):
            idx = perm[i:i + BATCH_SIZE]
            optimizer.zero_grad()
            loss = criterion(model(xt[idx]), yt[idx])
            loss.backward()
            optimizer.step()
    return model


def predict(model: PostureCNN64, x: np.ndarray) -> np.ndarray:
    model.eval()
    with torch.no_grad():
        return model(torch.tensor(x).unsqueeze(1)).argmax(dim=1).numpy()


def evaluate_fold(df: pd.DataFrame, test_person: str) -> dict:
    tr = df[df["person"] != test_person]
    te = df[df["person"] == test_person]
    mean, std = fit_norm(tr[CH_COLS].values.astype(np.float32))
    xtr = to_input(tr[CH_COLS].values.astype(np.float32), mean, std)
    xte = to_input(te[CH_COLS].values.astype(np.float32), mean, std)
    ytr = tr["posture"].map(LABEL_TO_IDX).values
    yte = te["posture"].map(LABEL_TO_IDX).values

    model = train(xtr, ytr)
    pred = predict(model, xte)

    per_class = {}
    for k, name in enumerate(LABEL_ORDER):
        m = yte == k
        per_class[name] = (
            {"n": int(m.sum()), "recall": float((pred[m] == k).mean())} if m.any() else None
        )
    confusion = np.zeros((len(LABEL_ORDER), len(LABEL_ORDER)), dtype=int)
    for t, p in zip(yte, pred):
        confusion[t, p] += 1
    return {
        "test_person": test_person,
        "train_persons": sorted(tr["person"].unique()),
        "n_train": int(len(tr)),
        "n_test": int(len(te)),
        "accuracy": float((pred == yte).mean()),
        "per_class": per_class,
        "confusion": confusion.tolist(),
    }


def main():
    random.seed(SEED)
    np.random.seed(SEED)
    df = load_raw()
    persons = sorted(df["person"].unique())
    print(f"데이터: {len(df)}프레임, 사람 {persons}, 파일 {len(list(RAW_DIR.glob('*.csv')))}개")
    print("자세별 프레임:", df["posture"].value_counts().reindex(LABEL_ORDER).to_dict())

    folds = []
    for p in persons:
        r = evaluate_fold(df, p)
        folds.append(r)
        print(f"\n[테스트 {p} / 학습 {r['train_persons']}] 정확도 {r['accuracy'] * 100:.1f}% "
              f"(학습 {r['n_train']} / 테스트 {r['n_test']})")
        for name in LABEL_ORDER:
            c = r["per_class"][name]
            print(f"   {name:17s} " + (f"n={c['n']:4d}  recall {c['recall'] * 100:5.1f}%" if c else "테스트 데이터 없음"))
    mean_acc = float(np.mean([f["accuracy"] for f in folds]))
    print(f"\n사람 단위 3-fold 평균 정확도: {mean_acc * 100:.1f}%")

    # 최종 모델: 3명 전체로 학습 (앱에 넘기는 용도)
    x_raw = df[CH_COLS].values.astype(np.float32)
    mean, std = fit_norm(x_raw)
    model = train(to_input(x_raw, mean, std), df["posture"].map(LABEL_TO_IDX).values)
    torch.save(model.state_dict(), OUT_PT)

    stats = {
        "label_order": LABEL_ORDER,
        "class_index": LABEL_TO_IDX,
        "channels": CH_COLS,
        "mean": mean.tolist(),
        "std": std.tolist(),
        "std_floor": STD_FLOOR,
        "normalize": "x_norm[i] = (ch[i] - mean[i]) / std[i]   (i = 0..31)",
        "padding": f"정규화 후 ch32~ch{N_INPUT - 1} 자리에 0 을 {N_INPUT - N_CH}개 붙인다 (등받이 없음)",
        "num_classes": len(LABEL_ORDER),
        "trained_on_persons": persons,
        "person_split_eval": {
            "method": "leave-one-person-out",
            "mean_accuracy": mean_acc,
            "folds": [{k: f[k] for k in ("test_person", "train_persons", "n_test", "accuracy")} for f in folds],
        },
    }
    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(stats, f, ensure_ascii=False, indent=2)
    print(f"\n저장: {OUT_PT.relative_to(ROOT)}, {OUT_JSON.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
