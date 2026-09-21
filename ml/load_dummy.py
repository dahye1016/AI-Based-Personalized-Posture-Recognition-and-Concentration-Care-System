#!/usr/bin/env python3
"""
더미 윈도우 로더
================

`generate_dummy_data.py --layout sessions` 가 만든 npz 를 (N, 50, C) 윈도우로 펼친다.
겹치는 구간을 복제 저장하지 않고 연속 세션 + 인덱스로 보관하기 때문에, 쓰기 직전에
여기서 되살린다. `--layout windows` 로 만든 파일도 같은 함수로 읽힌다.

    from ml.load_dummy import load_windows
    X, y, info = load_windows("data/dummy/dummy_windows.npz")
    X.shape   # (60000, 50, 64)   앞 32 = 방석, 뒤 32 = 등받이(합성)

메모리가 빠듯하면 세션 배열을 그대로 받아 배치 단위로 잘라 쓴다:

    S, y_sess, idx, info = load_sessions("data/dummy/dummy_windows.npz")
    batch = take_windows(S, idx[0:256])        # (256, 50, 64)

⚠️ 뒤쪽 32채널(back_ch*)은 실측이 아니라 규칙 기반 합성이다.
"""

from __future__ import annotations

import numpy as np


def _info(d) -> dict:
    return dict(
        labels=[str(x) for x in d["labels"]],
        channel_names=[str(x) for x in d["channel_names"]],
        back_is_synthetic=bool(d["back_is_synthetic"]),
        window_len=int(d["window_len"]),
        stride_frames=int(d["stride_frames"]),
    )


def load_sessions(path: str):
    """반환: (세션 배열 (S, T, C) int16, 세션 라벨, 윈도우 인덱스 (N, 2), info)"""
    d = np.load(path, allow_pickle=True)
    if str(d["layout"]) != "sessions":
        raise ValueError("이 파일은 layout='windows' 다. load_windows() 를 쓰라.")
    delta = d["sessions_delta"]
    S = np.cumsum(delta, axis=1, dtype=np.int32).astype(np.int16)   # 델타 복원
    return S, d["session_label"], d["win_index"], _info(d)


def take_windows(S: np.ndarray, idx: np.ndarray, window_len: int = 50) -> np.ndarray:
    """윈도우 인덱스 (session, start) 배열로 (n, window_len, C) 를 잘라낸다."""
    rows = idx[:, 0][:, None]
    cols = idx[:, 1][:, None] + np.arange(window_len)[None, :]
    return S[rows, cols]


def load_windows(path: str):
    """반환: (X (N, window_len, C) int16, y (N,) int8, info)"""
    d = np.load(path, allow_pickle=True)
    info = _info(d)
    if str(d["layout"]) == "windows":
        return d["X"], d["y"], info
    S, y_sess, idx, info = load_sessions(path)
    X = take_windows(S, idx, info["window_len"])
    return X, y_sess[idx[:, 0]], info


def load_groups(path: str) -> np.ndarray:
    """사람 단위 분할용 group 배열 (윈도우마다 person id)."""
    d = np.load(path, allow_pickle=True)
    if str(d["layout"]) == "windows":
        return d["person"]
    return d["session_person"][d["win_index"][:, 0]]


if __name__ == "__main__":
    import sys
    path = sys.argv[1] if len(sys.argv) > 1 else "data/dummy/dummy_windows.npz"
    X, y, info = load_windows(path)
    print(f"X {X.shape} {X.dtype} · y {y.shape} · 채널 {len(info['channel_names'])}개")
    print("자세별:", {info["labels"][i]: int((y == i).sum()) for i in range(len(info["labels"]))})
    if info["back_is_synthetic"]:
        print("※ 뒤쪽 32채널(back_ch*)은 실측이 아니라 규칙 기반 합성이다.")
