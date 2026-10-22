"""
train_posture_cnn_8cls.py — 64ch 실측(data/raw_64ch) 8클래스 자세 분류 1D-CNN 학습

ml/train_posture_cnn.py(32ch 7클래스)와 같은 구조를 64ch·8클래스로 넓힌 것.

라벨 순서는 posture_names.POSTURE_ORDER 를 그대로 쓴다 (앱 posture_class.dart 와 동일).
  0 not_sitting / 1 sitting_straight / 2 lean_forward / 3 cross_leg_right
  4 cross_leg_left / 5 lean_right / 6 lean_left / 7 turtle_neck

입력은 프레임 하나: ch0~31(좌석) + ch32~63(등받이)을 정규화한 64개. 0 패딩 없음.
(채널 순서는 ml/collect_data.py --port-back 이 저장한 순서 그대로)

평가는 사람 단위(LOPO): 한 명을 통째로 빼고 나머지로 학습해 그 사람으로 테스트.
앱에 넘기는 최종 모델은 전체 인원으로 학습한다.

json 하나를 앱과 서버가 같이 쓴다:
  앱(PosturePreprocessor.fromJson): label_order, mean, std, model_io.input_shape
                                    (model_io 는 export_tflite_8cls.py 가 채움)
  서버(server_64ch.py): sensor_cols_order, mean, std, label_classes, num_classes, label_names

실행 (저장소 루트에서):
    python ml/train_posture_cnn_8cls.py
결과: ml/posture_model_8cls.pt, ml/norm_stats_8cls.json, ml/runs/8cls/ (혼동행렬 등)
"""

import json
import random
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import torch
import torch.nn as nn
import torch.optim as optim

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from posture_names import POSTURE_ORDER, KOREAN  # noqa: E402

RAW_DIR = ROOT / "data" / "raw_64ch"
OUT_PT = ROOT / "ml" / "posture_model_8cls.pt"
OUT_JSON = ROOT / "ml" / "norm_stats_8cls.json"
RUN_DIR = ROOT / "ml" / "runs" / "8cls"

LABEL_ORDER = list(POSTURE_ORDER)
LABEL_TO_IDX = {name: i for i, name in enumerate(LABEL_ORDER)}
N_CLS = len(LABEL_ORDER)

N_CH = 64
CH_COLS = [f"ch{i}" for i in range(N_CH)]
STD_FLOOR = 1.0    # 한 번도 안 눌린 채널에서 0 으로 나누는 것을 막는다.

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
    files = sorted(f for f in RAW_DIR.glob("*.csv") if "_reject" not in f.stem)
    if not files:
        raise SystemExit(f"{RAW_DIR} 에 CSV 가 없습니다.")
    df = pd.concat([pd.read_csv(f) for f in files], ignore_index=True)
    # 같은 사람이 날짜를 바꿔 다시 잰 경우(aro / aro1022)는 한 사람으로 묶는다.
    # 따로 두면 LOPO 에서 같은 몸이 학습·테스트에 동시에 들어가 점수가 부풀려진다.
    df["session"] = df["person"].astype(str)
    df["person"] = df["session"].str.replace(r"\d+$", "", regex=True)
    unknown = set(df["posture"]) - set(LABEL_ORDER)
    if unknown:
        raise SystemExit(f"LABEL_ORDER 에 없는 자세 이름: {sorted(unknown)}")
    return df


def fit_norm(x_raw: np.ndarray):
    return x_raw.mean(axis=0), np.maximum(x_raw.std(axis=0), STD_FLOOR)


def to_input(x_raw: np.ndarray, mean, std) -> np.ndarray:
    return ((x_raw - mean) / std).astype(np.float32)


def train(x: np.ndarray, y: np.ndarray) -> PostureCNN64:
    torch.manual_seed(SEED)
    model = PostureCNN64(N_CLS)
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


def confusion_of(y_true, y_pred) -> np.ndarray:
    m = np.zeros((N_CLS, N_CLS), dtype=int)
    for t, p in zip(y_true, y_pred):
        m[t, p] += 1
    return m


def evaluate_fold(df: pd.DataFrame, test_person: str) -> dict:
    tr = df[df["person"] != test_person]
    te = df[df["person"] == test_person]
    mean, std = fit_norm(tr[CH_COLS].values.astype(np.float32))
    xtr = to_input(tr[CH_COLS].values.astype(np.float32), mean, std)
    xte = to_input(te[CH_COLS].values.astype(np.float32), mean, std)
    ytr = tr["posture"].map(LABEL_TO_IDX).values
    yte = te["posture"].map(LABEL_TO_IDX).values

    pred = predict(train(xtr, ytr), xte)
    conf = confusion_of(yte, pred)
    per_class = {}
    for k, name in enumerate(LABEL_ORDER):
        n = int(conf[k].sum())
        per_class[name] = {"n": n, "recall": float(conf[k, k] / n)} if n else None
    return {
        "test_person": test_person,
        "train_persons": sorted(tr["person"].unique()),
        "train_missing": [c for c in LABEL_ORDER if c not in set(tr["posture"])],
        "n_train": int(len(tr)),
        "n_test": int(len(te)),
        "accuracy": float((pred == yte).mean()),
        "per_class": per_class,
        "confusion": conf.tolist(),
    }


def save_confusion(conf: np.ndarray, title: str, path_png: Path, path_csv: Path):
    pd.DataFrame(conf, index=LABEL_ORDER, columns=LABEL_ORDER).to_csv(path_csv, encoding="utf-8-sig")
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        from matplotlib import font_manager
        for name in ("Malgun Gothic", "AppleGothic", "NanumGothic"):
            if any(f.name == name for f in font_manager.fontManager.ttflist):
                plt.rcParams["font.family"] = name
                break
        plt.rcParams["axes.unicode_minus"] = False
    except ImportError:
        return
    row_sum = conf.sum(axis=1, keepdims=True)
    rate = np.divide(conf, row_sum, out=np.zeros_like(conf, dtype=float), where=row_sum > 0)
    fig, ax = plt.subplots(figsize=(8, 7))
    ax.imshow(rate, cmap="Blues", vmin=0, vmax=1)
    ticks = [f"{i} {KOREAN[i]}" for i in range(N_CLS)]
    ax.set_xticks(range(N_CLS), ticks, rotation=45, ha="right")
    ax.set_yticks(range(N_CLS), ticks)
    ax.set_xlabel("예측")
    ax.set_ylabel("정답")
    ax.set_title(title)
    for i in range(N_CLS):
        for j in range(N_CLS):
            if conf[i, j]:
                ax.text(j, i, f"{rate[i, j] * 100:.0f}%\n({conf[i, j]})", ha="center", va="center",
                        fontsize=7, color="white" if rate[i, j] > 0.5 else "black")
    fig.tight_layout()
    fig.savefig(path_png, dpi=130)
    plt.close(fig)


def main():
    random.seed(SEED)
    np.random.seed(SEED)
    RUN_DIR.mkdir(parents=True, exist_ok=True)

    df = load_raw()
    persons = sorted(df["person"].unique())
    n_files = len([f for f in RAW_DIR.glob("*.csv") if "_reject" not in f.stem])
    print(f"데이터: {len(df)}프레임, 사람 {persons}, 파일 {n_files}개")

    have = df.groupby(["session", "posture"]).size().unstack(fill_value=0).reindex(columns=LABEL_ORDER, fill_value=0)
    print("\n측정 회차 x 자세 프레임 수 (0 = 아직 수집 안 됨). 평가는 이름 뒤 날짜를 뗀 사람 단위.")
    print(have.to_string())
    missing = [c for c in LABEL_ORDER if have[c].sum() == 0]
    if missing:
        print(f"⚠️ 아무도 수집하지 않은 자세: {missing} → 모델이 예측하지 못합니다.")

    folds = []
    total_conf = np.zeros((N_CLS, N_CLS), dtype=int)
    for p in persons:
        r = evaluate_fold(df, p)
        folds.append(r)
        total_conf += np.array(r["confusion"])
        print(f"\n[테스트 {p} / 학습 {r['train_persons']}] 정확도 {r['accuracy'] * 100:.1f}% "
              f"(학습 {r['n_train']} / 테스트 {r['n_test']})")
        if r["train_missing"]:
            print(f"   학습에 없는 자세: {r['train_missing']}")
        for name in LABEL_ORDER:
            c = r["per_class"][name]
            if c:
                print(f"   {name:17s} n={c['n']:5d}  recall {c['recall'] * 100:5.1f}%")
    mean_acc = float(np.mean([f["accuracy"] for f in folds]))
    pooled_acc = float(np.trace(total_conf) / total_conf.sum())
    print(f"\n사람 단위 {len(persons)}-fold 평균 정확도: {mean_acc * 100:.1f}%  (프레임 합산 {pooled_acc * 100:.1f}%)")

    print("\n혼동행렬 합계 (행=정답, 열=예측)")
    short = [f"p{i}" for i in range(N_CLS)]
    print("                    " + " ".join(f"{s:>6}" for s in short))
    for i, name in enumerate(LABEL_ORDER):
        n = total_conf[i].sum()
        rec = f"{total_conf[i, i] / n * 100:5.1f}%" if n else "  -  "
        print(f"  p{i} {name:15s} " + " ".join(f"{v:>6}" for v in total_conf[i]) + f"   {rec}")

    save_confusion(total_conf, f"LOPO {len(persons)}-fold 합계 (평균 정확도 {mean_acc * 100:.1f}%)",
                   RUN_DIR / "confusion_lopo.png", RUN_DIR / "confusion_lopo.csv")

    # 최종 모델: 전체 인원으로 학습 (앱에 넘기는 용도)
    x_raw = df[CH_COLS].values.astype(np.float32)
    mean, std = fit_norm(x_raw)
    model = train(to_input(x_raw, mean, std), df["posture"].map(LABEL_TO_IDX).values)
    torch.save(model.state_dict(), OUT_PT)

    seat_cols = [f"seat_{i + 1}" for i in range(32)]   # 서버 컬럼명: seat_1 = ch0 ... seat_32 = ch31
    back_cols = [f"back_{i + 1}" for i in range(32)]   #            back_1 = ch32 ... back_32 = ch63
    stats = {
        # 앱(PosturePreprocessor)이 읽는 키
        "label_order": LABEL_ORDER,
        "class_index": LABEL_TO_IDX,
        # 서버(server_64ch.py)·리포트·시뮬레이터가 읽는 키 — 같은 json 하나로 앱·서버 모두 쓴다
        "label_classes": [f"p{i}" for i in range(N_CLS)],
        "label_names": {f"p{i}": KOREAN[i] for i in range(N_CLS)},
        "seat_cols_order": seat_cols,
        "back_cols_order": back_cols,
        "sensor_cols_order": seat_cols + back_cols,
        "channels": CH_COLS,
        "channel_layout": "ch0~31 좌석, ch32~63 등받이 (ml/collect_data.py --port-back 저장 순서)",
        "mean": mean.tolist(),
        "std": std.tolist(),
        "std_floor": STD_FLOOR,
        "normalize": "x_norm[i] = (ch[i] - mean[i]) / std[i]   (i = 0..63)",
        "padding": "없음 (64개 모두 실측)",
        "num_classes": N_CLS,
        "trained_on_persons": persons,
        "classes_without_data": missing,
        "person_split_eval": {
            "method": "leave-one-person-out",
            "mean_accuracy": mean_acc,
            "pooled_accuracy": pooled_acc,
            "folds": [{k: f[k] for k in ("test_person", "train_persons", "n_test", "accuracy")} for f in folds],
        },
    }
    OUT_JSON.write_text(json.dumps(stats, ensure_ascii=False, indent=2), encoding="utf-8")
    (RUN_DIR / "lopo_report.json").write_text(
        json.dumps({"mean_accuracy": mean_acc, "pooled_accuracy": pooled_acc,
                    "confusion_total": total_conf.tolist(), "folds": folds},
                   ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\n저장: {OUT_PT.relative_to(ROOT)}, {OUT_JSON.relative_to(ROOT)}, {RUN_DIR.relative_to(ROOT)}/")
    print("다음: python ml/export_tflite_8cls.py  (TFLite 변환 + model_io 기록)")


if __name__ == "__main__":
    main()
