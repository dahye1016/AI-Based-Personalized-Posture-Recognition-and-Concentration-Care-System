import datetime as dt
from collections import defaultdict
from typing import List, Optional

from fastapi import FastAPI, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from database import SessionLocal, init_db, User, PostureLog, Calibration
from constants import POSTURE_LABELS, BAD_POSTURES, NUM_CHANNELS, FULL_SCALE

# [DEPRECATED] 구 아키텍처(서버 판정, 6채널)용 import.
#   원시 데이터 저장/서버 판정은 폐기됨 → 아래 엔드포인트도 주석 처리.
#   재활성화하려면 database.SensorData 와 posture_classifier import 를 되살려야 함.
# from database import SensorData
# from posture_classifier import classify_posture, get_posture_feedback

app = FastAPI()


# 서버 시작할 때 DB 테이블 자동 생성 (없는 테이블만 생성됨)
@app.on_event("startup")
def startup():
    init_db()


# DB 연결 함수
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


# ---------------------------------------------------------------------
# 공통 헬퍼
# ---------------------------------------------------------------------
def ensure_user(db: Session, user_id: int):
    """user_id 가 없으면 404."""
    exists = db.query(User.id).filter(User.id == user_id).first()
    if not exists:
        raise HTTPException(status_code=404, detail=f"user_id {user_id} not found")


def day_bounds(d: dt.date):
    """해당 날짜의 [00:00, 다음날 00:00) 경계를 datetime 으로 반환."""
    start = dt.datetime(d.year, d.month, d.day)
    return start, start + dt.timedelta(days=1)


def query_logs(db: Session, user_id: int, start: dt.datetime, end: dt.datetime):
    """started_at 인덱스를 타는 범위 조회.

    필터: user_id 등가(인덱스) + started_at 범위(인덱스 range scan).
    """
    return (
        db.query(PostureLog)
        .filter(
            PostureLog.user_id == user_id,
            PostureLog.started_at >= start,
            PostureLog.started_at < end,
        )
        .all()
    )


def aggregate(logs) -> dict:
    """로그 리스트를 자세별 시간/착석시간/나쁜자세 건수로 집계.

    ★ posture=0(앉지 않음)은 착석 시간에서 제외한다.
    """
    per_posture = {p: 0 for p in range(7)}
    bad_count = 0
    for log in logs:
        dur = log.duration_sec or 0
        per_posture[log.posture] = per_posture.get(log.posture, 0) + dur
        if log.posture in BAD_POSTURES:
            bad_count += 1
    total_sitting = sum(sec for p, sec in per_posture.items() if p != 0)
    return {
        "per_posture": per_posture,
        "total_sitting_sec": total_sitting,
        "bad_posture_count": bad_count,
    }


def build_postures_breakdown(per_posture: dict, total_sitting: int) -> List[dict]:
    """7클래스 고정 배열. percentage 는 착석시간 기준(posture=0 은 0.0)."""
    out = []
    for p in range(7):
        dur = per_posture.get(p, 0)
        if p == 0 or total_sitting == 0:
            pct = 0.0
        else:
            pct = round(dur / total_sitting * 100, 1)
        out.append({
            "posture": p,
            "label": POSTURE_LABELS[p],
            "duration_sec": dur,
            "percentage": pct,
        })
    return out


# =====================================================================
# Pydantic 모델 (요청/응답)
# =====================================================================
class PostureLogCreate(BaseModel):
    user_id: int
    posture: int = Field(..., ge=0, le=6)      # 0~6 벗어나면 422
    confidence: float = Field(..., ge=0.0, le=1.0)
    started_at: dt.datetime
    duration_sec: int = Field(..., ge=0)


class PostureLogOut(BaseModel):
    id: int
    user_id: int
    posture: int
    label: str
    confidence: float
    started_at: dt.datetime
    duration_sec: int


class PostureBreakdown(BaseModel):
    posture: int
    label: str
    duration_sec: int
    percentage: float


class HourlyBucket(BaseModel):
    hour: int
    sitting_sec: int
    by_posture: dict  # {posture_id(int): duration_sec}


class DailyReport(BaseModel):
    user_id: int
    date: dt.date
    total_sitting_sec: int
    postures: List[PostureBreakdown]
    hourly: List[HourlyBucket]
    bad_posture_count: int


class DailySummary(BaseModel):
    date: dt.date
    total_sitting_sec: int
    bad_posture_count: int


class WeeklyReport(BaseModel):
    user_id: int
    week_start: dt.date
    week_end: dt.date
    total_sitting_sec: int
    postures: List[PostureBreakdown]
    bad_posture_count: int
    daily: List[DailySummary]


class CalibrationItem(BaseModel):
    channel: int = Field(..., ge=0, le=NUM_CHANNELS - 1)  # 0~63
    max_value: int = Field(..., ge=1)                     # 0 나눗셈 방지


class CalibrationOut(BaseModel):
    channel: int
    max_value: int
    factor: float  # FULL_SCALE / max_value


class ChallengeDay(BaseModel):
    date: dt.date
    achieved: bool


class ChallengeStatus(BaseModel):
    user_id: int
    target_sec: int
    current_sec: int
    progress_percent: float
    week_history: List[ChallengeDay]


# =====================================================================
# 유지: 헬스체크
# =====================================================================
@app.get("/")
def read_root():
    return {"message": "posture-ai 서버 작동 중!", "time": str(dt.datetime.now())}


# =====================================================================
# 신규 엔드포인트
# =====================================================================
@app.post("/posture-logs", response_model=PostureLogOut)
def create_posture_log(body: PostureLogCreate, db: Session = Depends(get_db)):
    """자세가 '바뀔 때만' 앱이 호출해 한 행을 기록한다."""
    ensure_user(db, body.user_id)
    log = PostureLog(
        user_id=body.user_id,
        posture=body.posture,
        confidence=body.confidence,
        started_at=body.started_at,
        duration_sec=body.duration_sec,
    )
    db.add(log)
    db.commit()
    db.refresh(log)
    return {
        "id": log.id,
        "user_id": log.user_id,
        "posture": log.posture,
        "label": POSTURE_LABELS[log.posture],
        "confidence": log.confidence,
        "started_at": log.started_at,
        "duration_sec": log.duration_sec,
    }


@app.get("/reports/daily", response_model=DailyReport)
def report_daily(
    user_id: int = Query(...),
    date: dt.date = Query(...),  # YYYY-MM-DD
    db: Session = Depends(get_db),
):
    ensure_user(db, user_id)
    start, end = day_bounds(date)
    logs = query_logs(db, user_id, start, end)

    agg = aggregate(logs)
    total_sitting = agg["total_sitting_sec"]

    # 시간대별(1시간 단위) 자세 분포 — started_at 의 '시' 기준으로 귀속
    # TODO(hourly): 한 로그의 duration 전체를 started_at 의 '시'에 몰아서 귀속시킨다.
    #   정시를 걸치는 긴 구간(예: 10:50~11:20)을 시간대별로 쪼개지 않는 단순화.
    #   실제 로그 길이 분포를 확인한 뒤 시간대 분할이 필요한지 판단할 것.
    hourly_map = defaultdict(lambda: {"sitting_sec": 0, "by_posture": defaultdict(int)})
    for log in logs:
        if log.posture == 0:
            continue  # 착석 아님 → 시간대 분포에서 제외
        dur = log.duration_sec or 0
        h = log.started_at.hour
        hourly_map[h]["sitting_sec"] += dur
        hourly_map[h]["by_posture"][log.posture] += dur

    hourly = [
        {
            "hour": h,
            "sitting_sec": hourly_map[h]["sitting_sec"],
            "by_posture": dict(hourly_map[h]["by_posture"]),
        }
        for h in sorted(hourly_map.keys())
    ]

    return {
        "user_id": user_id,
        "date": date,
        "total_sitting_sec": total_sitting,
        "postures": build_postures_breakdown(agg["per_posture"], total_sitting),
        "hourly": hourly,
        "bad_posture_count": agg["bad_posture_count"],
    }


@app.get("/reports/weekly", response_model=WeeklyReport)
def report_weekly(
    user_id: int = Query(...),
    week: dt.date = Query(...),  # 주 안의 아무 날짜(YYYY-MM-DD) → 그 주 월~일로 스냅
    db: Session = Depends(get_db),
):
    ensure_user(db, user_id)
    monday = week - dt.timedelta(days=week.weekday())  # 월요일로 스냅
    sunday = monday + dt.timedelta(days=6)

    week_start, _ = day_bounds(monday)
    _, week_end_exclusive = day_bounds(sunday)

    # 주 전체 로그 1회 조회(인덱스 range) 후 일별로 나눠 집계
    logs = query_logs(db, user_id, week_start, week_end_exclusive)

    week_agg = aggregate(logs)

    daily = []
    for i in range(7):
        day = monday + dt.timedelta(days=i)
        d_start, d_end = day_bounds(day)
        day_logs = [l for l in logs if d_start <= l.started_at < d_end]
        d_agg = aggregate(day_logs)
        daily.append({
            "date": day,
            "total_sitting_sec": d_agg["total_sitting_sec"],
            "bad_posture_count": d_agg["bad_posture_count"],
        })

    return {
        "user_id": user_id,
        "week_start": monday,
        "week_end": sunday,
        "total_sitting_sec": week_agg["total_sitting_sec"],
        "postures": build_postures_breakdown(
            week_agg["per_posture"], week_agg["total_sitting_sec"]
        ),
        "bad_posture_count": week_agg["bad_posture_count"],
        "daily": daily,
    }


@app.get("/calibrations/{user_id}", response_model=List[CalibrationOut])
def get_calibrations(user_id: int, db: Session = Depends(get_db)):
    """채널별 보정값 조회. 보정값이 없으면 빈 배열."""
    ensure_user(db, user_id)
    rows = (
        db.query(Calibration)
        .filter(Calibration.user_id == user_id)
        .order_by(Calibration.channel)
        .all()
    )
    return [
        {
            "channel": r.channel,
            "max_value": r.max_value,
            "factor": round(FULL_SCALE / r.max_value, 4),
        }
        for r in rows
    ]


@app.post("/calibrations/{user_id}")
def upsert_calibrations(
    user_id: int,
    items: List[CalibrationItem],
    db: Session = Depends(get_db),
):
    """64채널 보정값 배열 upsert. (user_id, channel) 있으면 UPDATE, 없으면 INSERT."""
    ensure_user(db, user_id)
    inserted, updated = 0, 0
    for item in items:
        row = (
            db.query(Calibration)
            .filter(
                Calibration.user_id == user_id,
                Calibration.channel == item.channel,
            )
            .first()
        )
        if row:
            row.max_value = item.max_value
            updated += 1
        else:
            db.add(Calibration(
                user_id=user_id,
                channel=item.channel,
                max_value=item.max_value,
            ))
            inserted += 1
    db.commit()
    return {"message": "저장 완료", "inserted": inserted, "updated": updated}


@app.get("/challenges/{user_id}", response_model=ChallengeStatus)
def get_challenges(user_id: int, db: Session = Depends(get_db)):
    """오늘의 챌린지: 정자세(posture=1) 누적 시간이 목표(30분)에 얼마나 도달했는지."""
    ensure_user(db, user_id)
    TARGET_SEC = 1800  # 30분 고정
    GOOD_POSTURE = 1   # 정자세

    def good_sec_for_day(day: dt.date) -> int:
        d_start, d_end = day_bounds(day)
        logs = query_logs(db, user_id, d_start, d_end)
        return sum((l.duration_sec or 0) for l in logs if l.posture == GOOD_POSTURE)

    today = dt.date.today()
    current = good_sec_for_day(today)
    progress = round(min(100.0, current / TARGET_SEC * 100), 1) if TARGET_SEC else 0.0

    # 최근 7일(오늘 포함) 달성 여부
    week_history = []
    for i in range(6, -1, -1):
        day = today - dt.timedelta(days=i)
        week_history.append({
            "date": day,
            "achieved": good_sec_for_day(day) >= TARGET_SEC,
        })

    return {
        "user_id": user_id,
        "target_sec": TARGET_SEC,
        "current_sec": current,
        "progress_percent": progress,
        "week_history": week_history,
    }


# =====================================================================
# [DEPRECATED] 구 아키텍처 엔드포인트 — 삭제하지 않고 보존.
#   새 아키텍처에서는 원시 데이터를 서버로 보내지 않고, 자세 판정도 앱에서 한다.
#   재활성화하려면 상단의 SensorData / posture_classifier import 를 되살려야 함.
# =====================================================================
# # 센서 데이터 저장 API (자세 판정 포함)  ← 폐기: 원시 데이터 서버 저장 안 함
# @app.post("/sensor-data")
# def save_sensor_data(data: dict, db: Session = Depends(get_db)):
#     s1 = data.get("sensor_1", 0)
#     s2 = data.get("sensor_2", 0)
#     s3 = data.get("sensor_3", 0)
#     s4 = data.get("sensor_4", 0)
#     s5 = data.get("sensor_5", 0)
#     s6 = data.get("sensor_6", 0)
#     posture = classify_posture(s1, s2, s3, s4, s5, s6)
#     feedback = get_posture_feedback(posture)
#     sensor = SensorData(
#         sensor_1=s1, sensor_2=s2, sensor_3=s3,
#         sensor_4=s4, sensor_5=s5, sensor_6=s6,
#         posture=posture,
#         timestamp=datetime.now()
#     )
#     db.add(sensor)
#     db.commit()
#     return {
#         "message": "저장 완료!",
#         "posture": posture,
#         "feedback": feedback,
#         "timestamp": str(sensor.timestamp)
#     }
#
# # 저장된 센서 데이터 조회 API  ← 폐기: 원시 데이터 조회 불필요
# @app.get("/sensor-data")
# def get_sensor_data(db: Session = Depends(get_db)):
#     data = db.query(SensorData).order_by(SensorData.timestamp.desc()).limit(100).all()
#     return data
#
# # 최근 자세 1개 조회 API  ← 폐기: 실시간 상태는 앱이 온디바이스로 자체 판단
# @app.get("/current-posture")
# def get_current_posture(db: Session = Depends(get_db)):
#     latest = db.query(SensorData).order_by(SensorData.timestamp.desc()).first()
#     if not latest:
#         return {"posture": "데이터 없음", "feedback": None}
#     feedback = get_posture_feedback(latest.posture)
#     return {
#         "posture": latest.posture,
#         "feedback": feedback,
#         "timestamp": str(latest.timestamp)
#     }
