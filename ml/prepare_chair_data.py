#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
더미/실측 posture 데이터 -> chair_64ch_posture_data.csv와 완전히 같은 스키마로 변환.

목적
----
`train_posture_cnn_64ch.py`(실제 서버가 쓰는 학습 스크립트)는 딱 이 형태만 읽는다:
    seat_1~32, back_1~32, Label(p1~p8)   -- 한 행 = 한 시점(프레임) 샘플
지금 그 Label은 Kaggle ChairPose 데이터에 순번으로 임의 배정된 것(p1=정자세,
p2=거북목, ... 데이터 근거 없음)이라, 우리가 실제로 모은/합성한 posture 데이터로
바꿔치기하는 게 이 스크립트의 목적이다. **모델 구조·학습 루프는 원본 스크립트를
전혀 건드리지 않고, DATA_PATH만 이 스크립트가 만든 CSV로 바꿔서 쓰면 된다.**

posture -> p코드 매핑 (기존에 임의 배정된 이름 그대로 유지, p8 제외)
------------------------------------------------------------------
p1 정자세            <- sitting_straight
p2 거북목            <- lean_forward      (숙인 자세 -> 거북목에 가장 가까움)
p3 오른다리꼬기       <- cross_leg_right
p4 왼다리꼬기         <- cross_leg_left
p5 오른쪽기대기       <- lean_right
p6 왼쪽기대기         <- lean_left
p7 앉지않음           <- not_sitting
p8 등받이 밀착 자세    <- (제외) 등받이 실측 센서 없이는 수집 불가능한 자세라
                          더미/실측 어느 쪽에도 없음. 등받이 센서 도착 후 별도 수집
                          필요.
※ p2(거북목) 매핑은 다혜님이 다르게 판단하시면 --label-map으로 덮어쓸 수 있음.

사용법
------
    # 팀원 클로드가 만든 더미 윈도우 npz에서 (세션을 프레임 단위로 풀어서 사용)
    python3 -m ml.prepare_chair_data --source npz --npz data/dummy/dummy_windows.npz \
        --out chair_64ch_posture_data_dummy.csv

    # 우리가 모은 실측/합성 raw CSV 폴더에서 (frame,timestamp,ch0~31,back_ch0~31,... 형식)
    python3 -m ml.prepare_chair_data --source csvdir --csv-dir data/raw \
        --out chair_64ch_posture_data_real.csv
"""
from __future__ import annotations

import argparse
import glob
import os
import sys

import numpy as np
import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from ml.load_dummy import load_sessions   # noqa: E402

POSTURE_TO_PCODE = {
    "sitting_straight": "p1",   # 정자세
    "lean_forward": "p2",       # 거북목
    "cross_leg_right": "p3",    # 오른다리꼬기
    "cross_leg_left": "p4",     # 왼다리꼬기
    "lean_right": "p5",         # 오른쪽기대기
    "lean_left": "p6",          # 왼쪽기대기
    "not_sitting": "p7",        # 앉지않음
    # "등받이 밀착 자세"(p8)는 매핑 대상 posture가 없어 제외
}

SEAT_COLS = [f"seat_{i+1}" for i in range(32)]
BACK_COLS = [f"back_{i+1}" for i in range(32)]
OUT_COLS = SEAT_COLS + BACK_COLS + ["Label"]


def from_npz(npz_path: str, label_map: dict) -> pd.DataFrame:
    """윈도우 npz(sessions 레이아웃)를 세션 단위 연속 프레임으로 복원해서,
    윈도우로 자르지 않고 프레임 하나하나를 독립 샘플로 뽑는다 (윈도우끼리 겹치는
    구간을 중복 샘플링하지 않기 위해 — 원본 train_posture_cnn_64ch.py는 프레임
    단위 분류라 겹침 걱정 자체가 필요 없다)."""
    S, session_label, _win_index, info = load_sessions(npz_path)
    labels = info["labels"]
    n_sessions, n_frames, n_ch = S.shape
    assert n_ch == 64, f"채널 수가 64가 아님: {n_ch}"

    rows, pcodes = [], []
    skipped = 0
    for i in range(n_sessions):
        posture = labels[session_label[i]]
        pcode = label_map.get(posture)
        if pcode is None:
            skipped += 1
            continue
        rows.append(S[i])          # (n_frames, 64)
        pcodes.extend([pcode] * n_frames)
    if not rows:
        raise ValueError("매핑되는 posture가 하나도 없음 — label_map 확인 필요")
    X = np.concatenate(rows, axis=0).astype(np.float32)
    if skipped:
        print(f"[안내] {skipped}개 세션은 매핑표에 없는 posture라 건너뜀")
    df = pd.DataFrame(X, columns=SEAT_COLS + BACK_COLS)
    df["Label"] = pcodes
    return df


def from_csvdir(csv_dir: str, label_map: dict) -> pd.DataFrame:
    """frame,timestamp,ch0~31,back_ch0~31(있으면),person,posture,trial 형식의 raw CSV
    폴더를 그대로 프레임 단위로 이어붙인다. back_ch*가 없으면(아직 등받이 실측
    전 데이터) 0으로 채운다 — 학습 자체는 되지만 등받이 정보가 없다는 뜻."""
    files = sorted(glob.glob(os.path.join(csv_dir, "*.csv")))
    if not files:
        raise ValueError(f"CSV 없음: {csv_dir}")
    frames = []
    skipped = 0
    for path in files:
        df = pd.read_csv(path)
        posture = str(df["posture"].iloc[0])
        pcode = label_map.get(posture)
        if pcode is None:
            skipped += 1
            continue
        seat = df[[f"ch{i}" for i in range(32)]].astype(np.float32)
        seat.columns = SEAT_COLS
        back_src = [f"back_ch{i}" for i in range(32)]
        if all(c in df.columns for c in back_src):
            back = df[back_src].astype(np.float32)
        else:
            back = pd.DataFrame(0.0, index=df.index, columns=BACK_COLS)
        back.columns = BACK_COLS
        out = pd.concat([seat, back], axis=1)
        out["Label"] = pcode
        frames.append(out)
        print(f"[변환] {os.path.basename(path):<32} {posture:<17} -> {pcode}  ({len(out)}프레임)")
    if not frames:
        raise ValueError("매핑되는 posture가 하나도 없음")
    if skipped:
        print(f"[안내] {skipped}개 파일은 매핑표에 없는 posture라 건너뜀")
    return pd.concat(frames, ignore_index=True)


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description="더미/실측 데이터를 chair_64ch_posture_data.csv 스키마로 변환")
    p.add_argument("--source", choices=["npz", "csvdir"], required=True)
    p.add_argument("--npz", default="data/dummy/dummy_windows.npz")
    p.add_argument("--csv-dir", default="data/raw")
    p.add_argument("--out", default="chair_64ch_posture_data_dummy.csv")
    p.add_argument("--label-map", default=None,
                    help='posture=p코드 쌍을 콤마로 (예: "lean_forward=p2,not_sitting=p7") '
                         '지정하면 기본 매핑을 덮어씀')
    a = p.parse_args(argv)

    label_map = dict(POSTURE_TO_PCODE)
    if a.label_map:
        for pair in a.label_map.split(","):
            k, v = pair.split("=")
            label_map[k.strip()] = v.strip()

    if a.source == "npz":
        df = from_npz(a.npz, label_map)
    else:
        df = from_csvdir(a.csv_dir, label_map)

    df = df[OUT_COLS]
    df.to_csv(a.out, index=False)
    print(f"\n저장: {a.out}  ({len(df):,}행)")
    print(df["Label"].value_counts().sort_index())
    print(f"\n(매핑 안 쓴 posture는 제외됨. p8 등받이 밀착 자세는 이 데이터에 없음 —"
          " 등받이 센서 도착 후 별도 보강 필요)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
