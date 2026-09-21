import torch
import torch.nn as nn
import numpy as np
from fastapi import FastAPI, Depends
from sqlalchemy.orm import Session
from datetime import datetime
from database import SessionLocal, init_db, SensorData

# =====================================================================
# [보존 1] 다혜님의 1D-CNN 모델 아키텍처 구조 100% 그대로 유지
# =====================================================================
class PostureCNN(nn.Module):
    def __init__(self):
        super(PostureCNN, self).__init__()
        self.conv1 = nn.Conv1d(in_channels=1, out_channels=32, kernel_size=3, padding=1)
        self.pool = nn.MaxPool1d(kernel_size=2)
        self.fc1 = nn.Linear(96, 64) 
        self.fc2 = nn.Linear(64, 7)  # p0 ~ p6 총 7종 분류

    def forward(self, x):
        x = self.pool(torch.relu(self.conv1(x)))
        x = x.view(x.size(0), -1)  # Flatten
        x = torch.relu(self.fc1(x))
        x = self.fc2(x)
        return x

app = FastAPI()

# 글로벌 변수로 모델과 인코딩 맵 정의
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
cnn_model = PostureCNN().to(device)

# 가상의 Z-Score 정규화를 위한 학습 데이터 기준 Mean, Std 상수 (기존 함수 로직 계승)
# 실전 캘리브레이션을 위해 기본값 세팅 (필요시 실제 학습데이터 값으로 변경 가능)
GLOBAL_MEAN = 500.0
GLOBAL_STD = 250.0

LABEL_MAP = {
    0: "p0_앉지않음", 1: "p1_정자세", 2: "p2_앞으로숙이기",
    3: "p3_오른다리꼬기", 4: "p4_왼다리꼬기", 5: "p5_오른쪽기대기", 6: "p6_왼쪽기대기"
}

@app.on_event("startup")
def startup():
    init_db()
    # 서버 시작 시 가중치 파일 로드 (만약 파일이 아직 없다면 구조만 생성한 채 예외 처리)
    try:
        cnn_model.load_state_dict(torch.load('posture_model.pt', map_location=device))
        cnn_model.eval()
        print("🎉 1D-CNN 모델 가중치 로드 성공!")
    except Exception as e:
        print(f"⚠️ 모델 파일(posture_model.pt)을 로드할 수 없어 기본 모델 구조로 대기합니다: {e}")

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# =====================================================================
# [보존 2] posture_classifier.py 내의 규칙 기반 판정 로직 100% 보존
# =====================================================================
def classify_posture_rule(s1, s2, s3, s4, s5, s6):
    front_avg = (s1 + s2) / 2
    back_avg  = (s5 + s6) / 2
    left_avg  = (s1 + s3 + s5) / 3
    right_avg = (s2 + s4 + s6) / 3

    if abs(left_avg - right_avg) > 200:
        return "다리꼬기"
    if front_avg > 500 and front_avg - back_avg > 250:
        return "거북목"
    if back_avg > 500 and back_avg - front_avg > 250:
        return "기대기"
    return "바른자세"

def get_posture_feedback(posture):
    feedback_map = {
        "바른자세": "아주 좋습니다! 현재 자세를 유지하세요.",
        "거북목": "목이 앞으로 나와있습니다. 어깨를 펴고 턱을 당기세요.",
        "기대기": "허리에 무리가 갈 수 있으니 등받이에 엉덩이를 바짝 붙여주세요.",
        "다리꼬기": "골반 불균형을 유발합니다. 다리를 풀어주세요."
    }
    return feedback_map.get(posture, "자세를 점검해 보세요.")

# =====================================================================
# [보존 3] API 엔드포인트 통합 및 확장 (시뮬레이터 변수 + 데이터셋 변수 모두 수용)
# =====================================================================
@app.post("/sensor-data")
def save_sensor_data(data: dict, db: Session = Depends(get_db)):
    
    # 1. 시뮬레이터 형태(sensor_1~6)와 데이터셋 형태(F_Left 등)의 매핑 유연화 (둘 다 지원 가능)
    s1 = data.get("sensor_1", data.get("F_Left", 0.0))
    s2 = data.get("sensor_2", data.get("F_Right", 0.0))
    s3 = data.get("sensor_3", data.get("B_Left", 0.0))  # 딥러닝 매핑 순서 보존 유도
    s4 = data.get("sensor_4", data.get("B_Right", 0.0))
    s5 = data.get("sensor_5", data.get("BR_Left", 0.0))
    s6 = data.get("sensor_6", data.get("BR_Right", 0.0))

    # 2. 기존 규칙 기반 판정 결과 추출
    rule_posture = classify_posture_rule(s1, s2, s3, s4, s5, s6)
    feedback = get_posture_feedback(rule_posture)

    # 3. 1D-CNN 딥러닝 기반 실시간 판정 진행 (Z-Score 적용)
    raw_array = np.array([s1, s2, s3, s4, s5, s6], dtype=np.float32)
    norm_array = (raw_array - GLOBAL_MEAN) / (GLOBAL_STD + 1e-7)
    
    # PyTorch 입력 텐서 모양으로 변환 (Batch=1, Channel=1, Features=6)
    input_tensor = torch.tensor(norm_array).unsqueeze(0).unsqueeze(0).to(device)
    
    with torch.no_grad():
        outputs = cnn_model(input_tensor)
        pred_idx = torch.argmax(outputs, dim=1).item()
        cnn_posture = LABEL_MAP.get(pred_idx, "알 수 없음")

    # 4. 데이터베이스 저장 (기존 필드를 유지하되 판정 결과만 세분화하여 기록 가능)
    sensor_record = SensorData(
        sensor_1=float(s1), sensor_2=float(s2), sensor_3=float(s3),
        sensor_4=float(s4), sensor_5=float(s5), sensor_6=float(s6),
        posture=f"Rule: {rule_posture} / CNN: {cnn_posture}", # 두 정보를 하나로 병합 기록
        timestamp=datetime.now()
    )
    db.add(sensor_record)
    db.commit()

    # 최신 실시간 조회를 위한 임시 캐싱용 데이터 반환 구조 확장
    app.state.latest_posture = {
        "rule_posture": rule_posture,
        "cnn_posture": cnn_posture,
        "feedback": feedback,
        "sensors": [s1, s2, s3, s4, s5, s6]
    }

    return {
        "message": "저장 완료!",
        "rule_posture": rule_posture,
        "cnn_posture": cnn_posture,
        "feedback": feedback,
        "timestamp": str(sensor_record.timestamp)
    }

# Flutter 앱이 간편하게 최신 상태를 폴링(가져오기)할 수 있도록 라우트 추가
@app.get("/current-posture")
def get_current_posture():
    if hasattr(app.state, 'latest_posture'):
        return app.state.latest_posture
    return {"rule_posture": "데이터 없음", "cnn_posture": "데이터 없음", "feedback": "의자에 앉아주세요.", "sensors": [0,0,0,0,0,0]}
