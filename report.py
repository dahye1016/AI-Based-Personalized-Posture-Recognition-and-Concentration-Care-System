"""
report.py

DB(sensor_data_64ch 테이블)에 쌓인 판정 로그를 집계해서
- 일간 리포트 (하루 동안 자세별 비율)
- 주간 리포트 (최근 7일 추이)
- 연속 기록(스트릭) (좋은 자세를 유지한 날이 며칠 연속인지)
을 계산합니다.

서버(server_64ch.py)가 /sensor-data에 저장하는 posture 컬럼 형식이
"CNN: p1(정자세)" 같은 문자열이라, 여기서 정규식으로 코드(p1)만
뽑아내서 집계합니다.
"""

import re
from collections import defaultdict
from datetime import datetime, timedelta

from database_64ch import SessionLocal, SensorData

# server_64ch.py의 DISPLAY_NAMES와 동일하게 유지해야 함 (표시용)
DISPLAY_NAMES = {
    "p1": "정자세",
    "p2": "거북목(앞으로 숙이기)",
    "p3": "오른다리꼬기",
    "p4": "왼다리꼬기",
    "p5": "오른쪽기대기",
    "p6": "왼쪽기대기",
    "p7": "앉지않음",
    "p8": "등받이 밀착 자세",
}

_POSTURE_CODE_RE = re.compile(r"CNN:\s*(\w+)\(")


def _extract_code(posture_str: str):
    if not posture_str:
        return None
    m = _POSTURE_CODE_RE.search(posture_str)
    return m.group(1) if m else None


def _aggregate(start: datetime, end: datetime) -> dict:
    """[start, end) 구간의 자세별 등장 횟수/비율 집계."""
    db = SessionLocal()
    try:
        rows = (
            db.query(SensorData.posture)
            .filter(SensorData.timestamp >= start, SensorData.timestamp < end)
            .all()
        )
    finally:
        db.close()

    counts = defaultdict(int)
    total = 0
    for (posture_str,) in rows:
        code = _extract_code(posture_str)
        if code:
            counts[code] += 1
            total += 1

    percentages = {
        code: round(count / total * 100, 1) for code, count in counts.items()
    } if total else {}

    return {
        "total_samples": total,
        "counts": dict(counts),
        "percentages": percentages,
        "display_names": {code: DISPLAY_NAMES.get(code, code) for code in counts},
    }


def get_daily_report(target_date=None) -> dict:
    """특정 날짜(기본: 오늘) 하루치 자세 비율 리포트."""
    if target_date is None:
        target_date = datetime.now().date()
    start = datetime.combine(target_date, datetime.min.time())
    end = start + timedelta(days=1)

    report = _aggregate(start, end)
    report["date"] = str(target_date)
    return report


def get_weekly_report(end_date=None) -> dict:
    """end_date를 포함한 최근 7일 리포트 (일별 세부 + 주간 합계)."""
    if end_date is None:
        end_date = datetime.now().date()
    start_date = end_date - timedelta(days=6)

    days = [get_daily_report(start_date + timedelta(days=i)) for i in range(7)]

    week_counts = defaultdict(int)
    week_total = 0
    for day in days:
        for code, count in day["counts"].items():
            week_counts[code] += count
        week_total += day["total_samples"]

    week_percentages = {
        code: round(count / week_total * 100, 1) for code, count in week_counts.items()
    } if week_total else {}

    return {
        "start_date": str(start_date),
        "end_date": str(end_date),
        "days": days,
        "week_total_samples": week_total,
        "week_counts": dict(week_counts),
        "week_percentages": week_percentages,
        "display_names": {code: DISPLAY_NAMES.get(code, code) for code in week_counts},
    }


def get_streak(good_codes=("p1",), min_ratio: float = 0.5, max_days: int = 365) -> dict:
    """
    오늘부터 거슬러 올라가며, 하루 동안 good_codes(기본: 정자세=p1)의 비율이
    min_ratio(기본 50%) 이상인 날이 며칠 연속인지 계산.
    데이터가 아예 없는 날을 만나면 그 지점에서 스트릭이 끊긴 것으로 처리.
    (단, 오늘은 아직 하루가 안 끝났을 수 있으니 total_samples=0이어도 건너뜀)
    """
    today = datetime.now().date()
    streak = 0
    for i in range(max_days):
        d = today - timedelta(days=i)
        report = get_daily_report(d)

        if report["total_samples"] == 0:
            if i == 0:
                continue  # 오늘은 데이터가 아직 없을 수 있으므로 건너뜀 (스트릭 끊지 않음)
            break

        good = sum(count for code, count in report["counts"].items() if code in good_codes)
        ratio = good / report["total_samples"]

        if ratio >= min_ratio:
            streak += 1
        else:
            break

    return {
        "streak_days": streak,
        "good_codes": list(good_codes),
        "good_display_names": [DISPLAY_NAMES.get(c, c) for c in good_codes],
        "min_ratio": min_ratio,
    }
