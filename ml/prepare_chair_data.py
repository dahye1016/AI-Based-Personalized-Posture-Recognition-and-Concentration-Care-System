#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
더미/실측 posture 데이터 -> chair_64ch_posture_data.csv 스키마로 변환 (8종 버전).

한 행 = 한 시점(프레임) 샘플:
    seat_1~32, back_1~32, Label(p0~p7) [, Person]

라벨 정의는 루트의 posture_names.py 한 곳에만 있다 (앱 순서 0~7과 동일):
    p0 앉지 않음 / p1 정자세 / p2 앞으로 숙이기 / p3 오른다리 꼬기 /
    p4 왼다리 꼬기 / p5 오른쪽 기대기 / p6 왼쪽 기대기 / p7 거북목

※ 예전(7종) 버전과 의미가 달라졌다 (not_sitting: p7->p0, turtle_neck: p7 신규).
   예전에 만든 CSV·모델·norm_stats 는 새 라벨과 호환되지 않으니 이 스크립트로 다시 만들 것.

사용법
------
    # 64ch 실측 raw CSV 폴더 (collect_back.py 가 만든 data/raw_back/<자세>/*.csv)
    python -m ml.prepare_chair_data --source csvdir --csv-dir data/raw_back \
        --out chair_64ch_posture_data_real.csv

    # 팀원 더미 윈도우 npz (turtle_neck 이 없어서 7종만 나옴 — 파이프라인 점검용)
    python -m ml.prepare_chair_data --source npz --npz dummy_windows.npz \
        --out chair_64ch_posture_data_dummy.csv

raw CSV 가 가져야 하는 것
    posture 컬럼, 그리고 아래 중 하나의 센서 컬럼 묶음
      방석 : seat_0~31 (collect_back.py)  | seat_1~32  | ch0~31 (collect_data.py)
      등받이: back_0~31 (collect_back.py) | back_1~32  | back_ch0~31 | ch32~63 (collect_data.py --port-back)
    person 컬럼이 있으면 Person 컬럼으로 같이 저장한다 (학습 때 사람 단위 분리용).
    파일 이름에 _reject 가 들어 있으면 건너뛴다.
"""
from __future__ import annotations

import argparse
import glob
import os
import sys

import numpy as np
import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from posture_names import CODES, KOREAN, POSTURE_TO_PCODE   # noqa: E402

PCODE_TO_KOREAN = dict(zip(CODES, KOREAN))

SEAT_COLS = [f"seat_{i+1}" for i in range(32)]
BACK_COLS = [f"back_{i+1}" for i in range(32)]
OUT_COLS = SEAT_COLS + BACK_COLS + ["Label"]

SEAT_SRC_OPTIONS = [
    [f"seat_{i}" for i in range(32)],      # collect_back.py
    [f"seat_{i+1}" for i in range(32)],
    [f"ch{i}" for i in range(32)],         # collect_data.py (방석만)
]
BACK_SRC_OPTIONS = [
    [f"back_{i}" for i in range(32)],      # collect_back.py
    [f"back_{i+1}" for i in range(32)],
    [f"back_ch{i}" for i in range(32)],
    [f"ch{32 + i}" for i in range(32)],    # 팀 저장소 ml/collect_data.py --port-back (ch0~31 방석, ch32~63 등받이)
]


def _pick_columns(df: pd.DataFrame, options):
    """options 중 df 에 전부 있는 첫 컬럼 묶음을 돌려준다. 없으면 None."""
    for cols in options:
        if all(c in df.columns for c in cols):
            return cols
    return None


def from_npz(npz_path: str, label_map: dict) -> pd.DataFrame:
    """윈도우 npz(sessions 레이아웃)를 세션 단위 연속 프레임으로 복원해서
    프레임 하나하나를 독립 샘플로 뽑는다. (ml/load_dummy.py 필요)"""
    from ml.load_dummy import load_sessions

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


def from_csvdir(csv_dir: str, label_map: dict, allow_missing_back: bool = False) -> pd.DataFrame:
    """raw CSV 폴더(하위 폴더 포함)를 프레임 단위로 이어붙인다.

    - 등받이 컬럼이 없는 파일은 기본적으로 오류. 앞으로 숙이기(등받이 값 없음)와
      거북목(등은 닿고 어깨 줄은 거의 0)은 등받이 값으로 구분되므로, 0으로 채운 가짜
      등받이를 쓰면 라벨이 의미를 잃는다. (--allow-missing-back 은 파이프라인
      점검용이며 turtle_neck 파일에는 적용되지 않는다)
    - 방석이 전부 0인 파일(등받이 보드만 연결하고 수집한 파일)은 not_sitting 이
      아니면 쓸 수 없으므로 건너뛰고 알려준다.
    - 파일 이름에 _reject 가 있으면 건너뛴다.
    """
    files = sorted(glob.glob(os.path.join(csv_dir, "**", "*.csv"), recursive=True))
    files = [f for f in files if "_reject" not in os.path.basename(f)]
    if not files:
        raise ValueError(f"CSV 없음: {csv_dir}")
    frames = []
    skipped = 0
    for path in files:
        name = os.path.basename(path)
        df = pd.read_csv(path)
        if df.empty or "posture" not in df.columns:
            print(f"[건너뜀] {name}: 비어 있거나 posture 컬럼이 없음")
            skipped += 1
            continue
        posture = str(df["posture"].iloc[0])
        pcode = label_map.get(posture)
        if pcode is None:
            skipped += 1
            print(f"[건너뜀] {name}: 매핑표에 없는 posture '{posture}'")
            continue

        seat_cols = _pick_columns(df, SEAT_SRC_OPTIONS)
        if seat_cols is None:
            raise ValueError(f"{name}: 방석 32채널 컬럼을 찾지 못함 "
                             "(seat_0~31 / seat_1~32 / ch0~31 중 하나 필요)")
        seat = df[seat_cols].astype(np.float32)
        seat.columns = SEAT_COLS

        back_cols = _pick_columns(df, BACK_SRC_OPTIONS)
        if back_cols is not None:
            back = df[back_cols].astype(np.float32)
        else:
            if not allow_missing_back or posture == "turtle_neck":
                raise ValueError(
                    f"{name}: 등받이 32채널 컬럼이 없음 (back_0~31 / back_1~32 / back_ch0~31 필요). "
                    "등받이 실측 없이는 변환할 수 없다.")
            back = pd.DataFrame(0.0, index=df.index, columns=BACK_COLS)
        back.columns = BACK_COLS

        if posture != "not_sitting" and float(seat.values.max()) == 0.0:
            skipped += 1
            print(f"[건너뜀] {name}: 방석 값이 전부 0 — 등받이 보드만 연결하고 수집한 파일로 보임")
            continue

        out = pd.concat([seat, back], axis=1)
        out["Label"] = pcode
        if "person" in df.columns:
            out["Person"] = str(df["person"].iloc[0])
        frames.append(out)
        print(f"[변환] {name:<48} {posture:<17} -> {pcode}  ({len(out)}프레임)")
    if not frames:
        raise ValueError("변환할 수 있는 파일이 하나도 없음")
    if skipped:
        print(f"[안내] {skipped}개 파일을 건너뜀")
    return pd.concat(frames, ignore_index=True)


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description="더미/실측 데이터를 chair_64ch_posture_data.csv 스키마로 변환 (8종)")
    p.add_argument("--source", choices=["npz", "csvdir"], required=True)
    p.add_argument("--npz", default="dummy_windows.npz")
    p.add_argument("--csv-dir", default="data/raw_back")
    p.add_argument("--out", default="chair_64ch_posture_data_real.csv")
    p.add_argument("--allow-missing-back", action="store_true",
                   help="등받이 컬럼이 없는 raw CSV를 0으로 채워 변환 (파이프라인 점검용)")
    p.add_argument("--label-map", default=None,
                   help='posture=p코드 쌍을 콤마로 (예: "turtle_neck=p7") 지정하면 기본 매핑을 덮어씀')
    a = p.parse_args(argv)

    label_map = dict(POSTURE_TO_PCODE)
    if a.label_map:
        for pair in a.label_map.split(","):
            k, v = pair.split("=")
            label_map[k.strip()] = v.strip()

    if a.source == "npz":
        df = from_npz(a.npz, label_map)
    else:
        df = from_csvdir(a.csv_dir, label_map, allow_missing_back=a.allow_missing_back)

    cols = OUT_COLS + (["Person"] if "Person" in df.columns else [])
    df = df[cols]
    df.to_csv(a.out, index=False)
    print(f"\n저장: {a.out}  ({len(df):,}행)")
    counts = df["Label"].value_counts().sort_index()
    for code, n in counts.items():
        print(f"  {code} {PCODE_TO_KOREAN.get(code, '?'):<8} {n:>10,}")
    if "Person" in df.columns:
        per = df.groupby("Person")["Label"].nunique()
        print(f"\n참가자 {per.shape[0]}명: " + ", ".join(f"{k}({v}종)" for k, v in per.items()))

    missing = [c for c in CODES if c not in counts.index]
    if missing:
        names = ", ".join(f"{c}({PCODE_TO_KOREAN[c]})" for c in missing)
        print(f"\n[주의] 이 CSV에 없는 클래스: {names}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
