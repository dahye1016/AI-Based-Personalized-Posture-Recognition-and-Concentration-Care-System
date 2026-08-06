"""
simulator_64ch.py

방석32+등받이32 = 64채널 자세 시뮬레이터.
같은 폴더의 posture_stats_64ch.json(실측 데이터에서 뽑은 자세별 평균/표준편차)을
읽어서, 실제 데이터 분포와 비슷한 가짜 값을 만들어 서버로 전송합니다.
(chair_7_postures_data.csv 때처럼 사람이 임의로 지어낸 숫자가 아니라,
 실제 압력 데이터 p1~p8에서 계산된 통계를 그대로 씁니다.)
"""

import json
import random
import time

import requests

SERVER_URL = "http://127.0.0.1:8000/sensor-data"

with open("posture_stats_64ch.json", "r", encoding="utf-8") as f:
    POSTURE_STATS = json.load(f)  # {"p1": {"mean": [...64개...], "std": [...64개...]}, ...}

SEAT_COLS = [f"seat_{i+1}" for i in range(32)]
BACK_COLS = [f"back_{i+1}" for i in range(32)]
ALL_COLS = SEAT_COLS + BACK_COLS  # 순서 고정: mean/std 배열 순서와 동일


def generate_sensor_data(posture: str) -> dict:
    stats = POSTURE_STATS[posture]
    mean = stats["mean"]
    std = stats["std"]

    data = {"posture": posture}
    for i, col in enumerate(ALL_COLS):
        m, s = mean[i], max(std[i], 0.5)
        val = max(0.0, random.gauss(m, s))  # 압력은 음수가 될 수 없으므로 0 이상으로 클리핑
        data[col] = round(val, 2)
    return data


def send_data(posture: str):
    data = generate_sensor_data(posture)
    try:
        response = requests.post(SERVER_URL, json=data)
        if response.status_code == 200:
            res = response.json()
            match = "✅ 일치" if res.get("cnn_posture") == posture else "❓"
            print(f"의도: {posture} | CNN: {res.get('cnn_posture')} {match}")
        else:
            print(f"❌ 전송 실패: {response.status_code}")
    except Exception as e:
        print(f"❌ 서버 연결 오류: {e}")


def run_simulator():
    postures = list(POSTURE_STATS.keys())

    print("=" * 60)
    print("  64채널(방석32+등받이32) 자세 시뮬레이터 (실측 통계 기반)")
    print("=" * 60)
    for i, p in enumerate(postures, 1):
        print(f"  {i}. {p}")
    print(f"  {len(postures)+1}. 자동 (랜덤으로 자세 변경)")
    print("  q. 종료")
    print("=" * 60)

    while True:
        choice = input(f"\n선택 (1~{len(postures)+1}, q): ").strip()
        if choice == "q":
            print("시뮬레이터 종료!")
            break
        elif choice.isdigit() and 1 <= int(choice) <= len(postures):
            posture = postures[int(choice) - 1]
            print(f"\n'{posture}' 모드로 데이터 전송 시작! (멈추려면 Ctrl+C)")
            try:
                while True:
                    send_data(posture)
                    time.sleep(0.5)
            except KeyboardInterrupt:
                print(f"\n'{posture}' 전송 중단. 메뉴로 돌아갑니다.")
        elif choice == str(len(postures) + 1):
            print("\n자동 모드 시작! (멈추려면 Ctrl+C)")
            try:
                while True:
                    posture = random.choice(postures)
                    send_data(posture)
                    time.sleep(0.5)
            except KeyboardInterrupt:
                print("\n자동 모드 중단. 메뉴로 돌아갑니다.")
        else:
            print(f"1~{len(postures)+1} 또는 q를 입력해줘!")


if __name__ == "__main__":
    run_simulator()
