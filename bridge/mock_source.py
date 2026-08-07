"""
센서 실물 없이 32채널 프레임을 만들어내는 가상 소스.

벤더 그래프 페이지에도 "Random/Prev/Next 버튼은 Core 보드 없이
그래프를 시뮬레이션해보는 용도"라고 명시돼 있습니다. 같은 발상입니다.

앉은 사람의 엉덩이 두 덩이를 2D 가우시안 두 개로 모델링하고,
자세에 따라 그 중심/무게를 옮깁니다. 실제 방석센서 출력과
'분포 모양'이 비슷해지므로 자세분류 로직을 그대로 검증할 수 있습니다.
"""

import math
import random
from typing import Dict, List

from layout import HEIGHT_MM, N_CHANNELS, POSITIONS, ROWS, WIDTH_MM

_ROW_OF = {ch: row for row, (l, r) in ROWS.items() for ch in l + r}
_LEFT_SET = {ch for l, _ in ROWS.values() for ch in l}

# 자세별 파라미터
#   좌/우 좌골(ischial tuberosity) 중심 위치는 0~1 정규화 좌표
#   (x: 0=왼쪽 가장자리, y: 0=앞쪽 가장자리)
POSTURE_PROFILES: Dict[str, dict] = {
    "정자세": {
        "blobs": [(0.34, 0.55, 1.0), (0.66, 0.55, 1.0)],
        "spread": 0.20, "peak": 900,
    },
    "앞으로 숙이기": {   # 상체가 앞으로 → 무게가 앞(허벅지)쪽으로 이동
        "blobs": [(0.34, 0.34, 1.0), (0.66, 0.34, 1.0)],
        "spread": 0.22, "peak": 1050,
    },
    "뒤로 기대기": {     # 등받이에 기댐 → 무게가 뒤로, 전체 압력은 감소
        "blobs": [(0.34, 0.74, 1.0), (0.66, 0.74, 1.0)],
        "spread": 0.24, "peak": 700,
    },
    # ── 다리꼬기 vs 몸통 기울임 구분 포인트 ────────────────────────────
    # 다리를 꼬면 '올린 쪽 허벅지'가 방석에서 뜹니다 → 그 쪽 앞줄(ROW0)만
    # 압력이 확 빠지고 뒷줄(ROW2)은 별로 안 변합니다. (앞뒤 비대칭이 다름)
    # 반면 몸통을 옆으로 기울이면 앞줄·뒷줄이 '똑같이' 한쪽으로 쏠립니다.
    # row_gain = {행: (왼쪽배율, 오른쪽배율)}
    "오른다리 꼬기": {   # 오른다리를 위로 올림
        "blobs": [(0.32, 0.55, 1.0), (0.70, 0.58, 0.55)],
        "spread": 0.18, "peak": 1150,
        "row_gain": {0: (1.05, 0.20), 1: (1.10, 0.60), 2: (1.00, 0.95)},
    },
    "왼다리 꼬기": {
        "blobs": [(0.68, 0.55, 1.0), (0.30, 0.58, 0.55)],
        "spread": 0.18, "peak": 1150,
        "row_gain": {0: (0.20, 1.05), 1: (0.60, 1.10), 2: (0.95, 1.00)},
    },
    "좌측 기대기": {     # 몸통을 왼쪽으로 기울임 — 모든 줄이 균일하게 쏠림
        "blobs": [(0.26, 0.55, 1.0), (0.62, 0.55, 0.55)],
        "spread": 0.20, "peak": 1000,
        "row_gain": {0: (1.25, 0.65), 1: (1.25, 0.65), 2: (1.25, 0.65)},
    },
    "우측 기대기": {
        "blobs": [(0.74, 0.55, 1.0), (0.38, 0.55, 0.55)],
        "spread": 0.20, "peak": 1000,
        "row_gain": {0: (0.65, 1.25), 1: (0.65, 1.25), 2: (0.65, 1.25)},
    },
    "비착석": {
        "blobs": [], "spread": 0.2, "peak": 0,
    },
}

POSTURE_NAMES = list(POSTURE_PROFILES.keys())


def generate(posture: str = "정자세", noise: float = 0.05,
             jitter: float = 0.02, rng: random.Random = None) -> List[int]:
    """해당 자세의 32채널 raw 프레임 1개를 만든다."""
    rng = rng or random
    prof = POSTURE_PROFILES.get(posture)
    if prof is None:
        raise ValueError(f"알 수 없는 자세: {posture}")

    # 매 프레임 사람이 미세하게 움직이는 효과
    dx = rng.gauss(0, jitter)
    dy = rng.gauss(0, jitter)
    sp = prof["spread"]
    peak = prof["peak"]

    row_gain = prof.get("row_gain")

    frame = []
    for ch in range(N_CHANNELS):
        x, y = POSITIONS[ch]
        nx, ny = x / WIDTH_MM, y / HEIGHT_MM
        v = 0.0
        for bx, by, w in prof["blobs"]:
            d2 = (nx - bx - dx) ** 2 + (ny - by - dy) ** 2
            v += w * peak * math.exp(-d2 / (2 * sp * sp))
        if row_gain:
            v *= row_gain[_ROW_OF[ch]][0 if ch in _LEFT_SET else 1]
        v += rng.gauss(0, peak * noise) + rng.uniform(0, 12)  # 노이즈 + 베이스라인
        frame.append(int(max(0, min(1600, v))))               # ADC 상한 클램프
    return frame


class MockSource:
    """
    시리얼 포트 대신 쓰는 가상 프레임 소스.
    read_frame() 을 호출할 때마다 프레임 1개를 돌려줍니다.

    mode="auto" 면 몇 초마다 자세가 저절로 바뀝니다.
    """

    def __init__(self, posture: str = "정자세", mode: str = "fixed",
                 switch_every: int = 60, seed: int = None):
        self.rng = random.Random(seed)
        self.posture = posture
        self.mode = mode
        self.switch_every = switch_every
        self._count = 0

    def set_posture(self, posture: str):
        self.posture = posture

    def read_frame(self) -> List[int]:
        if self.mode == "auto" and self._count % self.switch_every == 0 and self._count:
            candidates = [p for p in POSTURE_NAMES if p != "비착석"]
            self.posture = self.rng.choice(candidates)
        self._count += 1
        return generate(self.posture, rng=self.rng)

    def close(self):
        pass


if __name__ == "__main__":
    import features
    for name in POSTURE_NAMES:
        f = features.extract(generate(name, noise=0.0, jitter=0.0))
        print(f"{name:8s}  sum={f['sum']:7.0f}  "
              f"CoF=({f['cof_x']:.2f},{f['cof_y']:.2f})  "
              f"LR={f['lr_balance']:+.2f}  FB={f['fb_balance']:+.2f}  "
              f"contact={f['contact_ratio']:.2f}")
