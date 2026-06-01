from fastapi import FastAPI, Depends
from sqlalchemy.orm import Session
from database import SessionLocal, init_db, SensorData
from posture_classifier import classify_posture, get_posture_feedback
from datetime import datetime

app = FastAPI()

# 서버 시작할 때 DB 테이블 자동 생성
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

# 서버 상태 확인
@app.get("/")
def read_root():
    return {"message": "posture-ai 서버 작동 중!", "time": str(datetime.now())}

# 센서 데이터 저장 API (자세 판정 포함)
@app.post("/sensor-data")
def save_sensor_data(data: dict, db: Session = Depends(get_db)):
    
    # 센서값 꺼내기
    s1 = data.get("sensor_1", 0)
    s2 = data.get("sensor_2", 0)
    s3 = data.get("sensor_3", 0)
    s4 = data.get("sensor_4", 0)
    s5 = data.get("sensor_5", 0)
    s6 = data.get("sensor_6", 0)

    # 자세 판정 (서버가 스스로 판단!)
    posture = classify_posture(s1, s2, s3, s4, s5, s6)
    feedback = get_posture_feedback(posture)

    # DB 저장
    sensor = SensorData(
        sensor_1=s1, sensor_2=s2, sensor_3=s3,
        sensor_4=s4, sensor_5=s5, sensor_6=s6,
        posture=posture,
        timestamp=datetime.now()
    )
    db.add(sensor)
    db.commit()

    return {
        "message": "저장 완료!",
        "posture": posture,
        "feedback": feedback,
        "timestamp": str(sensor.timestamp)
    }

# 저장된 센서 데이터 조회 API
@app.get("/sensor-data")
def get_sensor_data(db: Session = Depends(get_db)):
    data = db.query(SensorData).order_by(SensorData.timestamp.desc()).limit(100).all()
    return data

# 최근 자세 1개만 조회 API (앱에서 실시간으로 쓸 용도)
@app.get("/current-posture")
def get_current_posture(db: Session = Depends(get_db)):
    latest = db.query(SensorData).order_by(SensorData.timestamp.desc()).first()
    if not latest:
        return {"posture": "데이터 없음", "feedback": None}
    feedback = get_posture_feedback(latest.posture)
    return {
        "posture": latest.posture,
        "feedback": feedback,
        "timestamp": str(latest.timestamp)
    }