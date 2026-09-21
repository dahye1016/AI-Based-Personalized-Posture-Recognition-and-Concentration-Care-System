#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
실측 CSV(data/raw/*.csv, 방석 32채널) → 학습용 64채널 윈도우 npz 변환기.

목적
----
`ml/train_dummy.py`는 더미데이터 팀원분이 만든 (N, 50, 64) 윈도우 npz 포맷
(`ml/load_dummy.py`가 읽는 포맷)을 입력으로 받는다. 실측 데이터가 쌓이면
이 변환기로 같은 포맷을 만들어서, **학습 스크립트를 하나도 안 고치고**
그대로 재사용할 수 있다.

지금 실측 CSV는 방석 32채널만 있다(등받이 센서가 아직 없어서). 그래서 이
스크립트도 더미데이터와 똑같은 방식으로 — server_64ch.py의 잠정 8x4 격자
규칙으로 — 등받이 32채널을 규칙 기반 합성해서 채운다. **등받이 부분은 실측이
아니라는 걸 npz의 `back_is_synthetic=True` 플래그와 콘솔 출력에 항상 남긴다.**
실측 등받이 센서가 도착하면, 이 스크립트의 `synth_back()`을 빼고 진짜 back
채널 컬럼을 그대로 읽어오도록만 바꾸면 된다 (나머지 리샘플/윈도잉 로직은
그대로 재사용 가능).

사용법
------
    python3 -m ml.make_windows_from_real --raw-dir data/raw --out data/real/real_windows.npz

    # 만들어진 걸 그대로 학습 스크립트에 넣기
    python3 -m ml.train_dummy --data data/real/real_windows.npz --out runs/real_v1
"""
from __future__ import annotations

import argparse
import glob
import os

import numpy as np
import pandas as pd

NUM_SEAT_CH = 32
ADC_MAX = 4095
NOISE_GATE = 20
APP_HZ = 10.0                 # 개요서 Q4: 모델 입력 주기 10Hz
WINDOW_SEC = 5.0
WINDOW_LEN = int(WINDOW_SEC * APP_HZ)   # 50 프레임

POSTURES = [
    "not_sitting", "sitting_straight", "lean_forward",
    "cross_leg_right", "cross_leg_left", "lean_right", "lean_left",
]
LABEL_INDEX = {p: i for i, p in enumerate(POSTURES)}

RIGHT_IDX = list(range(0, 5)) + list(range(10, 17)) + list(range(24, 28))
LEFT_IDX = list(range(5, 10)) + list(range(17, 24)) + list(range(28, 32))

CHANNEL_NAMES = [f"ch{i}" for i in range(32)] + [f"back_ch{i}" for i in range(32)]

# 등받이 8x4 임시 격자 규칙 — server_64ch.py 그대로. 더미데이터 생성기(v3,
# generate_dummy_data.py의 BACK_SPEC)와 값을 맞춰서, 더미와 실측이 같은
# 가정으로 만들어지게 했다.
BACK_RULES = {
    "not_sitting":       dict(level_k=0.00, upper_ratio=0.50, propagate=0.00),
    "sitting_straight":  dict(level_k=0.60, upper_ratio=0.45, propagate=0.15),
    "lean_forward":      dict(level_k=0.05, upper_ratio=0.30, propagate=0.10),
    "cross_leg_right":   dict(level_k=0.55, upper_ratio=0.45, propagate=0.30),
    "cross_leg_left":    dict(level_k=0.55, upper_ratio=0.45, propagate=0.30),
    "lean_right":        dict(level_k=0.55, upper_ratio=0.45, propagate=0.80),
    "lean_left":         dict(level_k=0.55, upper_ratio=0.45, propagate=0.80),
}


def resample_10hz(df: pd.DataFrame) -> np.ndarray:
    """실측 fps가 고정 50이 아니라 흔들리므로(약 50~58fps 관측), timestamp
    기준으로 100ms 구간 평균을 내서 10Hz로 리샘플한다 (고정 stride 추출보다
    fps 지터에 안전하다)."""
    t0 = df["timestamp"].iloc[0]
    seat = df[[f"ch{i}" for i in range(NUM_SEAT_CH)]].astype(float)
    idx = pd.to_datetime(df["timestamp"] - t0, unit="s")
    seat.index = idx
    resampled = seat.resample(f"{int(1000/APP_HZ)}ms").mean().interpolate(limit_direction="both")
    arr = resampled.to_numpy()
    arr = np.rint(arr)
    arr[arr < NOISE_GATE] = 0
    arr = np.clip(arr, 0, ADC_MAX)
    return arr.astype(np.int16)


def synth_back(seat10: np.ndarray, posture: str, seed: int) -> np.ndarray:
    """실측 방석(10Hz로 리샘플된) 신호에서 등받이 32채널을 규칙 기반으로 합성.
    더미데이터와 동일한 BACK_RULES(8x4 격자, level_k/upper_ratio/propagate)."""
    n = len(seat10)
    rule = BACK_RULES[posture]
    right = seat10[:, RIGHT_IDX].mean(axis=1).astype(float)
    left = seat10[:, LEFT_IDX].mean(axis=1).astype(float)
    tot = right + left
    with np.errstate(divide="ignore", invalid="ignore"):
        right_pct = np.where(tot > 0, 100 * right / tot, 50.0)
    overall_mean = seat10.mean()
    level = overall_mean * rule["level_k"]

    back = np.zeros((n, 32), dtype=np.float32)
    if level > 0:
        rng = np.random.default_rng(seed)
        skew = (right_pct - 50.0) * rule["propagate"] / 50.0
        noise = rng.normal(0, 1.0, size=(n, 32)) * (level * 0.15)
        for r in range(8):
            row_w = (rule["upper_ratio"] * 2 if r < 4 else (1 - rule["upper_ratio"]) * 2) / 4.0
            for c in range(4):
                col_side = -1.0 if c < 2 else 1.0
                idx = r * 4 + c
                val = level * row_w * (1.0 + col_side * skew * 0.6)
                back[:, idx] = np.clip(val + noise[:, idx], 0, ADC_MAX)
    back = np.rint(back).astype(np.int16)
    back[back < NOISE_GATE] = 0
    return back


def make_windows(seat64: np.ndarray, stride_frames: int) -> np.ndarray:
    n = len(seat64)
    if n < WINDOW_LEN:
        return np.empty((0, WINDOW_LEN, 64), dtype=np.int16)
    starts = range(0, n - WINDOW_LEN + 1, stride_frames)
    return np.stack([seat64[s:s + WINDOW_LEN] for s in starts]).astype(np.int16)


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description="실측 CSV -> 64채널 윈도우 npz 변환")
    p.add_argument("--raw-dir", default="data/raw", help="실측 CSV 폴더")
    p.add_argument("--out", default="data/real/real_windows.npz")
    p.add_argument("--stride-sec", type=float, default=1.0, help="윈도우 간격(초)")
    p.add_argument("--seed", type=int, default=42)
    a = p.parse_args(argv)

    files = sorted(glob.glob(os.path.join(a.raw_dir, "*.csv")))
    if not files:
        print(f"CSV 없음: {a.raw_dir}")
        return 2

    stride_frames = max(1, int(round(a.stride_sec * APP_HZ)))
    X_all, y_all, person_all = [], [], []
    for path in files:
        df = pd.read_csv(path)
        posture = str(df["posture"].iloc[0])
        person = str(df["person"].iloc[0])
        if posture not in LABEL_INDEX:
            print(f"[건너뜀] {os.path.basename(path)}: 알 수 없는 자세 '{posture}'")
            continue

        seat10 = resample_10hz(df)
        back10 = synth_back(seat10, posture, seed=a.seed + LABEL_INDEX[posture])
        seat64 = np.concatenate([seat10, back10], axis=1)

        w = make_windows(seat64, stride_frames)
        if len(w) == 0:
            print(f"[건너뜀] {os.path.basename(path)}: {len(seat10)}프레임(10Hz) — "
                  f"{WINDOW_LEN}프레임(5초)보다 짧음")
            continue

        X_all.append(w)
        y_all.extend([LABEL_INDEX[posture]] * len(w))
        person_all.extend([person] * len(w))
        print(f"[변환] {os.path.basename(path):<28} {posture:<17} "
              f"{len(df):>6}프레임(원본) -> {len(seat10):>4}프레임(10Hz) -> 윈도우 {len(w):>4}개")

    if not X_all:
        print("변환된 파일이 없음")
        return 2

    X = np.concatenate(X_all)
    y = np.array(y_all, dtype=np.int8)
    person = np.array(person_all)

    os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    np.savez_compressed(
        a.out,
        layout="windows",
        X=X, y=y,
        labels=np.array(POSTURES),
        channel_names=np.array(CHANNEL_NAMES),
        person=person,
        case=person,                      # 실측은 케이스 라벨이 따로 없어 person과 동일하게 둠
        back_is_synthetic=True,           # 등받이 32채널은 여전히 규칙 기반 합성 — 실측 아님
        window_len=WINDOW_LEN,
        stride_frames=stride_frames,
    )
    counts = {POSTURES[i]: int((y == i).sum()) for i in range(len(POSTURES))}
    print(f"\n윈도우 {len(X):,}개 · 형태 {X.shape} · 저장: {a.out}")
    print("자세별:", "  ".join(f"{k} {v}" for k, v in counts.items()))
    print("인물:", sorted(set(person_all)))
    print("\n⚠️  뒤쪽 32채널(back_ch*)은 실측이 아니라 규칙 기반 합성이다 — "
          "등받이 실측 센서 도착 시 이 스크립트의 synth_back()을 실측 컬럼으로 교체할 것.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
