from sqlalchemy import (
    create_engine, Column, Integer, Float, String, DateTime,
    ForeignKey, UniqueConstraint,
)
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from datetime import datetime

# DB 파일 위치 설정 (data 폴더 안에 posture.db 파일로 저장됨)
DATABASE_URL = "sqlite:///./data/posture.db"

engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


# =====================================================================
# [DEPRECATED] 구 아키텍처(서버 판정, 6채널)용 테이블.
#   신규 코드에서 사용 금지.
#   - 원시 압력을 서버에 저장하던 시절의 모델이다.
#   - 새 아키텍처: 원시 데이터는 서버로 안 보내고, 앱에서 온디바이스(TFLite)로
#     7클래스 판정한 "결과"만 PostureLog 로 저장한다.
#   - 기존 테스트 데이터 보존을 위해 테이블 자체는 남겨둔다(삭제하지 않음).
# =====================================================================
class SensorData(Base):
    """DEPRECATED: 구 아키텍처(서버 판정, 6채널)용. 신규 코드에서 사용 금지."""
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


# =====================================================================
# [신규 아키텍처] users / posture_logs / calibrations
#   자세 판정은 앱(TFLite, 7클래스)이 하고, 서버는 "결과"만 저장·집계한다.
# =====================================================================
class User(Base):
    """사용자. 자세 로그와 보정값이 이 사용자에 귀속된다."""
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String)
    created_at = Column(DateTime, default=datetime.now)


class PostureLog(Base):
    """자세 판정 결과 로그.

    ★ 설계 의도:
      자세가 변경될 때만 1행 기록한다. 초당 저장 방식이 아니다.
      하루 8시간 착석 기준 초당 저장은 28,800행이지만
      변화 시점만 기록하면 수백 행으로 충분하며 리포트 집계 성능이 크게 좋아진다.

    한 행 = "started_at 시각부터 duration_sec 초 동안 posture 자세를 유지했다".
    """
    __tablename__ = "posture_logs"

    id = Column(Integer, primary_key=True, index=True)
    # 리포트 조회가 user_id + started_at 기준이라 두 컬럼에 인덱스를 건다.
    user_id = Column(Integer, ForeignKey("users.id"), index=True)
    posture = Column(Integer)          # 0~6 (constants.POSTURE_LABELS 참조)
    confidence = Column(Float)         # 모델 확신도 0.0~1.0
    started_at = Column(DateTime, index=True)
    duration_sec = Column(Integer)     # 해당 자세 유지 시간(초)


class Calibration(Base):
    """사용자별 채널 보정값.

    체형 차이로 채널마다 최대 압력이 다르다. 채널별 max_value 를 저장해두고
    보정 factor = FULL_SCALE / max_value 로 정규화한다.
    한 사용자의 한 채널은 하나의 보정값만 가진다 → (user_id, channel) 유일.
    """
    __tablename__ = "calibrations"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), index=True)
    channel = Column(Integer)      # 0~63 (constants.NUM_CHANNELS 참조)
    max_value = Column(Integer)    # 해당 채널의 개인 최대 압력값
    updated_at = Column(DateTime, default=datetime.now, onupdate=datetime.now)

    __table_args__ = (
        UniqueConstraint("user_id", "channel", name="uq_user_channel"),
    )


# 테이블 생성
def init_db():
    """정의된 모든 테이블 중 '아직 없는 것'만 생성한다.

    create_all 은 이미 존재하는 테이블(sensor_data 포함)은 건드리지 않으므로,
    기존 테스트 데이터를 그대로 둔 채 신규 3개 테이블만 추가된다.
    """
    Base.metadata.create_all(bind=engine)
