"""
server_64ch.py

방석 32채널 + 등받이 32채널 = 64채널 데이터를 받아서
1D-CNN으로 자세(p1~p8)를 판정하는 서버.

실행 전 준비물 (train_posture_cnn_64ch.py를 먼저 실행해서 생성):
- posture_model_64ch.pt
- norm_stats_64ch.json
- database_64ch.py (같은 폴더)
"""

import json
import numpy as np
import torch
import torch.nn as nn
from fastapi import FastAPI, Depends
from sqlalchemy.orm import Session
from datetime import datetime
from database_64ch import SessionLocal, init_db, SensorData, SEAT_COLS, BACK_COLS, ALL_COLS
from calibration import CalibrationSession, load_personal_stats


class PostureCNN64(nn.Module):
    def __init__(self, num_classes: int):
        super(PostureCNN64, self).__init__()
        self.conv1 = nn.Conv1d(in_channels=1, out_channels=32, kernel_size=3, padding=1)
        self.pool = nn.MaxPool1d(kernel_size=2)
        self.fc1 = nn.Linear(1024, 128)
        self.fc2 = nn.Linear(128, num_classes)

    def forward(self, x):
        x = self.pool(torch.relu(self.conv1(x)))
        x = x.view(x.size(0), -1)
        x = torch.relu(self.fc1(x))
        x = self.fc2(x)
        return x


app = FastAPI()
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

with open("norm_stats_64ch.json", "r", encoding="utf-8") as f:
    norm_stats = json.load(f)

SENSOR_COLS_ORDER = norm_stats["sensor_cols_order"]  # seat_1~32 -> back_1~32
SENSOR_MEAN = np.array(norm_stats["mean"], dtype=np.float32)
SENSOR_STD = np.array(norm_stats["std"], dtype=np.float32)
LABEL_CLASSES = norm_stats["label_classes"]
NUM_CLASSES = norm_stats["num_classes"]

print(f"📊 64채널 정규화 통계 로드 완료 (mean/std shape: {SENSOR_MEAN.shape})")
print(f"📊 라벨 순서 ({NUM_CLASSES}종): {LABEL_CLASSES}")

# =====================================================================
# 표시용 이름 매핑 (임시 배정 - 데이터 근거 아님, 우리 프로젝트 계획서의
# 7종 자세명을 순번대로 기계적으로 배정한 것. 실측 데이터 확보 후
# 실제 라벨링으로 교체 예정)
# =====================================================================
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

cnn_model = PostureCNN64(num_classes=NUM_CLASSES).to(device)

# =====================================================================
# 개인 캘리브레이션 (수행계획서의 "착석 초기 2분 학습 -> 개인별 임계치" 기능)
#    - 캘리브레이션이 끝나면 PERSONAL_MEAN/STD가 채워지고, 그 이후
#      정규화는 학습 데이터 전체 평균(SENSOR_MEAN) 대신 이 값을 사용함
#    - 서버 재시작 시 이전에 저장된 개인 통계가 있으면 자동으로 불러옴
# =====================================================================
calib_session = CalibrationSession()
PERSONAL_MEAN, PERSONAL_STD, _personal_info = load_personal_stats()
if PERSONAL_MEAN is not None:
    print(f"🙋 저장된 개인 캘리브레이션 결과를 불러왔습니다 ({_personal_info['calibrated_at']}, 샘플 {_personal_info['num_samples']}개)")


@app.on_event("startup")
def startup():
    init_db()
    try:
        cnn_model.load_state_dict(torch.load("posture_model_64ch.pt", map_location=device))
        cnn_model.eval()
        print("🎉 64채널 1D-CNN 모델 가중치 로드 성공!")
    except Exception as e:
        print(f"⚠️ 모델 파일을 로드할 수 없어 기본 구조로 대기합니다: {e}")


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


# =====================================================================
# 캘리브레이션 API
# =====================================================================
@app.post("/calibration/start")
def start_calibration(duration_sec: int = 120):
    """새로 앉은 사람의 개인별 압력 기준을 잡기 시작. 기본 120초(2분)."""
    calib_session.start(duration_sec=duration_sec)
    return {
        "message": f"캘리브레이션을 시작합니다. {duration_sec}초 동안 평소처럼 앉아서 /sensor-data 전송을 계속하세요.",
        "status": calib_session.status(),
    }


@app.get("/calibration/status")
def calibration_status():
    return calib_session.status()


@app.post("/calibration/cancel")
def cancel_calibration():
    calib_session.cancel()
    return {"message": "캘리브레이션이 취소되었습니다."}


# =====================================================================
# 구역별 요약 진단값 (판정용 X, 사람이 눈으로 확인하기 위한 참고용)
#
#    [방석 32채널] — 2026-08-09 팀 실측 기준(posturecare_demo_3.html)의
#    실제 물리적 센서 배치를 그대로 반영함:
#      rightHip(0-4), leftHip(5-9), rightMid(10-16), leftMid(17-23),
#      rightKnee(24-27), leftKnee(28-31)  (seat_1=index0 기준)
#
#    [등받이 32채널] — 아직 등받이 센서가 도착 전이라 실제 구역 정의가
#    없음. 실제 센서 배치가 정해지면 이 부분도 방석처럼 실제 구역명으로
#    교체 필요. 그 전까지는 8행x4열 임시 격자로 위/아래 x 좌/우만 표시.
#
#    CNN이 특정 자세를 헷갈려할 때, 이 요약값을 보면 "오른쪽 엉덩이만
#    유독 압력이 높구나" 같은 걸 사람이 바로 눈으로 확인할 수 있음.
# =====================================================================
SEAT_ZONES = {
    "right_hip": slice(0, 5),
    "left_hip": slice(5, 10),
    "right_mid": slice(10, 17),
    "left_mid": slice(17, 24),
    "right_knee": slice(24, 28),
    "left_knee": slice(28, 32),
}


def summarize_regions(seat_values, back_values):
    seat = np.array(seat_values, dtype=np.float32)  # (32,) index 0~31 = seat_1~32

    seat_summary = {
        zone_name: float(seat[idx_slice].mean())
        for zone_name, idx_slice in SEAT_ZONES.items()
    }

    # 등받이: 실제 구역 정의 전까지 임시 8x4 격자 사분면으로만 표시
    back = np.array(back_values, dtype=np.float32).reshape(8, 4)
    top, bottom = back[:4], back[4:]
    back_summary = {
        "back_upper_left": float(top[:, :2].mean()),
        "back_upper_right": float(top[:, 2:].mean()),
        "back_lower_left": float(bottom[:, :2].mean()),
        "back_lower_right": float(bottom[:, 2:].mean()),
    }

    return {**seat_summary, **back_summary}


@app.post("/sensor-data")
def save_sensor_data(data: dict, db: Session = Depends(get_db)):
    global PERSONAL_MEAN, PERSONAL_STD

    # data는 {"seat_1": .., ..., "seat_32": .., "back_1": .., ..., "back_32": ..} 형태로 전송돼야 함
    values = [float(data.get(col, 0.0)) for col in SENSOR_COLS_ORDER]  # 64개
    raw_array = np.array(values, dtype=np.float32)

    # 캘리브레이션 진행 중이면 이 값도 같이 수집. 시간이 다 되면 자동으로
    # 개인별 mean/std를 계산해서 저장하고, 이후 정규화에 바로 반영함.
    was_active = calib_session.active
    calib_session.add_sample(values)
    if was_active and not calib_session.active:
        result = calib_session.compute_and_save(SENSOR_MEAN, SENSOR_STD)
        if result is not None:
            PERSONAL_MEAN = np.array(result["personal_mean"], dtype=np.float32)
            PERSONAL_STD = np.array(result["personal_std"], dtype=np.float32)
            print(f"✅ 개인 캘리브레이션 완료! (샘플 {result['num_samples']}개) 이제부터 개인 기준으로 정규화합니다.")
        else:
            print("⚠️ 캘리브레이션 샘플이 너무 적어(10개 미만) 개인 기준을 계산하지 못했습니다.")

    # 개인 캘리브레이션 결과가 있으면 그걸 우선 사용, 없으면 학습 데이터 전체 기준 사용
    use_mean = PERSONAL_MEAN if PERSONAL_MEAN is not None else SENSOR_MEAN
    use_std = PERSONAL_STD if PERSONAL_STD is not None else SENSOR_STD

    norm_array = (raw_array - use_mean) / (use_std + 1e-7)
    input_tensor = torch.tensor(norm_array).unsqueeze(0).unsqueeze(0).to(device)  # (1,1,64)

    with torch.no_grad():
        outputs = cnn_model(input_tensor)
        pred_idx = torch.argmax(outputs, dim=1).item()
        cnn_posture = LABEL_CLASSES[pred_idx] if pred_idx < len(LABEL_CLASSES) else "알 수 없음"

    seat_values = values[:32]
    back_values = values[32:]
    region_summary = summarize_regions(seat_values, back_values)
    cnn_posture_display = DISPLAY_NAMES.get(cnn_posture, cnn_posture)

    record_kwargs = {col: values[i] for i, col in enumerate(SENSOR_COLS_ORDER)}
    sensor_record = SensorData(
        **record_kwargs,
        posture=f"CNN: {cnn_posture}({cnn_posture_display})",
        timestamp=datetime.now(),
    )
    db.add(sensor_record)
    db.commit()

    app.state.latest_posture = {
        "cnn_posture": cnn_posture,
        "cnn_posture_display": cnn_posture_display,
        "sensors": values,
        "region_summary": region_summary,
    }

    return {
        "message": "저장 완료!",
        "cnn_posture": cnn_posture,
        "cnn_posture_display": cnn_posture_display,  # 임시 배정 표시용 이름 (실측 검증 전)
        "region_summary": region_summary,  # 진단용 참고값 (판정에는 안 씀)
        "used_personal_calibration": PERSONAL_MEAN is not None,
        "calibration_status": calib_session.status() if calib_session.active else None,
        "timestamp": str(sensor_record.timestamp),
    }


@app.get("/current-posture")
def get_current_posture():
    if hasattr(app.state, "latest_posture"):
        return app.state.latest_posture
    return {"cnn_posture": "데이터 없음", "cnn_posture_display": "데이터 없음", "sensors": [0.0] * 64}
