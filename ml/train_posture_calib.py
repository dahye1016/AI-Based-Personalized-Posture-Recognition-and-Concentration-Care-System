"""
train_posture_calib.py — 캘리브레이션 + 두 모델 합치기 + 거북목 규칙 (8자세, 64ch)

앱 입력: [1, 128] float32 = 지금 프레임 원시값 ch0~63 + 캘리브레이션 기준값 ch0~63
  기준값 = 사용자가 정자세(등·어깨를 등받이에 붙임)로 5초 앉았을 때 채널별 평균 (원시값).
  정규화·특징 계산·거북목 규칙은 모두 모델 안에 들어 있다. 앱은 원시값만 넣으면 된다.
출력: [1, 8] 자세별 확률. argmax 가 label_order 인덱스.

모델 안에서 하는 일
  1. 부위 특징 98개: 좌석/등받이 합(log), 등받이 비율, 부위 12곳(엉덩이·허벅지·무릎·허리·등중간·어깨 x 좌우)
     비율과 합(log), 좌석/등받이 오른쪽 비율, 채널별 비율(좌석은 좌석합, 등받이는 등받이합으로 나눔),
     좌우 비율 log(오른/왼) (무릎·엉덩이·어깨·허벅지) + 무릎 균형(작은 쪽/큰 쪽)
  2. 모양 모델: 지금 프레임 특징 -> 8자세 확률
     차이 모델: (지금 프레임 특징 - 기준값 특징) -> 8자세 확률
     두 확률을 반반 평균한다. (모양 모델은 기대기·숙이기에, 차이 모델은 사람마다 다른 정자세에 강하다)
  3. 거북목 규칙: 좌석 합 >= 6000, 등받이 허리+중간 합 >= 400, 어깨 합 <= 60 이면 거북목.

학습 데이터
  - 실측 (data/raw_64ch, _reject 제외) 중 거북목을 뺀 7자세. 거북목은 실측을 쓰지 않는다.
  - 더미 8자세 (data/dummy/chair_64ch_posture_data_dummy.csv.gz, 20프레임마다 1개)
  - 좌우 반전 증강 (줄마다 순서 뒤집기 + 좌우 자세 라벨 교환)
평가: 사람 단위 LOPO. 실측만. 테스트할 사람 녹화가 재료로 들어간 더미는 그 fold 학습에서 뺀다.
  캘리브레이션에 쓴 5초는 평가에서 뺀다.
  '전체 녹화' 와 '정의대로 앉은 녹화(수집 기준 통과)' 두 가지로 보고한다.

실행 (저장소 루트에서):  python ml/train_posture_calib.py
결과: ml/posture_model_calib.pt, ml/posture_model_calib.tflite, ml/norm_stats_calib.json, ml/runs/calib/
"""

import glob
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
import pandas as pd
import torch
import torch.nn as nn

sys.path.insert(0, str(Path(__file__).resolve().parent))
import train_posture_cnn_8cls as T  # noqa: E402  (데이터 로더·수집 기준·라벨 순서 공유)

ROOT = T.ROOT
OUT_PT = ROOT / "ml" / "posture_model_calib.pt"
OUT_TFLITE = ROOT / "ml" / "posture_model_calib.tflite"
OUT_JSON = ROOT / "ml" / "norm_stats_calib.json"
RUN_DIR = ROOT / "ml" / "runs" / "calib"
DUMMY_GZ = ROOT / "data" / "dummy" / "chair_64ch_posture_data_dummy.csv.gz"

CH = T.CH_COLS
L = T.LABEL_TO_IDX
N = T.N_CLS
FPS = 62
CAL_SEC = 5
DUMMY_EVERY = 20
EPOCHS = 25
SEED = 42
W_REL = 0.5             # 차이 모델 비중

# ---- 좌우 반전 -------------------------------------------------------------
ROWS = [(0, 9), (10, 23), (24, 31), (32, 41), (42, 55), (56, 63)]
FLIP = list(range(64))
for a, b in ROWS:
    for k in range(a, b + 1):
        FLIP[k] = a + b - k
SWAP = {"cross_leg_right": "cross_leg_left", "cross_leg_left": "cross_leg_right",
        "lean_right": "lean_left", "lean_left": "lean_right"}

# ---- 부위 (뒤집은 매트 기준) ------------------------------------------------
REG = [("hipL", range(0, 5), "s"), ("hipR", range(5, 10), "s"), ("thL", range(10, 17), "s"),
       ("thR", range(17, 24), "s"), ("knL", range(24, 28), "s"), ("knR", range(28, 32), "s"),
       ("waR", range(32, 37), "b"), ("waL", range(37, 42), "b"), ("miR", range(42, 49), "b"),
       ("miL", range(49, 56), "b"), ("shR", range(56, 60), "b"), ("shL", range(60, 64), "b")]
SEAT_R = list(range(5, 10)) + list(range(17, 24)) + list(range(28, 32))
BACK_R = list(range(32, 37)) + list(range(42, 49)) + list(range(56, 60))
N_FEAT = 3 + 2 * len(REG) + 2 + 64 + 5     # 마지막 5개 = 좌우 비율(무릎·엉덩이·어깨·허벅지) + 무릎 균형


class Features(nn.Module):
    """원시값 [B,64] -> 특징 [B,93]. 고정 행렬만 쓰므로 TFLite 로 그대로 바뀐다."""

    def __init__(self):
        super().__init__()
        reg = torch.zeros(64, len(REG))
        for j, (_, r, _) in enumerate(REG):
            reg[list(r), j] = 1.0
        side = torch.zeros(64, 2)
        side[SEAT_R, 0] = 1.0
        side[BACK_R, 1] = 1.0
        self.register_buffer("reg", reg)
        self.register_buffer("side", side)
        self.register_buffer("is_seat_reg", torch.tensor([1.0 if k == "s" else 0.0 for _, _, k in REG]))

    def forward(self, x):
        seat = x[:, :32].sum(1, keepdim=True) + 1.0
        back = x[:, 32:].sum(1, keepdim=True) + 1.0
        tot = seat + back
        rs = x @ self.reg                                              # [B,12]
        denom = seat * self.is_seat_reg + back * (1.0 - self.is_seat_reg)
        sd = x @ self.side                                             # [B,2]
        # 좌우 비율: 거북목(양쪽 무릎 닿음)과 다리 꼬기(한쪽 무릎 들림)를 몸무게·캘리브레이션과 무관하게 가른다
        kl, kr = x[:, 24:28].sum(1, keepdim=True) + 10.0, x[:, 28:32].sum(1, keepdim=True) + 10.0
        hl, hr = x[:, 0:5].sum(1, keepdim=True) + 10.0, x[:, 5:10].sum(1, keepdim=True) + 10.0
        sl, sr = x[:, 60:64].sum(1, keepdim=True) + 10.0, x[:, 56:60].sum(1, keepdim=True) + 10.0
        tl, tr = x[:, 10:17].sum(1, keepdim=True) + 10.0, x[:, 17:24].sum(1, keepdim=True) + 10.0
        lr = torch.cat([torch.log(kr / kl), torch.log(hr / hl), torch.log(sr / sl), torch.log(tr / tl),
                        torch.minimum(kl, kr) / torch.maximum(kl, kr)], dim=1)
        return torch.cat([
            torch.log1p(seat), torch.log1p(back), back / tot,
            rs / denom, torch.log1p(rs),
            sd[:, :1] / seat, sd[:, 1:] / back,
            x[:, :32] / seat, x[:, 32:] / back,
            lr,
        ], dim=1)


def mlp():
    return nn.Sequential(nn.Linear(N_FEAT, 128), nn.ReLU(), nn.Dropout(0.2),
                         nn.Linear(128, 64), nn.ReLU(), nn.Linear(64, N))


USE_RULE = {"on": True}      # --no-rule 이면 거북목 규칙 없이 모델 판정만


class CalibNet(nn.Module):
    """입력 [B,128] = 지금 프레임 64 + 기준값 64 (원시값). 출력 [B,8] 확률."""

    def __init__(self):
        super().__init__()
        self.use_rule = USE_RULE["on"]
        self.feat = Features()
        self.shape_head = mlp()
        self.diff_head = mlp()
        for name in ("mu_s", "sd_s", "mu_d", "sd_d"):
            self.register_buffer(name, torch.zeros(N_FEAT) if name.startswith("mu") else torch.ones(N_FEAT))
        self.register_buffer("turtle_onehot", torch.eye(N)[L["turtle_neck"]])

    def logits(self, x, b):
        fx, fb = self.feat(x), self.feat(b)
        ls = self.shape_head((fx - self.mu_s) / self.sd_s)
        ld = self.diff_head((fx - fb - self.mu_d) / self.sd_d)
        return ls, ld

    def forward(self, xb):
        x, b = xb[:, :64], xb[:, 64:]
        ls, ld = self.logits(x, b)
        p = (1.0 - W_REL) * torch.softmax(ls, 1) + W_REL * torch.softmax(ld, 1)
        if not self.use_rule:
            return p
        R = T.TURTLE_RULE
        hit = ((x[:, :32].sum(1) >= R["seat_min"]) & (x[:, 32:56].sum(1) >= R["back_min"])
               & (x[:, 56:64].sum(1) <= R["shoulder_max"])).float().unsqueeze(1)
        return hit * self.turtle_onehot + (1.0 - hit) * p


# ---- 데이터 ----------------------------------------------------------------
def flip_df(d):
    f = d.copy()
    f[CH] = d[CH].values[:, FLIP]
    f["posture"] = d["posture"].map(lambda p: SWAP.get(p, p))
    return f


def real_calibration():
    """회차별 기준값: 어깨가 닿은 정자세(어깨 줄 합 >= 200) 처음 5초. 없으면 아무 정자세. _reject 포함."""
    cal, used = {}, {}
    files = sorted(glob.glob(str(ROOT / "data" / "raw_64ch" / "*sitting_straight*.csv")))
    for prefer in (True, False):
        for f in files:
            d = pd.read_csv(f)
            s = str(d["person"].iloc[0])
            if s in cal:
                continue
            good = d[CH].values[:, 56:64].mean(0).sum() >= 200
            if prefer and not good:
                continue
            cal[s] = d[CH].values[:CAL_SEC * FPS].astype(np.float32).mean(0)
            used[s] = (int(d["trial"].iloc[0]), os.path.basename(f))
    return cal, used


def dummy_calibration(dm):
    """가상 참가자별 기준값: 그 사람 정자세 앞부분 평균."""
    cal = {}
    for p, g in dm.groupby("person"):
        st = g[g["posture"] == "sitting_straight"]
        src = st if len(st) else g
        cal[p] = src[CH].values[: max(1, CAL_SEC * FPS // DUMMY_EVERY)].astype(np.float32).mean(0)
    return cal


def assemble(real_tr, dm, cal_real, cal_dm):
    """(X [n,64], B [n,64], y) — 원본 + 좌우 반전."""
    Xs, Bs, ys = [], [], []
    for d, key, cal in ((real_tr, "session", cal_real), (dm, "person", cal_dm)):
        for s, g in d.groupby(key):
            if s not in cal:
                continue
            for flipped in (False, True):
                gg = flip_df(g) if flipped else g
                base = cal[s][FLIP] if flipped else cal[s]
                Xs.append(gg[CH].values.astype(np.float32))
                Bs.append(np.repeat(base[None, :], len(gg), 0))
                ys.append(gg["posture"].map(L).values)
    return np.vstack(Xs), np.vstack(Bs), np.concatenate(ys)


def fit(X, B, y):
    torch.manual_seed(SEED)
    net = CalibNet()
    with torch.no_grad():
        fx = net.feat(torch.tensor(X))
        fd = fx - net.feat(torch.tensor(B))
        net.mu_s.copy_(fx.mean(0)); net.sd_s.copy_(fx.std(0).clamp_min(1e-3))
        net.mu_d.copy_(fd.mean(0)); net.sd_d.copy_(fd.std(0).clamp_min(1e-3))
    counts = np.bincount(y, minlength=N).astype(np.float32)
    w = torch.tensor(np.where(counts > 0, counts.sum() / (N * np.maximum(counts, 1)), 0.0), dtype=torch.float32)
    crit = nn.CrossEntropyLoss(weight=w)
    opt = torch.optim.Adam(list(net.shape_head.parameters()) + list(net.diff_head.parameters()), lr=1e-3)
    Xt, Bt, yt = torch.tensor(X), torch.tensor(B), torch.tensor(y).long()
    n = len(Xt)
    for ep in range(EPOCHS):
        if ep % 5 == 0:
            print(f"      에폭 {ep + 1}/{EPOCHS} (학습 {n:,}행)", flush=True)
        net.train()
        perm = torch.randperm(n)
        for i in range(0, n, 256):
            idx = perm[i:i + 256]
            ls, ld = net.logits(Xt[idx], Bt[idx])
            loss = crit(ls, yt[idx]) + crit(ld, yt[idx])
            opt.zero_grad()
            loss.backward()
            opt.step()
    net.eval()
    return net


def predict(net, X, base):
    xb = np.hstack([X.astype(np.float32), np.repeat(base[None, :], len(X), 0)])
    with torch.no_grad():
        return net(torch.tensor(xb)).argmax(1).numpy()


def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-rule", action="store_true", help="거북목 규칙 없이 모델 판정만 쓴다")
    ap.add_argument("--spec", action="store_true",
                    help="팀 자세 정의(gen_dummy_spec.py)에 맞는 실측 녹화만 학습에 쓰고(거북목 포함), "
                         "평가의 '정의대로 앉은 녹화'도 이 정의로 고른다")
    args = ap.parse_args()
    USE_RULE["on"] = not args.no_rule
    np.random.seed(SEED)
    RUN_DIR.mkdir(parents=True, exist_ok=True)
    T.ONLY_PASSING["on"] = False
    df = T.load_raw()
    if args.spec:
        sys.path.insert(0, str(ROOT))
        import gen_dummy_spec as S
        rec_ok = lambda g: S.spec_ok(str(g["posture"].iloc[0]), g[CH].values.astype(float))
    else:
        rec_ok = T.passes_protocol
    dm = T.load_dummy(DUMMY_GZ, DUMMY_EVERY)
    cal_real, cal_used = real_calibration()
    cal_dm = dummy_calibration(dm)
    persons = sorted(df["person"].unique())
    print(f"실측 {len(df):,}프레임 {persons} / 더미 {len(dm):,}프레임")
    print("캘리브레이션 (회차: 녹화):", {s: f for s, (_, f) in cal_used.items()})

    key = ["session", "posture", "trial"]
    ok = np.zeros(len(df), bool)
    for k, g in df.groupby(key):
        if rec_ok(g):
            ok[g.index] = True
    print("정의에 맞는 실측 녹화:", sorted({f"{k[0]}:{k[1]}" for k, g in df[ok].groupby(key)}))

    def train_real(d):
        """학습에 쓸 실측: --spec 이면 정의에 맞는 녹화만(거북목 포함), 아니면 거북목 뺀 전체."""
        if args.spec:
            return d[ok[d.index]]
        return d[d["posture"] != "turtle_neck"]
    drop = np.zeros(len(df), bool)                       # 캘리브레이션 5초는 평가에서 뺀다
    for s, (trial, _) in cal_used.items():
        m = ((df["session"] == s) & (df["posture"] == "sitting_straight") & (df["trial"] == trial)).values
        drop[np.where(m)[0][:CAL_SEC * FPS]] = True

    conf_all = np.zeros((N, N), int)
    conf_ok = np.zeros((N, N), int)
    folds = []
    for i, p in enumerate(persons):
        print(f"\n[{i + 1}/{len(persons) + 1}] {p} 빼고 학습 중...", flush=True)
        tr = train_real(df[df["person"] != p])
        d = dm[~dm["template_person"].str.split("+").map(lambda ps: p in ps)]
        X, B, y = assemble(tr, d, cal_real, cal_dm)
        net = fit(X, B, y)
        te_mask = (df["person"] == p).values & ~drop
        ca, co = np.zeros((N, N), int), np.zeros((N, N), int)
        for s, g in df[te_mask].groupby("session"):
            if s not in cal_real:
                continue
            pr = predict(net, g[CH].values, cal_real[s])
            yy = g["posture"].map(L).values
            okk = ok[g.index]
            np.add.at(ca, (yy, pr), 1)
            np.add.at(co, (yy[okk], pr[okk]), 1)
        conf_all += ca
        conf_ok += co
        acc = np.trace(co) / co.sum() if co.sum() else float("nan")
        folds.append({"test_person": p, "acc_all": float(np.trace(ca) / ca.sum()), "acc_protocol": float(acc),
                      "confusion_all": ca.tolist(), "confusion_protocol": co.tolist()})
        print(f"   [테스트 {p}] 정의대로 앉은 녹화 {acc * 100:.1f}% / 전체 녹화 {np.trace(ca) / ca.sum() * 100:.1f}%")

    def rates(c):
        return [float(c[i, i] / c[i].sum()) if c[i].sum() else None for i in range(N)]
    r_all, r_ok = rates(conf_all), rates(conf_ok)
    pooled = lambda c: float(np.trace(c) / c.sum())
    print("\n자세별 정확도 (사람 단위, 처음 보는 사람)")
    print("  자세               정의대로 앉은 녹화   전체 녹화")
    for i, name in enumerate(T.LABEL_ORDER):
        f = lambda v: f"{v * 100:6.1f}%" if v is not None else "    -  "
        print(f"  p{i} {name:16s}    {f(r_ok[i])}         {f(r_all[i])}")
    print(f"  합산                   {pooled(conf_ok) * 100:6.1f}%         {pooled(conf_all) * 100:6.1f}%")
    T.save_confusion(conf_ok, f"정의대로 앉은 녹화 LOPO (합산 {pooled(conf_ok) * 100:.1f}%)",
                     RUN_DIR / "confusion_protocol.png", RUN_DIR / "confusion_protocol.csv")
    T.save_confusion(conf_all, f"전체 녹화 LOPO (합산 {pooled(conf_all) * 100:.1f}%)",
                     RUN_DIR / "confusion_all.png", RUN_DIR / "confusion_all.csv")

    # ---- 최종 모델: 전체 인원 ----
    print(f"\n[{len(persons) + 1}/{len(persons) + 1}] 전체 인원으로 최종 모델 학습 중...", flush=True)
    X, B, y = assemble(train_real(df), dm, cal_real, cal_dm)
    net = fit(X, B, y)
    torch.save(net.state_dict(), OUT_PT)

    # ---- TFLite ----
    import tensorflow as tf
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        onnx_path = tmp / "m.onnx"
        torch.onnx.export(net, torch.zeros(1, 128), str(onnx_path), input_names=["input"],
                          output_names=["output"], opset_version=13, dynamo=False)
        exe = Path(sys.executable).parent / "Scripts" / "onnx2tf.exe"
        if not exe.exists():
            exe = Path(sys.executable).parent / "onnx2tf.exe"
        subprocess.run([str(exe) if exe.exists() else "onnx2tf", "-i", str(onnx_path), "-o", str(tmp / "tf"), "-osd"],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        shutil.copy(next((tmp / "tf").glob("*float32*.tflite")), OUT_TFLITE)
    it = tf.lite.Interpreter(model_path=str(OUT_TFLITE))
    it.allocate_tensors()
    ind, outd = it.get_input_details()[0], it.get_output_details()[0]
    agree, total = 0, 0
    for s, g in df.groupby("session"):
        if s not in cal_real:
            continue
        xs = g[CH].values.astype(np.float32)[::5]
        pt = predict(net, xs, cal_real[s])
        for row, q in zip(xs, pt):
            it.set_tensor(ind["index"], np.hstack([row, cal_real[s]])[None, :].astype(np.float32))
            it.invoke()
            agree += int(np.argmax(it.get_tensor(outd["index"])) == q)
            total += 1
    in_shape, out_shape = ind["shape"].tolist(), outd["shape"].tolist()
    agreement = agree / total
    print(f"\nTFLite 입력 {in_shape} / 출력 {out_shape} / PyTorch 와 예측 일치율 {agreement * 100:.2f}% ({total}프레임)")

    stats = {
        "label_order": T.LABEL_ORDER,
        "class_index": L,
        "label_names": {f"p{i}": T.KOREAN[i] for i in range(N)},
        "num_classes": N,
        "model_io": {
            "tflite_file": "posture_model_calib.tflite",
            "input_shape": in_shape,
            "input_dtype": "float32",
            "input_layout": "값 128개 = [지금 프레임 원시값 ch0~63] + [캘리브레이션 기준값 ch0~63]. 정규화하지 말 것 (모델 안에서 함)",
            "output_shape": out_shape,
            "output": "8자세 확률 (argmax 가 label_order 인덱스). 거북목 규칙이 모델 안에 포함됨",
            "pt_vs_tflite_agreement": agreement,
        },
        "raw_input": True,
        "channel_layout": "ch0~31 좌석, ch32~63 등받이 (ml/collect_data.py --port-back 저장 순서)",
        "calibration": {
            "seconds": CAL_SEC,
            "how": "사용자가 정자세(허리·등·어깨를 등받이에 붙임)로 5초 앉는 동안 채널별 원시값 평균 64개를 저장해 두고, "
                   "매 프레임 입력 뒤쪽 64개로 같이 넣는다. 사용자·의자 위치가 바뀌면 다시 잰다.",
        },
        "turtle_rule": (dict(T.TURTLE_RULE, note="모델 안에 포함됨 (앱에서 따로 할 필요 없음)")
                        if USE_RULE["on"] else None),
        "training_mode": {"rule": USE_RULE["on"], "spec": args.spec,
                          "spec_note": "gen_dummy_spec.py 의 SPEC (팀 자세 정의 2026-10-25)" if args.spec else None},
        "ensemble": {"shape_model_weight": 1 - W_REL, "diff_model_weight": W_REL},
        "trained_on_persons": persons,
        "person_split_eval": {
            "method": "leave-one-person-out (실측만, 캘리브레이션 5초 제외)",
            "pooled_accuracy_protocol": pooled(conf_ok),
            "pooled_accuracy_all": pooled(conf_all),
            "per_class_protocol": dict(zip(T.LABEL_ORDER, r_ok)),
            "per_class_all": dict(zip(T.LABEL_ORDER, r_all)),
            "note": "protocol = 수집 기준(합격 기준 + 어깨 기준)을 통과한 녹화만. 자세당 녹화 1~3개라 흔들림이 크다.",
        },
    }
    OUT_JSON.write_text(json.dumps(stats, ensure_ascii=False, indent=2), encoding="utf-8")
    (RUN_DIR / "lopo_report.json").write_text(json.dumps({"folds": folds}, ensure_ascii=False, indent=2),
                                              encoding="utf-8")
    print(f"저장: {OUT_PT.name}, {OUT_TFLITE.name}, {OUT_JSON.name}, runs/calib/")
    if in_shape != [1, 128] or agreement < 0.99:
        sys.exit("⚠️ TFLite 입력 shape 또는 예측 일치율을 확인하세요.")


if __name__ == "__main__":
    main()
