"""
PostureCare 서버 (PoseLab Seat 32채널 버전)

실행:  cd server && uvicorn main:app --reload --host 0.0.0.0 --port 8000
문서:  http://127.0.0.1:8000/docs

[구조]
   Core 보드 --USB--> bridge/main.py --POST /sensor-frame--> 이 서버 --> Flutter 앱
"""

import json
import os
import sys
from collections import Counter, defaultdict
from datetime import datetime, timedelta
from typing import List, Optional

from fastapi import Depends, FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from database import Calibration, SensorFrame, SessionLocal, init_db
from posture_classifier import POSTURES, classify, get_posture_feedback

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "..", "bridge"))
import features as F        # noqa: E402
import layout as L          # noqa: E402

app = FastAPI(title="PostureCare API", version="2.0.0")

# Flutter 웹/실기기에서 붙을 수 있게 CORS 허용
app.add_middleware(
    CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"],
)


@app.on_event("startup")
def startup():
    init_db()


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


# --------------------------------------------------------------- 스키마
class FramePayload(BaseModel):
    frame: List[int] = Field(..., description="32채널 raw 값")
    features: Optional[dict] = None
    device_id: str = "seat"
    user_id: str = "default"


class CalibPayload(BaseModel):
    label: str
    frame: List[int]
    features: Optional[dict] = None
    samples: int = 0
    user_id: str = "default"


# --------------------------------------------------------------- 기본
@app.get("/")
def root():
    return {
        "message": "PostureCare 서버 작동 중",
        "version": "2.0.0",
        "channels": L.N_CHANNELS,
        "time": datetime.now().isoformat(),
    }


@app.get("/layout")
def get_layout():
    """앱이 히트맵을 그릴 때 쓰는 센서 물리 배치."""
    return {
        "n_channels": L.N_CHANNELS,
        "width_mm": L.WIDTH_MM,
        "height_mm": L.HEIGHT_MM,
        "positions": [{"ch": ch, "x": x, "y": y}
                      for ch, (x, y) in sorted(L.POSITIONS.items())],
        "rows": {str(k): {"left": v[0], "right": v[1]} for k, v in L.ROWS.items()},
    }


# --------------------------------------------------------------- 수집
@app.post("/sensor-frame")
def save_frame(payload: FramePayload, db: Session = Depends(get_db)):
    if len(payload.frame) != L.N_CHANNELS:
        raise HTTPException(400, f"채널 수가 {len(payload.frame)}개입니다. "
                                 f"{L.N_CHANNELS}개여야 합니다.")

    feat = payload.features or F.extract(payload.frame)

    calibs = [c.to_dict() for c in db.query(Calibration)
              .filter(Calibration.user_id == payload.user_id).all()]
    posture, confidence = classify(feat, calibs)

    row = SensorFrame(
        device_id=payload.device_id,
        channels_json=json.dumps(payload.frame),
        sum_val=feat.get("sum"),
        max_val=feat.get("max"),
        cof_x=feat.get("cof_x"),
        cof_y=feat.get("cof_y"),
        lr_balance=feat.get("lr_balance"),
        fb_balance=feat.get("fb_balance"),
        contact_ratio=feat.get("contact_ratio"),
        area_100=feat.get("area_100"),
        area_500=feat.get("area_500"),
        seated=int(bool(feat.get("seated"))),
        posture=posture,
        confidence=confidence,
        timestamp=datetime.now(),
    )
    db.add(row)
    db.commit()

    return {
        "message": "저장 완료",
        "posture": posture,
        "confidence": round(confidence, 3),
        "feedback": get_posture_feedback(posture),
        "calibrated": bool(calibs),
        "timestamp": row.timestamp.isoformat(),
    }


# --------------------------------------------------------------- 조회
@app.get("/current-posture")
def current_posture(device_id: str = "seat", db: Session = Depends(get_db)):
    row = (db.query(SensorFrame)
             .filter(SensorFrame.device_id == device_id)
             .order_by(SensorFrame.timestamp.desc()).first())
    if not row:
        return {"posture": "데이터 없음", "confidence": 0.0,
                "feedback": get_posture_feedback("없음"), "timestamp": None}

    # 같은 자세를 얼마나 유지했는지 (앱 홈의 "24분 유지 중")
    held_since = row.timestamp
    for prev in (db.query(SensorFrame)
                   .filter(SensorFrame.device_id == device_id)
                   .order_by(SensorFrame.timestamp.desc()).limit(2000).all()):
        if prev.posture != row.posture:
            break
        held_since = prev.timestamp

    return {
        "posture": row.posture,
        "confidence": round(row.confidence or 0, 3),
        "feedback": get_posture_feedback(row.posture),
        "held_seconds": int((row.timestamp - held_since).total_seconds()),
        "seated": bool(row.seated),
        "cof": {"x": row.cof_x, "y": row.cof_y},
        "timestamp": row.timestamp.isoformat(),
    }


@app.get("/heatmap")
def heatmap(device_id: str = "seat", db: Session = Depends(get_db)):
    """앱 홈 화면의 좌석/등받이 압력 격자용."""
    row = (db.query(SensorFrame)
             .filter(SensorFrame.device_id == device_id)
             .order_by(SensorFrame.timestamp.desc()).first())
    if not row:
        return {"channels": [0] * L.N_CHANNELS, "max": 0, "timestamp": None}
    return {
        "channels": row.channels,
        "max": row.max_val,
        "sum": row.sum_val,
        "posture": row.posture,
        "timestamp": row.timestamp.isoformat(),
    }


@app.get("/frames")
def list_frames(limit: int = Query(100, le=1000), device_id: str = "seat",
                db: Session = Depends(get_db)):
    rows = (db.query(SensorFrame)
              .filter(SensorFrame.device_id == device_id)
              .order_by(SensorFrame.timestamp.desc()).limit(limit).all())
    return [r.to_dict() for r in rows]


# --------------------------------------------------------------- 자세 등록
@app.post("/calibration")
def add_calibration(payload: CalibPayload, db: Session = Depends(get_db)):
    if len(payload.frame) != L.N_CHANNELS:
        raise HTTPException(400, f"채널 수가 {len(payload.frame)}개입니다.")

    feat = payload.features or F.extract(payload.frame)
    vector = F.to_vector(feat)

    # 같은 라벨이 이미 있으면 덮어쓰기 (재보정)
    existing = (db.query(Calibration)
                  .filter(Calibration.user_id == payload.user_id,
                          Calibration.label == payload.label).first())
    row = existing or Calibration(user_id=payload.user_id, label=payload.label)
    row.vector_json = json.dumps(vector)
    row.frame_json = json.dumps(payload.frame)
    row.samples = payload.samples
    row.created_at = datetime.now()
    db.add(row)
    db.commit()

    done = db.query(Calibration).filter(
        Calibration.user_id == payload.user_id).count()
    return {"message": "자세 등록 완료", "label": payload.label,
            "registered": done, "total_expected": len(POSTURES)}


@app.get("/calibration")
def list_calibration(user_id: str = "default", db: Session = Depends(get_db)):
    rows = db.query(Calibration).filter(Calibration.user_id == user_id).all()
    registered = {r.label for r in rows}
    return {
        "items": [r.to_dict() for r in rows],
        "registered": sorted(registered),
        "missing": [p for p in POSTURES if p not in registered],
        "complete": all(p in registered for p in POSTURES),
    }


@app.delete("/calibration")
def reset_calibration(user_id: str = "default", db: Session = Depends(get_db)):
    n = db.query(Calibration).filter(Calibration.user_id == user_id).delete()
    db.commit()
    return {"message": "자세 재보정을 위해 초기화했습니다", "deleted": n}


# --------------------------------------------------------------- 리포트
@app.get("/report/daily")
def report_daily(date: Optional[str] = None, device_id: str = "seat",
                 db: Session = Depends(get_db)):
    """앱 '리포트' 탭 — 자세 분포 + 시간대별."""
    day = datetime.fromisoformat(date).date() if date else datetime.now().date()
    start = datetime.combine(day, datetime.min.time())
    end = start + timedelta(days=1)

    rows = (db.query(SensorFrame)
              .filter(SensorFrame.device_id == device_id,
                      SensorFrame.timestamp >= start,
                      SensorFrame.timestamp < end).all())
    seated = [r for r in rows if r.seated]

    if not seated:
        return {"date": str(day), "total_frames": 0, "distribution": {},
                "hourly": [], "good_ratio": 0.0, "seated_seconds": 0}

    counts = Counter(r.posture for r in seated)
    total = len(seated)
    distribution = {k: round(v / total * 100, 1) for k, v in counts.most_common()}

    hourly = defaultdict(Counter)
    for r in seated:
        hourly[r.timestamp.hour][r.posture] += 1

    # 브리지 기본 전송 주기 2Hz → 프레임 1개 = 0.5초
    seconds_per_frame = 0.5

    return {
        "date": str(day),
        "total_frames": total,
        "seated_seconds": int(total * seconds_per_frame),
        "distribution": distribution,
        "good_ratio": round(counts.get("정자세", 0) / total * 100, 1),
        "hourly": [
            {"hour": h,
             "dominant": c.most_common(1)[0][0],
             "counts": dict(c),
             "good_ratio": round(c.get("정자세", 0) / sum(c.values()) * 100, 1)}
            for h, c in sorted(hourly.items())
        ],
        "worst_hour": max(
            hourly.items(),
            key=lambda kv: 1 - kv[1].get("정자세", 0) / sum(kv[1].values()),
        )[0],
    }


@app.get("/report/weekly")
def report_weekly(device_id: str = "seat", db: Session = Depends(get_db)):
    today = datetime.now().date()
    out = []
    for i in range(6, -1, -1):
        d = today - timedelta(days=i)
        r = report_daily(date=str(d), device_id=device_id, db=db)
        out.append({"date": str(d), "good_ratio": r["good_ratio"],
                    "seated_seconds": r["seated_seconds"]})
    return {"days": out}
