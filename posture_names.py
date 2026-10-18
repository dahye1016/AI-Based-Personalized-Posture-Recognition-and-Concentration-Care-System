"""
posture_names.py — 자세 라벨 정의 (8종) + 서버/리포트/시뮬레이터 공용 표시 이름 로더.

2026-10-15 확정 (앱 lib/models/posture_class.dart 순서와 동일):

    0 p0 not_sitting       앉지 않음
    1 p1 sitting_straight  정자세
    2 p2 lean_forward      앞으로 숙이기   (등받이에 값이 거의 없음)
    3 p3 cross_leg_right   오른다리 꼬기
    4 p4 cross_leg_left    왼다리 꼬기
    5 p5 lean_right        오른쪽 기대기
    6 p6 lean_left         왼쪽 기대기
    7 p7 turtle_neck       거북목          (등은 닿고 어깨 부분은 떠 있음)

순서를 바꾸지 말 것. 학습 라벨(Label 컬럼)은 이 순서대로 p0~p7 문자열이다.

표시 이름은 학습 때 norm_stats_64ch.json 의 "label_names" 에 같이 저장된다.
서버·리포트·시뮬레이터는 그 파일을 읽어서 이름을 정하므로, 모델과 이름표가
항상 같은 파일에서 나온다. label_names 가 없는 예전(7종) norm_stats 가 올라가
있으면 예전 이름표(LEGACY_NAMES)를 써서, 새 모델로 교체하기 전에도 서버가
그대로 동작한다.
"""
import json
import os

POSTURE_ORDER = [
    "not_sitting",       # 0
    "sitting_straight",  # 1
    "lean_forward",      # 2
    "cross_leg_right",   # 3
    "cross_leg_left",    # 4
    "lean_right",        # 5
    "lean_left",         # 6
    "turtle_neck",       # 7
]
CODES = [f"p{i}" for i in range(len(POSTURE_ORDER))]
POSTURE_TO_PCODE = dict(zip(POSTURE_ORDER, CODES))

KOREAN = [
    "앉지 않음",
    "정자세",
    "앞으로 숙이기",
    "오른다리 꼬기",
    "왼다리 꼬기",
    "오른쪽 기대기",
    "왼쪽 기대기",
    "거북목",
]
NEW_NAMES = dict(zip(CODES, KOREAN))

# 8종으로 바꾸기 전(7종 모델) 이름표. 새 모델로 교체하기 전까지만 쓰인다.
LEGACY_NAMES = {
    "p1": "정자세",
    "p2": "거북목(앞으로 숙이기)",
    "p3": "오른다리꼬기",
    "p4": "왼다리꼬기",
    "p5": "오른쪽기대기",
    "p6": "왼쪽기대기",
    "p7": "앉지않음",
    "p8": "등받이 밀착 자세",
}

_HERE = os.path.dirname(os.path.abspath(__file__))


def load_display_names(norm_stats_path: str | None = None) -> dict:
    """norm_stats 의 label_names 가 있으면 그것을, 없으면 예전 이름표를 돌려준다."""
    path = norm_stats_path or os.path.join(_HERE, "norm_stats_64ch.json")
    try:
        with open(path, "r", encoding="utf-8") as f:
            names = json.load(f).get("label_names")
        if names:
            return dict(names)
    except Exception:
        pass
    return dict(LEGACY_NAMES)
