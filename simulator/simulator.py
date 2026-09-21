import requests
import random
import time

# 서버 주소
SERVER_URL = "http://127.0.0.1:8000/sensor-data"

# 자세별 센서 패턴 정의
# 6개 센서 값 범위: 0~1023 (높을수록 압력 강함)
POSTURE_PATTERNS = {
    "바른자세": {
        "sensor_1": (380, 420),  # 앞 왼쪽
        "sensor_2": (380, 420),  # 앞 오른쪽
        "sensor_3": (350, 390),  # 중간 왼쪽
        "sensor_4": (350, 390),  # 중간 오른쪽
        "sensor_5": (300, 350),  # 뒤 왼쪽
        "sensor_6": (300, 350),  # 뒤 오른쪽
    },
    "거북목": {
        "sensor_1": (600, 700),  # 앞쪽 압력 매우 높음
        "sensor_2": (600, 700),
        "sensor_3": (400, 500),
        "sensor_4": (400, 500),
        "sensor_5": (100, 200),  # 뒤쪽 압력 낮음
        "sensor_6": (100, 200),
    },
    "기대기": {
        "sensor_1": (100, 200),  # 앞쪽 압력 낮음
        "sensor_2": (100, 200),
        "sensor_3": (300, 400),
        "sensor_4": (300, 400),
        "sensor_5": (600, 750),  # 뒤쪽 압력 매우 높음
        "sensor_6": (600, 750),
    },
    "다리꼬기": {
        "sensor_1": (200, 300),  # 왼쪽 압력 낮음
        "sensor_2": (550, 650),  # 오른쪽 압력 높음
        "sensor_3": (200, 300),
        "sensor_4": (550, 650),
        "sensor_5": (200, 300),
        "sensor_6": (550, 650),
    },
}

def generate_sensor_data(posture):
    """자세 패턴에 맞는 센서 데이터 생성"""
    pattern = POSTURE_PATTERNS[posture]
    data = {"posture": posture}
    for sensor, (min_val, max_val) in pattern.items():
        data[sensor] = round(random.uniform(min_val, max_val), 2)
    return data

def send_data(posture):
    """서버로 데이터 전송"""
    data = generate_sensor_data(posture)
    try:
        response = requests.post(SERVER_URL, json=data)
        if response.status_code == 200:
            print(f"✅ 전송 완료 | 자세: {posture} | 데이터: {data}")
        else:
            print(f"❌ 전송 실패: {response.status_code}")
    except Exception as e:
        print(f"❌ 서버 연결 오류: {e}")

def run_simulator():
    """시뮬레이터 실행"""
    print("=" * 50)
    print("  posture-ai 가상 센서 시뮬레이터 시작!")
    print("=" * 50)
    print("자세를 선택하세요:")
    print("  1. 바른자세")
    print("  2. 거북목")
    print("  3. 기대기")
    print("  4. 다리꼬기")
    print("  5. 자동 (랜덤으로 자세 변경)")
    print("  q. 종료")
    print("=" * 50)

    postures = list(POSTURE_PATTERNS.keys())

    while True:
        choice = input("\n선택 (1~5, q): ").strip()

        if choice == "q":
            print("시뮬레이터 종료!")
            break
        elif choice in ["1", "2", "3", "4"]:
            posture = postures[int(choice) - 1]
            print(f"\n'{posture}' 모드로 데이터 전송 시작! (멈추려면 Ctrl+C)")
            try:
                while True:
                    send_data(posture)
                    time.sleep(0.5)
            except KeyboardInterrupt:
                print(f"\n'{posture}' 전송 중단. 메뉴로 돌아갑니다.")
        elif choice == "5":
            print("\n자동 모드 시작! (멈추려면 Ctrl+C)")
            try:
                while True:
                    posture = random.choice(postures)
                    send_data(posture)
                    time.sleep(0.5)
            except KeyboardInterrupt:
                print("\n자동 모드 중단. 메뉴로 돌아갑니다.")
        else:
            print("1~5 또는 q를 입력해줘!")

if __name__ == "__main__":
    run_simulator()