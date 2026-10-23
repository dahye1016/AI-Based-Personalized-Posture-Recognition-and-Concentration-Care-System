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

더미 섞기 (--dummy-dir): gen_dummy_64ch.py 로 만든 더미 CSV 를 학습에만 더한다.
  · 평가(테스트)는 항상 실측만 쓴다.
  · LOPO 에서 테스트할 사람의 녹화로 만든 더미(template_person)는 그 fold 학습에서 뺀다.
    (안 빼면 테스트할 사람의 몸이 학습에 들어가 점수가 부풀려진다.)
  · 정규화 mean/std 는 실측 학습 데이터로만 계산한다.

실행 (저장소 루트에서):
    python ml/train_posture_cnn_8cls.py
    python ml/train_posture_cnn_8cls.py --dummy-dir data/dummy_64ch_turtle   # 거북목 더미 섞기
    # 현재 모델 (2026-10-23, LOPO 68.9%). 옵션 비교는 RUNBOOK_8cls.md 참고
    python ml/train_posture_cnn_8cls.py --dummy-dir data/dummy_64ch_turtle --fill-shoulder --turtle-from-straight
결과: ml/posture_model_8cls.pt, ml/norm_stats_8cls.json, ml/runs/8cls/ (혼동행렬 등)
"""

import argparse
import json
import random
import re
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


def passes_protocol(d: pd.DataFrame) -> bool:
    """녹화 하나가 수집 기준(엑셀 합격 기준 + 어깨 기준, gen_dummy_64ch.py 와 동일)을 통과하는지.
    거북목: 등은 닿고 어깨는 뜸 / 앞으로 숙이기: 등받이 0 / 그 밖의 앉은 자세: 어깨가 등받이에 닿음."""
    import gen_dummy_64ch as G
    p = str(d["posture"].iloc[0])
    X = d[CH_COLS].values.astype(float)
    m = X.mean(0)
    if p == "not_sitting":
        return m[:32].sum() <= G.Q["empty_seat"]
    dur = float(d["timestamp"].iloc[-1] - d["timestamp"].iloc[0])
    if not G.passes(p, G.metrics(X, dur, len(X))):
        return False
    bt = m[32:].sum()
    if p == "turtle_neck":
        return bt >= 400 and m[G.SHOULDER].sum() / bt * 100 <= 3
    if p == "lean_forward":
        return bt <= 100
    return True


ONLY_PASSING = {"on": False}


def load_raw() -> pd.DataFrame:
    files = sorted(f for f in RAW_DIR.glob("*.csv") if "_reject" not in f.stem)
    if not files:
        raise SystemExit(f"{RAW_DIR} 에 CSV 가 없습니다.")
    frames = [pd.read_csv(f) for f in files]
    if ONLY_PASSING["on"]:
        kept = []
        for f, d in zip(files, frames):
            if passes_protocol(d):
                kept.append(d)
            else:
                print(f"  기준 불통과로 제외: {f.name}")
        frames = kept
    df = pd.concat(frames, ignore_index=True)
    # 같은 사람이 날짜를 바꿔 다시 잰 경우(aro / aro1022)는 한 사람으로 묶는다.
    # 따로 두면 LOPO 에서 같은 몸이 학습·테스트에 동시에 들어가 점수가 부풀려진다.
    df["session"] = df["person"].astype(str)
    df["person"] = df["session"].str.replace(r"\d+$", "", regex=True)
    unknown = set(df["posture"]) - set(LABEL_ORDER)
    if unknown:
        raise SystemExit(f"LABEL_ORDER 에 없는 자세 이름: {sorted(unknown)}")
    return df


def load_dummy(dummy_dir: Path, every: int = 1) -> pd.DataFrame:
    """gen_dummy_64ch.py 결과 폴더, 또는 ml/merge_dummy_8cls.py 로 묶은 csv.gz.
    template_person(재료 녹화 주인)을 실측과 같은 규칙으로 정리한다.
    every: N 프레임마다 1개만 쓴다 (연속 프레임은 거의 같아서 학습 시간만 늘어난다)."""
    if dummy_dir.is_file():
        g = pd.read_csv(dummy_dir)
        if not g["Source"].astype(str).str.startswith("gen_").all():
            raise SystemExit("csv.gz 에 재료 정보(Source=gen_<사람>)가 없는 행이 있습니다. "
                             "merge_dummy_8cls.py --gen-dir 로 다시 만드세요.")
        seat = [f"seat_{i + 1}" for i in range(32)]
        back = [f"back_{i + 1}" for i in range(32)]
        df = pd.DataFrame(g[seat + back].values, columns=CH_COLS)
        df["posture"] = g["Label"].str[1:].astype(int).map(dict(enumerate(LABEL_ORDER))).values
        df["person"] = g["Person"].values
        df["template_person"] = g["Source"].str[len("gen_"):].values
    else:
        files = sorted(dummy_dir.rglob("*.csv"))
        if not files:
            raise SystemExit(f"{dummy_dir} 에 더미 CSV 가 없습니다.")
        df = pd.concat([pd.read_csv(f) for f in files], ignore_index=True)
    if every > 1:
        df = df.iloc[::every].reset_index(drop=True)
    if "template_person" not in df.columns:
        raise SystemExit("더미 CSV 에 template_person 컬럼이 없습니다. gen_dummy_64ch.py 로 다시 만드세요.")
    unknown = set(df["posture"]) - set(LABEL_ORDER)
    if unknown:
        raise SystemExit(f"더미에 LABEL_ORDER 에 없는 자세: {sorted(unknown)}")
    # "aro1022+dahye" (등받이 재료 + 좌석 재료) -> "aro+dahye"
    df["template_person"] = df["template_person"].astype(str).map(
        lambda s: "+".join(sorted({re.sub(r"\d+$", "", x) for x in s.split("+")})))
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
    for ep in range(EPOCHS):
        if ep % 10 == 0:
            print(f"      에폭 {ep + 1}/{EPOCHS} (학습 {n:,}행)", flush=True)
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


SHOULDER = [f"ch{i}" for i in range(56, 64)]   # 등받이 어깨 줄
BACK_LOW = [f"ch{i}" for i in range(32, 56)]   # 등받이 허리·중간 줄
OPTS = {"turtle_from_straight": False, "drop_straight_no_shoulder": False, "fill_shoulder": False,
        "no_real_train": []}   # 학습에서 뺄 실측 자세 (평가에는 남김). 예: ["turtle_neck"]
# 어깨가 등받이에 닿아야 하는 자세 (거북목·앞으로 숙이기·앉지 않음 제외)
SHOULDER_POSTURES = ["sitting_straight", "cross_leg_right", "cross_leg_left", "lean_right", "lean_left"]
SHOULDER_OK = 200      # 정자세에서 어깨가 '닿았다'고 볼 어깨 줄 합
SHOULDER_NONE = 100    # 이보다 작으면 정자세인데 어깨가 안 닿은 녹화


def fill_shoulder(tr: pd.DataFrame, key: list) -> pd.DataFrame:
    """[가짜 데이터] 어깨가 닿아야 하는 자세인데 어깨 줄이 비어 있는 녹화에, 어깨가 닿은 녹화의
    같은 자세 평균 어깨 압력을 채운다. 같은 자세 재료가 없으면 정자세 재료를 쓴다.
    재료는 학습 데이터 안에서만 고른다 (테스트할 사람 데이터는 쓰지 않음).
    이렇게 하면 '어깨가 비어 있음'은 거북목에만 남는다. 실제 측정값이 아니므로 평가에는 쓰지 않는다."""
    rng = np.random.default_rng(SEED)
    sh = tr.groupby(key)[SHOULDER].mean()
    total = sh.sum(axis=1)
    tmpl = {}
    for p in SHOULDER_POSTURES:
        ok = sh[(total >= SHOULDER_OK) & (sh.index.get_level_values("posture") == p)]
        if len(ok):
            tmpl[p] = ok.mean().values
    if "sitting_straight" not in tmpl:
        return tr                                   # 재료가 없으면 아무것도 안 함
    out = tr.copy()
    rec_key = out[key].apply(tuple, axis=1)
    for k in total[(total < SHOULDER_NONE)].index:
        if k[1] not in SHOULDER_POSTURES:
            continue
        m = (rec_key == k).values
        base = tmpl.get(k[1], tmpl["sitting_straight"])
        noise = rng.normal(1.0, 0.08, (m.sum(), len(SHOULDER)))
        out.loc[m, SHOULDER] = np.clip(np.round(base * rng.uniform(0.7, 1.3) * noise), 0, 1064)
    return out


def adjust_training(tr: pd.DataFrame) -> pd.DataFrame:
    """학습 데이터에만 적용 (평가 데이터는 건드리지 않는다).

    turtle_from_straight: 어깨가 닿은 정자세 녹화에서 어깨 줄을 0 으로 떼고 등 압력을 줄여
        거북목(등은 닿고 어깨만 뜸) 샘플을 만든다. 녹화 1개당 2벌 (등 압력 x0.6, x0.9).
    drop_straight_no_shoulder: 어깨가 안 닿은 정자세 녹화를 학습에서 뺀다
        (거북목과 숫자가 같아서 '어깨가 비어도 정자세'로 잘못 가르치기 때문).
    """
    if OPTS["no_real_train"]:
        tr = tr[~tr["posture"].isin(OPTS["no_real_train"])]
    if not (OPTS["turtle_from_straight"] or OPTS["drop_straight_no_shoulder"] or OPTS["fill_shoulder"]):
        return tr
    key = ["session", "posture", "trial"]
    if OPTS["fill_shoulder"]:
        tr = fill_shoulder(tr, key)
    straight = tr[tr["posture"] == "sitting_straight"]
    sh = straight.groupby(key)[SHOULDER].mean().sum(axis=1)
    out = tr
    if OPTS["drop_straight_no_shoulder"]:
        bad = set(sh[sh < SHOULDER_NONE].index)
        keep = ~tr[key].apply(tuple, axis=1).isin(bad)
        out = tr[keep]
    if OPTS["turtle_from_straight"]:
        good = set(sh[sh >= SHOULDER_OK].index)
        src = straight[straight[key].apply(tuple, axis=1).isin(good)]
        made = []
        for f in (0.6, 0.9):
            t = src.copy()
            t[SHOULDER] = 0
            t[BACK_LOW] = (t[BACK_LOW] * f).round()
            t["posture"] = "turtle_neck"
            made.append(t)
        if made:
            out = pd.concat([out] + made, ignore_index=True)
    return out


# 거북목 규칙: 팀 정의(등은 닿고 어깨만 뜸)를 숫자로 옮긴 것. 모델 판정 뒤에 덮어쓴다.
# 앱도 같은 규칙을 쓰도록 norm_stats json 의 "turtle_rule" 에 저장한다.
TURTLE_RULE = {
    "seat_min": 6000,        # 좌석 ch0~31 합: 앉아 있음
    "back_min": 400,         # 등받이 허리·중간 ch32~55 합: 등이 닿음
    "shoulder_max": 60,      # 등받이 어깨 ch56~63 합: 어깨가 뜸
}


def apply_turtle_rule(pred: np.ndarray, x_raw: np.ndarray) -> np.ndarray:
    """원시값(정규화 전) 프레임에 규칙이 맞으면 거북목으로 바꾼다."""
    seat = x_raw[:, :32].sum(1)
    back = x_raw[:, 32:56].sum(1)
    shoulder = x_raw[:, 56:64].sum(1)
    hit = (seat >= TURTLE_RULE["seat_min"]) & (back >= TURTLE_RULE["back_min"]) & \
          (shoulder <= TURTLE_RULE["shoulder_max"])
    out = pred.copy()
    out[hit] = LABEL_TO_IDX["turtle_neck"]
    return out


def evaluate_fold(df: pd.DataFrame, test_person: str, dummy: pd.DataFrame | None) -> dict:
    tr = df[df["person"] != test_person]
    te = df[df["person"] == test_person]
    mean, std = fit_norm(tr[CH_COLS].values.astype(np.float32))
    tr = adjust_training(tr)
    n_dummy = 0
    if dummy is not None:
        # 테스트할 사람 녹화가 재료로 (하나라도) 들어간 더미는 뺀다
        dm = dummy[~dummy["template_person"].str.split("+").map(lambda ps: test_person in ps)]
        n_dummy = len(dm)
        tr = pd.concat([tr, dm], ignore_index=True)
    xtr = to_input(tr[CH_COLS].values.astype(np.float32), mean, std)
    xte = to_input(te[CH_COLS].values.astype(np.float32), mean, std)
    ytr = tr["posture"].map(LABEL_TO_IDX).values
    yte = te["posture"].map(LABEL_TO_IDX).values

    pred = predict(train(xtr, ytr), xte)
    pred_rule = apply_turtle_rule(pred, te[CH_COLS].values.astype(np.float32))
    conf = confusion_of(yte, pred)
    conf_rule = confusion_of(yte, pred_rule)
    # 정의대로 앉은(수집 기준 통과) 녹화만 따로 평가
    key = ["session", "posture", "trial"]
    ok_keys = {k for k, g in te.groupby(key) if passes_protocol(g)}
    ok = te[key].apply(tuple, axis=1).isin(ok_keys).values
    conf_ok = confusion_of(yte[ok], pred[ok])
    conf_rule_ok = confusion_of(yte[ok], pred_rule[ok])
    per_class = {}
    for k, name in enumerate(LABEL_ORDER):
        n = int(conf[k].sum())
        per_class[name] = {"n": n, "recall": float(conf[k, k] / n)} if n else None
    return {
        "test_person": test_person,
        "train_persons": sorted(df[df["person"] != test_person]["person"].unique()),
        "train_missing": [c for c in LABEL_ORDER if c not in set(tr["posture"])],
        "n_train": int(len(tr)),
        "n_train_dummy": int(n_dummy),
        "n_test": int(len(te)),
        "accuracy": float((pred == yte).mean()),
        "per_class": per_class,
        "confusion": conf.tolist(),
        "accuracy_rule": float((pred_rule == yte).mean()),
        "confusion_rule": conf_rule.tolist(),
        "confusion_ok": conf_ok.tolist(),
        "confusion_rule_ok": conf_rule_ok.tolist(),
        "accuracy_rule_ok": float((pred_rule[ok] == yte[ok]).mean()) if ok.any() else None,
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
    ap = argparse.ArgumentParser()
    ap.add_argument("--dummy-dir", default="",
                    help="학습에만 더할 더미. gen_dummy_64ch.py 결과 폴더 또는 "
                         "data/dummy/chair_64ch_posture_data_dummy.csv.gz")
    ap.add_argument("--dummy-every", type=int, default=10,
                    help="더미는 N 프레임마다 1개만 쓴다 (기본 10)")
    ap.add_argument("--turtle-from-straight", action="store_true",
                    help="어깨가 닿은 정자세에서 어깨 줄을 떼어 거북목 샘플을 만들어 학습에 더한다")
    ap.add_argument("--drop-straight-no-shoulder", action="store_true",
                    help="어깨가 안 닿은 정자세 녹화를 학습에서 뺀다 (평가에는 남김)")
    ap.add_argument("--fill-shoulder", action="store_true",
                    help="[가짜 데이터] 어깨가 안 닿게 찍힌 정자세·다리꼬기·기대기에 어깨 압력을 채워 학습 (평가는 실측 그대로)")
    ap.add_argument("--dummy-postures", default="",
                    help="더미에서 이 자세만 쓴다 (쉼표). 예: turtle_neck")
    ap.add_argument("--no-real-train", default="",
                    help="이 자세의 실측은 학습에서 뺀다 (평가에는 남김, 쉼표). 예: turtle_neck")
    ap.add_argument("--only-passing", action="store_true",
                    help="실측도 수집 기준(합격 기준 + 어깨 기준)을 통과한 녹화만 학습·평가에 쓴다")
    ap.add_argument("--no-save", action="store_true", help="평가만 하고 모델·json 은 저장하지 않는다 (실험용)")
    args = ap.parse_args()
    OPTS["turtle_from_straight"] = args.turtle_from_straight
    OPTS["drop_straight_no_shoulder"] = args.drop_straight_no_shoulder
    OPTS["fill_shoulder"] = args.fill_shoulder
    ONLY_PASSING["on"] = args.only_passing
    OPTS["no_real_train"] = [p.strip() for p in args.no_real_train.split(",") if p.strip()]

    random.seed(SEED)
    np.random.seed(SEED)
    RUN_DIR.mkdir(parents=True, exist_ok=True)

    df = load_raw()
    dummy = None
    if args.dummy_dir:
        dummy_dir = (ROOT / args.dummy_dir).resolve()
        dummy = load_dummy(dummy_dir, args.dummy_every)
        keep_p = [p.strip() for p in args.dummy_postures.split(",") if p.strip()]
        if keep_p:
            dummy = dummy[dummy["posture"].isin(keep_p)].reset_index(drop=True)
        print(f"더미(학습에만 사용): {len(dummy)}프레임 {dummy_dir.relative_to(ROOT)}  "
              f"자세 {sorted(dummy['posture'].unique())}, 재료 {sorted(dummy['template_person'].unique())}")
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
        print(f"\n[{persons.index(p) + 1}/{len(persons) + 1}] {p} 빼고 학습 중...", flush=True)
        r = evaluate_fold(df, p, dummy)
        folds.append(r)
        total_conf += np.array(r["confusion"])
        dm_note = f", 그중 더미 {r['n_train_dummy']}" if dummy is not None else ""
        print(f"\n[테스트 {p} / 학습 {r['train_persons']}] 정확도 {r['accuracy'] * 100:.1f}% "
              f"(학습 {r['n_train']}{dm_note} / 테스트 {r['n_test']})")
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

    rule_conf = sum(np.array(f["confusion_rule"]) for f in folds)
    rule_mean = float(np.mean([f["accuracy_rule"] for f in folds]))
    print(f"\n[거북목 규칙 적용] 사람 단위 평균 {rule_mean * 100:.1f}%  (규칙: {TURTLE_RULE})")
    ok_conf = sum(np.array(f["confusion_ok"]) for f in folds)
    rule_ok_conf = sum(np.array(f["confusion_rule_ok"]) for f in folds)
    ok_means = [f["accuracy_rule_ok"] for f in folds if f["accuracy_rule_ok"] is not None]
    rule_ok_mean = float(np.mean(ok_means)) if ok_means else float("nan")

    def rate(c, i):
        n = c[i].sum()
        return f"{c[i, i] / n * 100:6.1f}%" if n else "     - "

    print("  자세                [전체 녹화] 모델만  모델+규칙 | [정의대로 앉은 녹화] 모델만  모델+규칙  (녹화 프레임 수)")
    for i, name in enumerate(LABEL_ORDER):
        print(f"  r{i} {name:15s}  {rate(total_conf, i)}  {rate(rule_conf, i)}  |  "
              f"{rate(ok_conf, i)}  {rate(rule_ok_conf, i)}  ({int(ok_conf[i].sum())})")
    pooled = lambda c: np.trace(c) / c.sum() * 100
    print(f"  프레임 합산          {pooled(total_conf):6.1f}%  {pooled(rule_conf):6.1f}%  |  "
          f"{pooled(ok_conf):6.1f}%  {pooled(rule_ok_conf):6.1f}%")
    print(f"  사람 단위 평균 (정의대로 앉은 녹화, 모델+규칙): {rule_ok_mean * 100:.1f}%")

    if args.no_save:
        print("\n(--no-save: 모델·json·혼동행렬은 저장하지 않음)")
        return

    save_confusion(total_conf, f"LOPO {len(persons)}-fold 합계 (평균 정확도 {mean_acc * 100:.1f}%)",
                   RUN_DIR / "confusion_lopo.png", RUN_DIR / "confusion_lopo.csv")

    # 최종 모델: 전체 인원으로 학습 (앱에 넘기는 용도)
    print(f"\n[{len(persons) + 1}/{len(persons) + 1}] 전체 인원으로 최종 모델 학습 중...", flush=True)
    x_raw = df[CH_COLS].values.astype(np.float32)
    mean, std = fit_norm(x_raw)               # 정규화는 실측으로만
    full = adjust_training(df)
    full = full if dummy is None else pd.concat([full, dummy], ignore_index=True)
    model = train(to_input(full[CH_COLS].values.astype(np.float32), mean, std),
                  full["posture"].map(LABEL_TO_IDX).values)
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
        "training_options": dict(OPTS, only_passing=ONLY_PASSING["on"]),
        "turtle_rule": dict(TURTLE_RULE, how="모델 argmax 뒤에, 원시값(정규화 전)으로 계산해서 맞으면 turtle_neck 으로 덮어쓴다. "
                                         "seat=ch0~31 합, back=ch32~55 합, shoulder=ch56~63 합",
                            lopo_mean_accuracy_with_rule=rule_mean,
                            lopo_mean_accuracy_with_rule_protocol_only=rule_ok_mean),
        "dummy_in_training": None if dummy is None else {
            "dir": args.dummy_dir,
            "frames": int(len(dummy)),
            "every": args.dummy_every,
            "postures": sorted(dummy["posture"].unique()),
            "template_persons": sorted(dummy["template_person"].unique()),
            "rule": "학습에만 사용. LOPO 에서는 테스트할 사람 녹화로 만든 더미 제외. 평가와 정규화는 실측만.",
        },
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
