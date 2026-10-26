"""
gen_dummy_device.py — 지금 기기(labchair) 녹화로 가상 사용자 더미 만들기

녹화가 한 사람(다혜)뿐이라 사람을 섞지 않고, 녹화 하나에 변화를 줘서 가상 사용자를 만든다.
  - 체중 배율 0.8~1.25 (가상 사용자마다 6자세 공통)
  - 의자 차이: 등받이(ch32~63) 0.5~1.5배, 무릎(ch24~31) 0.6~1.6배 (가상 사용자마다 공통)
  - 자세 강도: 정자세 + k x (자세 - 정자세), k 0.85~1.15
  - 시간 흔들림: 원본 녹화의 프레임 순서를 그대로 쓰고 무작위로 뒤집거나 시작점 이동
  - 센서: 잡음(1% + 2), 0~4095 정수, 20 미만 0, 프레임마다 0.5% 확률로 칸 하나 꺼짐
미착석은 만들지 않는다 (모델은 빈 방석을 규칙으로 처리).

사용 (학습 스크립트에서 import): make(device_df, n_people=30, frames=600, seed=0) -> DataFrame
단독 실행: python ml/gen_dummy_device.py  -> data/train_7cls/dummy_device.csv.gz
"""
import glob, sys
from pathlib import Path
import numpy as np, pandas as pd

ROOT = Path(__file__).resolve().parents[1]
CH = [f"ch{i}" for i in range(64)]
POSTURES = ["sitting_straight", "lean_forward", "cross_leg_right", "cross_leg_left", "lean_right", "lean_left"]


def make(dev, n_people=30, frames=600, seed=0):
    rng = np.random.default_rng(seed)
    rec = {p: g[CH].to_numpy(np.float64) for p, g in dev.groupby("posture") if p in POSTURES}
    st_mean = rec["sitting_straight"].mean(0)
    rows = []
    for i in range(n_people):
        pid = f"devdummy{i+1:02d}"
        w = rng.uniform(0.8, 1.25); bg = rng.uniform(0.5, 1.5); kg = rng.uniform(0.6, 1.6)
        for p, R in rec.items():
            mean = R.mean(0)
            k = 1.0 if p == "sitting_straight" else rng.uniform(0.85, 1.15)
            target = np.clip(st_mean + k * (mean - st_mean), 0, None)
            rel = (R - mean) / (mean + 30)                       # 원본의 시간 흔들림(상대값)
            if rng.random() < 0.5: rel = rel[::-1]
            s = rng.integers(0, max(1, len(rel) - frames)); rel = rel[s:s + frames]
            if len(rel) < frames: rel = np.vstack([rel, rel[::-1]] * (frames // len(rel) + 1))[:frames]
            X = target * (1 + rel * rng.uniform(0.8, 1.2))
            X *= w; X[:, 32:] *= bg; X[:, 24:32] *= kg
            X += rng.normal(0, 1, X.shape) * (0.01 * X + 2)
            drop = rng.random(frames) < 0.005
            X[drop, rng.integers(0, 64, drop.sum())] = 0
            X = np.clip(np.rint(X), 0, 4095); X[X < 20] = 0
            f = pd.DataFrame(X.astype(int), columns=CH)
            f["person"] = pid; f["posture"] = p; f["trial"] = 1
            rows.append(f)
    return pd.concat(rows, ignore_index=True)


if __name__ == "__main__":
    dev = pd.concat([pd.read_csv(f) for f in sorted(glob.glob(str(ROOT / "data/test_64ch/*.csv")))])
    out = make(dev)
    path = ROOT / "data/train_7cls/dummy_device.csv.gz"
    out.to_csv(path, index=False)
    print(len(out), "행 ->", path)
