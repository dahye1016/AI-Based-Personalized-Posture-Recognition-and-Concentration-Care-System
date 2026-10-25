"""
train_posture_gbt.py — 캘리브레이션 + 두 부스팅 모델(모양/차이) 합치기, 규칙 없음 (8자세, 64ch)

train_posture_calib.py 와 입력·출력·특징이 같다. 분류기만 신경망 대신 부스팅(HistGradientBoosting)이다.
  (같은 데이터·특징에서 신경망은 처음 보는 사람의 거북목을 못 맞혔고, 부스팅은 맞혔다)

앱 입력: [1, 128] float32 = 지금 프레임 원시값 ch0~63 + 캘리브레이션 기준값(정자세 5초 평균) ch0~63
출력: [1, 8] 자세별 확률 (argmax = label_order 인덱스). 규칙 없음.

TFLite 변환: 부스팅의 나무들을 행렬 계산으로 옮긴다 (GEMM 방식)
  나무마다  T = (특징[선택] <= 기준값)  ->  leaf = (T @ C == D)  ->  leaf @ 값
  C: 내부노드 x 잎 (왼쪽으로 가면 +1, 오른쪽 -1), D: 그 잎까지 왼쪽으로 간 횟수.
  변환 뒤 sklearn 예측과 TFLite 예측이 같은지 검사한다.

학습 데이터: 팀 자세 정의(gen_dummy_spec.py)에 맞는 실측 + 더미 8자세 + 좌우 반전
평가: 사람 단위 LOPO (실측만, 캘리브레이션 5초 제외), '정의에 맞는 녹화' / '전체 녹화'

실행 (저장소 루트에서):  python ml/train_posture_gbt.py
결과: ml/posture_model_gbt.tflite, ml/posture_model_gbt.pkl, ml/norm_stats_gbt.json, ml/runs/gbt/
"""

import json
import pickle
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
from sklearn.ensemble import HistGradientBoostingClassifier

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import train_posture_calib as C  # noqa: E402
import gen_dummy_spec as S  # noqa: E402

T = C.T
ROOT = C.ROOT
OUT_TFLITE = ROOT / "ml" / "posture_model_gbt.tflite"
OUT_PKL = ROOT / "ml" / "posture_model_gbt.pkl"
OUT_JSON = ROOT / "ml" / "norm_stats_gbt.json"
RUN_DIR = ROOT / "ml" / "runs" / "gbt"
CH, L, N = C.CH, C.L, C.N           # N = 8 (평가용 혼동행렬은 8x8 로 두고 뺀 자세 칸은 비워 둔다)
# 2026-10-25: 거북목은 학습·평가·출력에서 뺀다 (7자세). 거북목이 마지막 번호(p7)라 나머지 번호 p0~p6 은 그대로다.
DROP = ["turtle_neck"]
LABELS = [p for p in T.LABEL_ORDER if p not in DROP]
assert LABELS == T.LABEL_ORDER[:len(LABELS)], "뺀 자세가 마지막 번호가 아니면 번호가 밀린다"
N_OUT = len(LABELS)                 # 모델 출력 개수 (7)
W_DIFF = 0.5
EVERY = 3            # 학습 데이터 3행마다 1개 (연속 프레임은 거의 같다)
GBT = dict(max_iter=200, learning_rate=0.1, class_weight="balanced", random_state=42)

FEAT = C.Features()


N_LR = 5   # Features 마지막 5개 = 좌우 비율·무릎 균형. 차이 모델에도 '차이'가 아니라 지금 값 그대로 넣는다
           # (양쪽 무릎이 지금 다 닿았는지가 거북목/다리 꼬기를 가르는 정보라서)


def features(X, B):
    with torch.no_grad():
        fx = FEAT(torch.tensor(X, dtype=torch.float32)).numpy()
        fb = FEAT(torch.tensor(B, dtype=torch.float32)).numpy()
    fd = fx - fb
    fd[:, -N_LR:] = fx[:, -N_LR:]
    return fx, fd


def fit(X, B, y):
    fa, fd = features(X[::EVERY], B[::EVERY])
    ys = y[::EVERY]
    return (HistGradientBoostingClassifier(**GBT).fit(fa, ys),
            HistGradientBoostingClassifier(**GBT).fit(fd, ys))


def proba(models, X, B):
    fa, fd = features(X, B)
    ma, md = models
    out = np.zeros((len(X), N_OUT))
    out[:, ma.classes_] += (1 - W_DIFF) * ma.predict_proba(fa)
    out[:, md.classes_] += W_DIFF * md.predict_proba(fd)
    return out


# ---- 부스팅 -> 텐서 연산 -----------------------------------------------------
class TreeEnsemble(nn.Module):
    """sklearn HistGradientBoostingClassifier 를 행렬 계산으로. 입력 특징 [B,F] -> 클래스 점수 [B,N]."""

    def __init__(self, model):
        super().__init__()
        preds = model._predictors                       # [iter][class] TreePredictor
        k = len(preds[0])
        trees, cls = [], []
        for it in preds:
            for c, tp in enumerate(it):
                trees.append(tp.nodes)
                cls.append(int(model.classes_[c]))
        ni = max(max(int((~nd["is_leaf"].astype(bool)).sum()), 1) for nd in trees)
        nl = max(int(nd["is_leaf"].astype(bool).sum()) for nd in trees)
        nt = len(trees)
        feat = np.zeros((nt, ni), np.int64)
        thr = np.full((nt, ni), np.inf, np.float32)
        Cm = np.zeros((nt, ni, nl), np.float32)
        Dm = np.full((nt, nl), -1.0, np.float32)
        V = np.zeros((nt, nl), np.float32)
        for t, nd in enumerate(trees):
            internal = [i for i in range(len(nd)) if not nd["is_leaf"][i]]
            leaves = [i for i in range(len(nd)) if nd["is_leaf"][i]]
            pos = {n: j for j, n in enumerate(internal)}
            for n, j in pos.items():
                feat[t, j] = int(nd["feature_idx"][n])
                thr[t, j] = float(nd["num_threshold"][n])
            parent = {}
            for n in internal:
                parent[int(nd["left"][n])] = (n, True)
                parent[int(nd["right"][n])] = (n, False)
            for li, leaf in enumerate(leaves):
                V[t, li] = float(nd["value"][leaf])
                lefts, cur = 0, leaf
                while cur in parent:
                    p, is_left = parent[cur]
                    Cm[t, pos[p], li] = 1.0 if is_left else -1.0
                    lefts += int(is_left)
                    cur = p
                Dm[t, li] = float(lefts)
            if not internal:                             # 잎 하나뿐인 나무
                Dm[t, 0] = 0.0
        onehot = np.zeros((nt, N_OUT), np.float32)
        onehot[np.arange(nt), cls] = 1.0
        base = np.zeros(N_OUT, np.float32)
        base[model.classes_] = np.ravel(model._baseline_prediction).astype(np.float32)
        missing = [c for c in range(N_OUT) if c not in set(model.classes_)]
        base[missing] = -1e4
        self.register_buffer("feat", torch.tensor(feat.reshape(-1)))
        self.register_buffer("thr", torch.tensor(np.where(np.isinf(thr), 3.0e38, thr).reshape(1, nt, ni)))
        self.register_buffer("Cm", torch.tensor(Cm))
        self.register_buffer("Dm", torch.tensor(Dm))
        self.register_buffer("V", torch.tensor(V))
        self.register_buffer("onehot", torch.tensor(onehot))
        self.register_buffer("base", torch.tensor(base))
        self.nt, self.ni = nt, ni

    def forward(self, f):                                # f [B,F]
        sel = torch.index_select(f, 1, self.feat).reshape(-1, self.nt, self.ni)
        t = (sel <= self.thr).float()                    # [B,nt,ni]
        s = torch.matmul(t.transpose(0, 1), self.Cm)     # [nt,B,nl]
        leaf = (torch.abs(s - self.Dm.unsqueeze(1)) < 0.5).float()
        val = (leaf * self.V.unsqueeze(1)).sum(2)        # [nt,B]
        return val.transpose(0, 1) @ self.onehot + self.base


class GBTNet(nn.Module):
    def __init__(self, models):
        super().__init__()
        self.feat = C.Features()
        self.shape_trees = TreeEnsemble(models[0])
        self.diff_trees = TreeEnsemble(models[1])

    def forward(self, xb):
        x, b = xb[:, :64], xb[:, 64:]
        fx, fb = self.feat(x), self.feat(b)
        fd = torch.cat([fx[:, :-N_LR] - fb[:, :-N_LR], fx[:, -N_LR:]], dim=1)
        pa = torch.softmax(self.shape_trees(fx), 1)
        pd = torch.softmax(self.diff_trees(fd), 1)
        return (1 - W_DIFF) * pa + W_DIFF * pd


def main():
    RUN_DIR.mkdir(parents=True, exist_ok=True)
    T.ONLY_PASSING["on"] = False
    df = T.load_raw()
    df = df[~df["posture"].isin(DROP)].reset_index(drop=True)          # 뺀 자세는 학습·평가 모두 제외
    dm = T.load_dummy(C.DUMMY_GZ, C.DUMMY_EVERY)
    dm = dm[~dm["posture"].isin(DROP)].reset_index(drop=True)
    print(f"뺀 자세: {DROP} -> 출력 {N_OUT}자세 {LABELS}")
    cal, used = C.real_calibration()
    cdm = C.dummy_calibration(dm)
    persons = sorted(df["person"].unique())
    key = ["session", "posture", "trial"]
    ok = np.zeros(len(df), bool)
    for k, g in df.groupby(key):
        if S.spec_ok(str(g["posture"].iloc[0]), g[CH].values.astype(float)):
            ok[g.index] = True
    drop = np.zeros(len(df), bool)
    for s, (trial, _) in used.items():
        m = ((df["session"] == s) & (df["posture"] == "sitting_straight") & (df["trial"] == trial)).values
        drop[np.where(m)[0][:C.CAL_SEC * C.FPS]] = True
    print(f"실측 {len(df):,}프레임 {persons} / 더미 {len(dm):,}프레임 / 정의에 맞는 실측 프레임 {int(ok.sum()):,}")

    conf_all, conf_ok, folds = np.zeros((N, N), int), np.zeros((N, N), int), []
    for i, p in enumerate(persons):
        print(f"\n[{i + 1}/{len(persons) + 1}] {p} 빼고 학습 중...", flush=True)
        tr = df[df["person"] != p]
        tr = tr[ok[tr.index]]
        d = dm[~dm["template_person"].str.split("+").map(lambda ps: p in ps)]
        models = fit(*C.assemble(tr, d, cal, cdm))
        ca, co = np.zeros((N, N), int), np.zeros((N, N), int)
        for s, g in df[(df["person"] == p).values & ~drop].groupby("session"):
            if s not in cal:
                continue
            X = g[CH].values.astype(np.float32)
            pr = proba(models, X, np.repeat(cal[s][None], len(X), 0)).argmax(1)
            yy = g["posture"].map(L).values
            okk = ok[g.index]
            np.add.at(ca, (yy, pr), 1)
            np.add.at(co, (yy[okk], pr[okk]), 1)
        conf_all += ca
        conf_ok += co
        folds.append({"test_person": p, "confusion_all": ca.tolist(), "confusion_protocol": co.tolist()})
        print(f"   [테스트 {p}] 정의에 맞는 녹화 {np.trace(co) / max(co.sum(), 1) * 100:.1f}% / "
              f"전체 녹화 {np.trace(ca) / ca.sum() * 100:.1f}%", flush=True)

    rates = lambda c: [float(c[i, i] / c[i].sum()) if c[i].sum() else None for i in range(N)]
    pooled = lambda c: float(np.trace(c) / c.sum())
    r_ok, r_all = rates(conf_ok), rates(conf_all)
    print("\n자세별 정확도 (사람 단위, 처음 보는 사람)\n  자세               정의에 맞는 녹화   전체 녹화")
    for i, name in enumerate(LABELS):
        f = lambda v: f"{v * 100:6.1f}%" if v is not None else "    -  "
        print(f"  p{i} {name:16s}    {f(r_ok[i])}         {f(r_all[i])}")
    print(f"  합산                   {pooled(conf_ok) * 100:6.1f}%         {pooled(conf_all) * 100:6.1f}%")
    T.save_confusion(conf_ok, f"정의에 맞는 녹화 LOPO (합산 {pooled(conf_ok) * 100:.1f}%)",
                     RUN_DIR / "confusion_protocol.png", RUN_DIR / "confusion_protocol.csv")
    T.save_confusion(conf_all, f"전체 녹화 LOPO (합산 {pooled(conf_all) * 100:.1f}%)",
                     RUN_DIR / "confusion_all.png", RUN_DIR / "confusion_all.csv")

    print(f"\n[{len(persons) + 1}/{len(persons) + 1}] 전체 인원으로 최종 모델 학습 중...", flush=True)
    models = fit(*C.assemble(df[ok], dm, cal, cdm))
    OUT_PKL.write_bytes(pickle.dumps(models))

    # ---- 텐서 연산으로 옮기고 sklearn 과 같은지 확인 ----
    net = GBTNet(models).eval()
    check_x, check_b, ref = [], [], []
    for s, g in df.groupby("session"):
        if s not in cal:
            continue
        X = g[CH].values.astype(np.float32)[::10]
        check_x.append(X)
        check_b.append(np.repeat(cal[s][None], len(X), 0))
    Xc, Bc = np.vstack(check_x), np.vstack(check_b)
    ref = proba(models, Xc, Bc).argmax(1)
    with torch.no_grad():
        pt = net(torch.tensor(np.hstack([Xc, Bc]))).argmax(1).numpy()
    print(f"sklearn vs 텐서 변환 예측 일치율 {(pt == ref).mean() * 100:.2f}% ({len(ref)}프레임)")

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
    tfl = []
    for row in np.hstack([Xc, Bc]):
        it.set_tensor(ind["index"], row[None, :].astype(np.float32))
        it.invoke()
        tfl.append(int(np.argmax(it.get_tensor(outd["index"]))))
    agree = float((np.array(tfl) == ref).mean())
    in_shape, out_shape = ind["shape"].tolist(), outd["shape"].tolist()
    print(f"TFLite 입력 {in_shape} / 출력 {out_shape} / sklearn 과 예측 일치율 {agree * 100:.2f}% "
          f"/ 파일 {OUT_TFLITE.stat().st_size / 1e6:.1f}MB")

    stats = {
        "label_order": LABELS,
        "class_index": {p: L[p] for p in LABELS},
        "label_names": {f"p{i}": T.KOREAN[i] for i in range(N_OUT)},
        "num_classes": N_OUT,
        "dropped_postures": DROP,
        "model_io": {
            "tflite_file": OUT_TFLITE.name,
            "input_shape": in_shape,
            "input_dtype": "float32",
            "input_layout": "값 128개 = [지금 프레임 원시값 ch0~63] + [캘리브레이션 기준값 ch0~63]. 정규화하지 말 것",
            "output_shape": out_shape,
            "output": f"{N_OUT}자세 확률 (argmax 가 label_order 인덱스). 규칙 없음. 거북목 없음",
            "sklearn_vs_tflite_agreement": agree,
        },
        "raw_input": True,
        "channel_layout": "ch0~31 좌석, ch32~63 등받이 (ml/collect_data.py --port-back 저장 순서)",
        "calibration": {
            "seconds": C.CAL_SEC,
            "how": "정자세(허리·등·어깨를 등받이에 붙임)로 5초 앉는 동안 채널별 원시값 평균 64개를 저장해 두고, "
                   "매 프레임 입력 뒤쪽 64개로 같이 넣는다.",
        },
        "model": {"type": "HistGradientBoosting x2 (모양 / 캘리브레이션 차이), 확률 평균", "params": GBT,
                  "diff_weight": W_DIFF, "posture_spec": "gen_dummy_spec.py SPEC (2026-10-25)"},
        "trained_on_persons": persons,
        "person_split_eval": {
            "method": "leave-one-person-out (실측만, 캘리브레이션 5초 제외)",
            "pooled_accuracy_spec": pooled(conf_ok), "pooled_accuracy_all": pooled(conf_all),
            "per_class_spec": dict(zip(LABELS, r_ok)), "per_class_all": dict(zip(LABELS, r_all)),
        },
    }
    OUT_JSON.write_text(json.dumps(stats, ensure_ascii=False, indent=2), encoding="utf-8")
    (RUN_DIR / "lopo_report.json").write_text(json.dumps({"folds": folds}, ensure_ascii=False, indent=2),
                                              encoding="utf-8")
    print(f"저장: {OUT_TFLITE.name}, {OUT_PKL.name}, {OUT_JSON.name}, runs/gbt/")
    if in_shape != [1, 128] or agree < 0.99:
        sys.exit("⚠️ TFLite 입력 shape 또는 예측 일치율을 확인하세요.")


if __name__ == "__main__":
    main()
