"""
data_collector.py

실측 센서로 학습 데이터를 모을 때 쓰는 "녹화 모드" 로직입니다.
계획서의 "라벨 지정 -> N초 녹화 -> CSV 저장" 워크플로우를 구현합니다.

동작 방식:
1. /record/start 에 {"label": "정자세", "duration_sec": 30} 를 보내면 녹화 시작
2. 그 동안 평소처럼 /sensor-data 로 센서값이 계속 들어오면, 서버가
   그 값들을 "label=정자세"로 태그해서 함께 수집함
3. duration_sec가 지나면 자동 종료되고, 수집된 행들을 즉시
   collected_real_data.csv 파일 끝에 추가(append)함
   (파일이 없으면 새로 만듦, 있으면 이어서 씀 -> 자세별로 여러 번
   반복해도 계속 쌓임)
4. 다음 자세로 넘어갈 땐 label만 바꿔서 /record/start를 다시 호출

calibration.py의 CalibrationSession과 구조가 거의 동일합니다
(같은 패턴을 재사용해 유지보수 부담을 줄임).
"""

import csv
import os
import time

OUTPUT_PATH = "collected_real_data.csv"

SEAT_COLS = [f"seat_{i+1}" for i in range(32)]
BACK_COLS = [f"back_{i+1}" for i in range(32)]
ALL_COLS = SEAT_COLS + BACK_COLS


class RecordingSession:
    def __init__(self):
        self.active = False
        self.label = None
        self.start_time = None
        self.duration_sec = 30
        self.samples = []  # 각 원소: 64개짜리 raw 값 리스트

    def start(self, label: str, duration_sec: int = 30):
        self.active = True
        self.label = label
        self.start_time = time.time()
        self.duration_sec = duration_sec
        self.samples = []

    def cancel(self):
        self.active = False
        self.samples = []
        self.label = None

    def add_sample(self, values: list):
        """활성 상태일 때만 샘플을 추가하고, 시간이 다 되면 자동 종료 + 저장."""
        if not self.active:
            return
        self.samples.append(values)
        if time.time() - self.start_time >= self.duration_sec:
            self.active = False
            self._save_to_csv()

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
            "label": self.label,
            "collected_samples": len(self.samples),
            "elapsed_seconds": round(self.elapsed_seconds(), 1) if self.start_time else 0.0,
            "remaining_seconds": round(self.remaining_seconds(), 1),
            "duration_sec": self.duration_sec,
            "output_file": OUTPUT_PATH,
        }

    def stop_and_save(self) -> int:
        """duration_sec가 되기 전에 수동으로 중단하고 그때까지 모은 걸 저장."""
        self.active = False
        return self._save_to_csv()

    def _save_to_csv(self) -> int:
        """지금까지 모은 샘플을 CSV 끝에 이어붙여서 저장. 저장한 행 수 반환."""
        if not self.samples:
            return 0

        file_exists = os.path.isfile(OUTPUT_PATH)
        with open(OUTPUT_PATH, "a", newline="", encoding="utf-8-sig") as f:
            writer = csv.writer(f)
            if not file_exists:
                writer.writerow(ALL_COLS + ["Label"])
            for row in self.samples:
                writer.writerow(list(row) + [self.label])

        n = len(self.samples)
        self.samples = []
        return n
