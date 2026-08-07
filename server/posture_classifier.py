"""
자세 판정.

[변경 이유]
  기존 classify_posture(s1..s6) 은 0~1023 범위 6개 값에 대한 하드코딩
  임계값(>200, >500 …)이었습니다. 32채널 센서에서는 값 범위도, 채널 수도,
  의미도 전부 달라서 그대로는 절대 동작하지 않습니다.

[새 방식] 2단계
  1순위: 사용자가 등록한 기준 자세와의 최근접 비교 (nearest-centroid)
         → 사람마다 체형/앉는 습관이 달라도 맞음. 이게 기본 경로.
  2순위: 등록된 자세가 없을 때만 쓰는 규칙 기반 폴백
         → 앱 처음 켠 직후에도 '아무것도 안 뜨는' 상황을 막기 위함
"""

import math
import sys
import os

# bridge/ 의 features 모듈을 재사용 (판정 기준을 한 곳에만 두기 위해)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "..", "bridge"))
import features as F  # noqa: E402

# 앱에 표시할 표준 자세 이름
POSTURES = [
    "정자세", "앞으로 숙이기", "뒤로 기대기",
    "오른다리 꼬기", "왼다리 꼬기", "좌측 기대기", "우측 기대기",
]

# 신뢰도가 이 아래면 '알 수 없음'으로 처리
CONFIDENCE_FLOOR = 0.35


# --------------------------------------------------------------- 1순위: 개인화
def classify_by_calibration(feat, calibrations):
    """
    calibrations: [{"label": str, "vector": [float, ...]}, ...]
    반환: (posture, confidence)
    """
    if not calibrations:
        return None, 0.0

    vec = F.to_vector(feat)
    scored = []
    for c in calibrations:
        ref = c.get("vector") or []
        if len(ref) != len(vec):
            continue
        scored.append((F.distance(vec, ref), c["label"]))
    if not scored:
        return None, 0.0

    scored.sort()
    best_d, best_label = scored[0]

    # 신뢰도: 1등과 2등의 거리 차이가 클수록 확신이 큼
    if len(scored) > 1:
        second_d = scored[1][0]
        margin = (second_d - best_d) / (second_d + best_d + 1e-6)
    else:
        margin = 0.5

    closeness = math.exp(-best_d * 2.0)          # 절대 거리도 반영
    confidence = max(0.0, min(1.0, 0.5 * closeness + 0.5 * margin))
    return best_label, confidence


# --------------------------------------------------------------- 2순위: 규칙
def classify_by_rule(feat):
    """
    등록된 자세가 없을 때의 폴백.
    32채널 특징(비율값)만 쓰기 때문에 체중과 무관합니다.
    """
    if not feat.get("seated"):
        return "비착석", 1.0

    lr = feat.get("lr_balance", 0.0)
    fb = feat.get("fb_balance", 0.0)
    grad = feat.get("lr_gradient", 0.0)   # 앞줄 쏠림 - 뒷줄 쏠림

    # 좌우 쏠림이 큰 경우, 앞뒤 줄의 쏠림 '차이'로 원인을 구분합니다.
    #   차이가 크다  → 한쪽 허벅지가 떴다 → 다리꼬기
    #   차이가 작다  → 몸 전체가 옆으로 갔다 → 몸통 기울임
    if abs(lr) > 0.18:
        if abs(grad) > 0.18:
            return ("왼다리 꼬기" if grad > 0 else "오른다리 꼬기"), 0.65
        return ("우측 기대기" if lr > 0 else "좌측 기대기"), 0.6

    if fb < -0.30:
        return "앞으로 숙이기", 0.6
    if fb > 0.70:
        return "뒤로 기대기", 0.6

    return "정자세", 0.7


def classify(feat, calibrations=None):
    """최종 진입점."""
    if not feat.get("seated"):
        return "비착석", 1.0

    label, conf = classify_by_calibration(feat, calibrations or [])
    if label and conf >= CONFIDENCE_FLOOR:
        return label, conf

    label, conf = classify_by_rule(feat)
    return label, conf


# --------------------------------------------------------------- 피드백 문구
_FEEDBACK = {
    "정자세": ("good", "좋아요! 바른 자세를 유지하고 있어요", None),
    "앞으로 숙이기": ("warning", "상체가 앞으로 쏠렸어요. 등을 세우고 화면을 눈높이로 올려주세요", "진동 알림"),
    "뒤로 기대기": ("warning", "등받이에 너무 기대고 있어요. 엉덩이를 안쪽으로 당겨 앉아주세요", "진동 알림"),
    "오른다리 꼬기": ("warning", "오른다리를 꼬고 있어요. 골반이 틀어질 수 있어요", "진동 알림"),
    "왼다리 꼬기": ("warning", "왼다리를 꼬고 있어요. 골반이 틀어질 수 있어요", "진동 알림"),
    "좌측 기대기": ("warning", "몸이 왼쪽으로 기울었어요. 양쪽에 체중을 고르게 실어주세요", "진동 알림"),
    "우측 기대기": ("warning", "몸이 오른쪽으로 기울었어요. 양쪽에 체중을 고르게 실어주세요", "진동 알림"),
    "비착석": ("idle", "자리에 앉으면 측정이 시작돼요", None),
}


def get_posture_feedback(posture):
    status, message, action = _FEEDBACK.get(
        posture, ("unknown", "자세를 분석하는 중이에요", None))
    return {"status": status, "message": message, "action": action}


# --------------------------------------------------------------- 하위호환
def classify_posture(*args, **kwargs):
    """
    ⚠️ 구버전 6채널 API. 팀원 코드가 아직 이걸 부르고 있을 수 있어
    남겨두지만, 호출되면 경고를 냅니다. 통합 시 제거하세요.
    """
    raise NotImplementedError(
        "classify_posture(s1..s6) 은 6채널 FSR 전용이라 폐기되었습니다. "
        "classify(features_dict, calibrations) 를 쓰세요."
    )
