"""
DB 스키마.

[변경 이유]
  기존: sensor_1 ~ sensor_6 컬럼 6개 (FSR 6개 전제)
  현재: PoseLab Seat 은 32채널이라 컬럼 32개를 만드는 건 말이 안 됩니다.
       → channels 를 JSON 문자열로 통째 저장하고,
         자주 조회하는 특징값만 별도 컬럼으로 뽑아 인덱싱합니다.
"""

import json
import os
from datetime import datetime

from sqlalchemy import (
    Column, DateTime, Float, Integer, String, Text, create_engine, Index,
)
from sqlalchemy.orm import declarative_base, sessionmaker

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.join(BASE_DIR, "data")
os.makedirs(DATA_DIR, exist_ok=True)

# 기존 posture.db 는 스키마가 완전히 달라서 재사용 불가 → 새 파일로 분리
DATABASE_URL = f"sqlite:///{os.path.join(DATA_DIR, 'poselab.db')}"

engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


class SensorFrame(Base):
    """센서 프레임 1건 (32채널 + 파생 특징 + 판정결과)"""

    __tablename__ = "sensor_frame"

    id = Column(Integer, primary_key=True, index=True)
    timestamp = Column(DateTime, default=datetime.now, index=True)
    device_id = Column(String(32), default="seat")   # seat / backrest

    channels_json = Column(Text)     # [32개 raw 값]

    # 조회/집계에 쓰는 특징
    sum_val = Column(Float)
    max_val = Column(Float)
    cof_x = Column(Float)
    cof_y = Column(Float)
    lr_balance = Column(Float)
    fb_balance = Column(Float)
    contact_ratio = Column(Float)
    area_100 = Column(Float)
    area_500 = Column(Float)
    seated = Column(Integer, default=1)

    posture = Column(String(32), index=True)
    confidence = Column(Float)

    @property
    def channels(self):
        return json.loads(self.channels_json or "[]")

    def to_dict(self):
        return {
            "id": self.id,
            "timestamp": self.timestamp.isoformat() if self.timestamp else None,
            "device_id": self.device_id,
            "channels": self.channels,
            "sum": self.sum_val,
            "max": self.max_val,
            "cof_x": self.cof_x,
            "cof_y": self.cof_y,
            "lr_balance": self.lr_balance,
            "fb_balance": self.fb_balance,
            "contact_ratio": self.contact_ratio,
            "seated": bool(self.seated),
            "posture": self.posture,
            "confidence": self.confidence,
        }


class Calibration(Base):
    """
    사용자가 '초기 설정 > 자세 등록' 화면에서 직접 등록한 기준 자세.
    이게 있으면 하드코딩 임계값 대신 이 사람 몸에 맞춘 판정을 합니다.
    (프로젝트 제목의 'Personalized' 가 실제로 구현되는 지점)
    """

    __tablename__ = "calibration"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(String(64), default="default", index=True)
    label = Column(String(32), index=True)
    vector_json = Column(Text)       # 비교용 정규화 벡터
    frame_json = Column(Text)        # 등록 당시 평균 raw 프레임 (히트맵 미리보기용)
    samples = Column(Integer, default=0)
    created_at = Column(DateTime, default=datetime.now)

    def to_dict(self):
        return {
            "id": self.id,
            "user_id": self.user_id,
            "label": self.label,
            "vector": json.loads(self.vector_json or "[]"),
            "frame": json.loads(self.frame_json or "[]"),
            "samples": self.samples,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }


Index("ix_frame_user_time", SensorFrame.device_id, SensorFrame.timestamp)


def init_db():
    Base.metadata.create_all(bind=engine)
