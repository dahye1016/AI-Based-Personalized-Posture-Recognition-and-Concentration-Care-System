from sqlalchemy import create_engine, Column, Integer, Float, String, DateTime
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from datetime import datetime

# DB 파일 위치 설정 (data 폴더 안에 posture.db 파일로 저장됨)
DATABASE_URL = "sqlite:///./data/posture.db"

engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

# 센서 데이터 테이블 구조 정의
class SensorData(Base):
    __tablename__ = "sensor_data"

    id = Column(Integer, primary_key=True, index=True)
    sensor_1 = Column(Float)  # FSR 센서 1번값
    sensor_2 = Column(Float)  # FSR 센서 2번값
    sensor_3 = Column(Float)  # FSR 센서 3번값
    sensor_4 = Column(Float)  # FSR 센서 4번값
    sensor_5 = Column(Float)  # FSR 센서 5번값
    sensor_6 = Column(Float)  # FSR 센서 6번값
    posture = Column(String)  # 자세 판정 결과
    timestamp = Column(DateTime, default=datetime.now)

# 테이블 생성
def init_db():
    Base.metadata.create_all(bind=engine)