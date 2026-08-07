"""
32채널 raw 프레임 -> 자세 판정용 특징 벡터.

기존 코드는 6개 센서값을 그대로 임계값에 때려박았지만,
32채널은 값 자체보다 '압력이 어디에 몰려 있는가'가 훨씬 중요합니다.
그래서 벤더 그래프 페이지가 쓰는 지표와 같은 것들을 뽑습니다.
(Sum / Max / Avg / Area / CoF)

여기서 나온 특징은 그대로
  - 서버 자세분류 (nearest-centroid)
  - 앱 리포트 화면 (자세 분포, 시간대별)
두 군데에서 쓰입니다.
"""

from typing import Dict, List, Sequence

from layout import (
    BACK_CH, FRONT_CH, HEIGHT_MM, LEFT_CH, MID_CH, MIRROR_LR, N_CHANNELS,
    NODE_AREA_CM2, ORIENTATION_FLIP, POSITIONS, RIGHT_CH, ROWS, WIDTH_MM,
)

# Area 를 계산할 압력 임계값들 (벤더 그래프 페이지와 동일 기준)
AREA_LEVELS = (100, 300, 500, 700, 1000, 1200, 1400)

# 사람이 앉아 있다고 볼 최소 총합. 이 아래면 '착석 안 함'.
SEATED_SUM_THRESHOLD = 800


def _mean(xs: Sequence[float]) -> float:
    return sum(xs) / len(xs) if xs else 0.0


def extract(frame: Sequence[int]) -> Dict[str, float]:
    """raw 32채널 -> 특징 dict"""
    if len(frame) != N_CHANNELS:
        raise ValueError(f"프레임 길이가 {len(frame)}입니다. {N_CHANNELS}개여야 합니다.")

    vals = [max(0.0, float(v)) for v in frame]
    total = sum(vals)

    feat: Dict[str, float] = {
        "sum": total,
        "max": max(vals),
        "avg": total / N_CHANNELS,
        "seated": 1.0 if total >= SEATED_SUM_THRESHOLD else 0.0,
    }

    # 면적: 임계값 이상인 노드 개수 x 노드당 면적
    for lv in AREA_LEVELS:
        feat[f"area_{lv}"] = sum(1 for v in vals if v >= lv) * NODE_AREA_CM2

    # 무게중심(CoF) — 0~1 정규화. 0.5 가 정중앙.
    if total > 0:
        cx = sum(vals[ch] * POSITIONS[ch][0] for ch in range(N_CHANNELS)) / total
        cy = sum(vals[ch] * POSITIONS[ch][1] for ch in range(N_CHANNELS)) / total
        feat["cof_x"] = cx / WIDTH_MM
        feat["cof_y"] = cy / HEIGHT_MM
    else:
        feat["cof_x"] = feat["cof_y"] = 0.5

    # 영역별 평균
    front = _mean([vals[c] for c in FRONT_CH])
    mid = _mean([vals[c] for c in MID_CH])
    back = _mean([vals[c] for c in BACK_CH])
    left = _mean([vals[c] for c in LEFT_CH])
    right = _mean([vals[c] for c in RIGHT_CH])
    feat.update(front=front, mid=mid, back=back, left=left, right=right)

    # 비대칭 지표 — 이게 자세 판별의 핵심 (-1 ~ +1)
    # lr_balance  > 0 이면 오른쪽으로 쏠림 (왼다리 꼬기 등)
    # fb_balance  > 0 이면 뒤쪽으로 쏠림 (등받이에 기댐)
    feat["lr_balance"] = (right - left) / (right + left) if (right + left) > 0 else 0.0
    feat["fb_balance"] = (back - front) / (back + front) if (back + front) > 0 else 0.0

    # 접촉 집중도 — 다리를 꼬면 닿는 면적이 줄고 한쪽에 몰립니다
    feat["contact_ratio"] = sum(1 for v in vals if v >= 100) / N_CHANNELS
    feat["peakiness"] = feat["max"] / feat["avg"] if feat["avg"] > 0 else 0.0

    # ── 다리꼬기 vs 몸통 기울임을 가르는 핵심 지표 ─────────────────────
    # 줄(ROW)별로 좌우 불균형을 따로 계산합니다.
    #   · 다리를 꼬면 → 올린 쪽 허벅지가 떠서 '앞줄'만 크게 쏠림
    #                   (앞줄 불균형 ≫ 뒷줄 불균형)
    #   · 몸통을 기울이면 → 앞줄과 뒷줄이 똑같이 쏠림 (차이가 거의 0)
    # 그래서 lr_gradient(=앞줄불균형 - 뒷줄불균형) 하나로 둘이 갈립니다.
    for row, (lch, rch) in ROWS.items():
        lv, rv = _mean([vals[c] for c in lch]), _mean([vals[c] for c in rch])
        feat[f"lr_row{row}"] = (rv - lv) / (rv + lv) if (rv + lv) > 0 else 0.0

    if ORIENTATION_FLIP:
        f_row, b_row = "lr_row2", "lr_row0"
    else:
        f_row, b_row = "lr_row0", "lr_row2"
    if MIRROR_LR:
        for k in ("lr_row0", "lr_row1", "lr_row2"):
            feat[k] = -feat[k]

    feat["lr_front"] = feat[f_row]
    feat["lr_back"] = feat[b_row]
    feat["lr_gradient"] = feat[f_row] - feat[b_row]

    return feat


# 자세 비교(nearest-centroid)에 실제로 쓰는 축.
# sum/max 같은 절대값은 체중에 따라 달라지므로 일부러 뺐습니다.
# 이게 '개인화(personalized)'의 핵심입니다.
COMPARE_KEYS = (
    "cof_x", "cof_y",
    "lr_balance", "fb_balance",
    "lr_front", "lr_back", "lr_gradient",
    "contact_ratio",
    "front_ratio", "mid_ratio", "back_ratio",
    "left_ratio", "right_ratio",
)

# 축별 가중치 — 좌우 쏠림(다리꼬기)과 앞뒤 쏠림(기대기)을 더 민감하게
WEIGHTS = {
    "cof_x": 1.5, "cof_y": 1.5,
    "lr_balance": 2.0, "fb_balance": 2.0,
    "lr_front": 1.5, "lr_back": 1.5,
    "lr_gradient": 3.0,          # 다리꼬기/기울임 구분의 핵심축이라 가중치 최대
    "contact_ratio": 1.0,
    "front_ratio": 1.0, "mid_ratio": 1.0, "back_ratio": 1.0,
    "left_ratio": 1.0, "right_ratio": 1.0,
}


def to_vector(feat: Dict[str, float]) -> List[float]:
    """특징 dict -> 비교용 정규화 벡터 (체중/개인차 영향 제거)"""
    s = feat.get("sum", 0.0) or 1.0
    ratios = {
        "front_ratio": feat.get("front", 0.0) * len(FRONT_CH) / s,
        "mid_ratio": feat.get("mid", 0.0) * len(MID_CH) / s,
        "back_ratio": feat.get("back", 0.0) * len(BACK_CH) / s,
        "left_ratio": feat.get("left", 0.0) * len(LEFT_CH) / s,
        "right_ratio": feat.get("right", 0.0) * len(RIGHT_CH) / s,
    }
    merged = {**feat, **ratios}
    return [merged.get(k, 0.0) for k in COMPARE_KEYS]


def distance(a: List[float], b: List[float]) -> float:
    """가중 유클리드 거리"""
    w = [WEIGHTS.get(k, 1.0) for k in COMPARE_KEYS]
    return sum(wi * (x - y) ** 2 for wi, x, y in zip(w, a, b)) ** 0.5
