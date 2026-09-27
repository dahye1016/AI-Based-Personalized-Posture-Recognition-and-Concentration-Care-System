"""
calibration.py

수행계획서에 있던 "착석 초기 2분간 데이터를 학습해 개인별 압력 분포
평균/표준편차를 산출하고, 개인화된 정자세 임계치를 설정"하는 기능을
구현한 모듈입니다.

동작 방식:
1. 사용자가 새로 앉으면 /calibration/start 호출 (기본 120초)
2. 그 사이 평소처럼 /sensor-data로 센서값을 계속 보내면, 서버가
   내부적으로 그 값들을 캘리브레이션 샘플로 같이 수집함
3. 설정 시간이 지나면 자동으로 종료되고, 수집된 값들의 채널별
   평균/표준편차를 계산해서 personal_stats.json에 저장
4. 그 이후부터는 정규화(Z-Score)에 "학습 데이터 전체 평균" 대신
   "이 사람의 평균"을 사용 -> 개인별 체형/앉는 습관 차이를 보정

한 번에 한 명만 앉는 개인용 의자를 가정하고, 세션을 하나만 유지합니다
(여러 사용자를 동시에 구분해야 하면 세션을 dict로 확장하면 됩니다).
"""

import json
import time

import numpy as np

PERSONAL_STATS_PATH = "personal_stats.json"

# 표준편차가 너무 작으면(예: 짧은 시간 거의 안 움직인 경우) 정규화가
# 불안정해지므로, 학습 데이터 기준 표준편차보다 너무 작아지지 않게
# 하한선을 둡니다.
MIN_STD_RATIO = 0.3  # 개인 std가 전역 std의 30% 밑으로는 안 내려가게 함


class CalibrationSession:
    def __init__(self):
        self.active = False
        self.start_time = None
        self.duration_sec = 120
        self.samples = []  # 각 원소: 64개짜리 raw 값 리스트

    def start(self, duration_sec: int = 120):
        self.active = True
        self.start_time = time.time()
        self.duration_sec = duration_sec
        self.samples = []

    def cancel(self):
        self.active = False
        self.samples = []

    def add_sample(self, values: list):
        """활성 상태일 때만 샘플을 추가하고, 시간이 다 되면 자동 종료."""
        if not self.active:
            return
        self.samples.append(values)
        if time.time() - self.start_time >= self.duration_sec:
            self.active = False

    def elapsed_seconds(self) -> float:
        if self.start_time is None:
            return 0.0
        return time.time() - self.start_time

    def remaining_seconds(self) -> float:
        if not self.active:
            return 0.0
        return max(0.0, self.duration_sec - self.elapsed_seconds())

    def status(self) -> dict:
        return {
            "active": self.active,
            "collected_samples": len(self.samples),
            "elapsed_seconds": round(self.elapsed_seconds(), 1) if self.start_time else 0.0,
            "remaining_seconds": round(self.remaining_seconds(), 1),
            "duration_sec": self.duration_sec,
        }

    def compute_and_save(self, global_mean: np.ndarray, global_std: np.ndarray) -> dict | None:
        """수집된 샘플로 개인별 mean/std를 계산해서 파일로 저장.
        샘플이 너무 적으면(10개 미만) 신뢰할 수 없으므로 None 반환."""
        if len(self.samples) < 10:
            return None

        arr = np.array(self.samples, dtype=np.float32)  # (N, 64)
        personal_mean = arr.mean(axis=0)
        personal_std = arr.std(axis=0)

        # std 하한선 적용 (전역 std 대비 너무 작아지는 채널 보정)
        floor = global_std * MIN_STD_RATIO
        personal_std = np.maximum(personal_std, floor)

        result = {
            "personal_mean": personal_mean.tolist(),
            "personal_std": personal_std.tolist(),
            "num_samples": len(self.samples),
            "calibrated_at": time.strftime("%Y-%m-%d %H:%M:%S"),
        }
        with open(PERSONAL_STATS_PATH, "w", encoding="utf-8") as f:
            json.dump(result, f, ensure_ascii=False, indent=2)
        return result


def load_personal_stats():
    """서버 시작 시, 이전에 저장된 개인 캘리브레이션 결과가 있으면 불러옴."""
    try:
        with open(PERSONAL_STATS_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
        mean = np.array(data["personal_mean"], dtype=np.float32)
        std = np.array(data["personal_std"], dtype=np.float32)
        return mean, std, data
    except FileNotFoundError:
        return None, None, None
