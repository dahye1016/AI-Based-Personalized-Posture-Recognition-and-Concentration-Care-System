"""
database_64ch.py

기존 database.py를 64채널(방석 32 + 등받이 32) 기준으로 확장한 버전.
DB 파일 경로는 기존과 동일하게 ./data/posture.db를 사용합니다.
"""

from sqlalchemy import create_engine, Column, Integer, Float, String, DateTime
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from datetime import datetime

DATABASE_URL = "sqlite:///./data/posture.db"

engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


class SensorData(Base):
    __tablename__ = "sensor_data_64ch"

    id = Column(Integer, primary_key=True, index=True)
    # 방석 32채널
    seat_1 = Column(Float); seat_2 = Column(Float); seat_3 = Column(Float); seat_4 = Column(Float)
    seat_5 = Column(Float); seat_6 = Column(Float); seat_7 = Column(Float); seat_8 = Column(Float)
    seat_9 = Column(Float); seat_10 = Column(Float); seat_11 = Column(Float); seat_12 = Column(Float)
    seat_13 = Column(Float); seat_14 = Column(Float); seat_15 = Column(Float); seat_16 = Column(Float)
    seat_17 = Column(Float); seat_18 = Column(Float); seat_19 = Column(Float); seat_20 = Column(Float)
    seat_21 = Column(Float); seat_22 = Column(Float); seat_23 = Column(Float); seat_24 = Column(Float)
    seat_25 = Column(Float); seat_26 = Column(Float); seat_27 = Column(Float); seat_28 = Column(Float)
    seat_29 = Column(Float); seat_30 = Column(Float); seat_31 = Column(Float); seat_32 = Column(Float)
    # 등받이 32채널
    back_1 = Column(Float); back_2 = Column(Float); back_3 = Column(Float); back_4 = Column(Float)
    back_5 = Column(Float); back_6 = Column(Float); back_7 = Column(Float); back_8 = Column(Float)
    back_9 = Column(Float); back_10 = Column(Float); back_11 = Column(Float); back_12 = Column(Float)
    back_13 = Column(Float); back_14 = Column(Float); back_15 = Column(Float); back_16 = Column(Float)
    back_17 = Column(Float); back_18 = Column(Float); back_19 = Column(Float); back_20 = Column(Float)
    back_21 = Column(Float); back_22 = Column(Float); back_23 = Column(Float); back_24 = Column(Float)
    back_25 = Column(Float); back_26 = Column(Float); back_27 = Column(Float); back_28 = Column(Float)
    back_29 = Column(Float); back_30 = Column(Float); back_31 = Column(Float); back_32 = Column(Float)

    posture = Column(String)
    timestamp = Column(DateTime, default=datetime.now)


def init_db():
    Base.metadata.create_all(bind=engine)


SEAT_COLS = [f"seat_{i+1}" for i in range(32)]
BACK_COLS = [f"back_{i+1}" for i in range(32)]
ALL_COLS = SEAT_COLS + BACK_COLS
