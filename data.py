import requests
import random
import time

SERVER_URL = "http://127.0.0.1:8000/sensor-data"

# [보존] 기존 다혜님의 4가지 메뉴 유형과 수치 범위 100% 완벽 유지
POSTURE_PATTERNS = {
    "바른자세": {
        "sensor_1": (380, 420), "sensor_2": (380, 420),
        "sensor_3": (350, 390), "sensor_4": (350, 390),
        "sensor_5": (300, 350), "sensor_6": (300, 350),
    },
    "거북목": {
        "sensor_1": (600, 700), "sensor_2": (600, 700),
        "sensor_3": (400, 500), "sensor_4": (400, 500),
        "sensor_5": (100, 200), "sensor_6": (100, 200),
    },
    "기대기": {
        "sensor_1": (100, 200), "sensor_2": (100, 200),
        "sensor_3": (300, 400), "sensor_4": (300, 400),
        "sensor_5": (600, 700), "sensor_6": (600, 700),
    },
    "다리꼬기": {
        "sensor_1": (200, 300), "sensor_2": (500, 600),
        "sensor_3": (200, 300), "sensor_4": (500, 600),
        "sensor_5": (200, 300), "sensor_6": (500, 600),
    }
}

def send_data(posture):
    pattern = POSTURE_PATTERNS[posture]
    
    # 무작위 값 생성
    s1 = random.randint(*pattern["sensor_1"])
    s2 = random.randint(*pattern["sensor_2"])
    s3 = random.randint(*pattern["sensor_3"])
    s4 = random.randint(*pattern["sensor_4"])
    s5 = random.randint(*pattern["sensor_5"])
    s6 = random.randint(*pattern["sensor_6"])

    # [통합 보완] 규칙 기반용 키와 딥러닝 데이터셋용 명칭 키를 모두 한 JSON 객체에 채워 송신
    data = {
        "sensor_1": s1, "sensor_2": s2, "sensor_3": s3,
        "sensor_4": s4, "sensor_5": s5, "sensor_6": s6,
        
        # 딥러닝 매핑 연동용 보조 키 탑재
        "F_Left": s1, "F_Right": s2,
        "B_Left": s3, "B_Right": s4,
        "BR_Left": s5, "BR_Right": s6
    }

    try:
        response = requests.post(SERVER_URL, json=data)
        if response.status_code == 200:
            res_json = response.json()
            print(f"✅ 전송 성공 | 규칙 결과: {res_json.get('rule_posture')} | CNN 결과: {res_json.get('cnn_posture')}")
        else:
            print(f"❌ 전송 실패: {response.status_code}")
    except Exception as e:
        print(f"❌ 서버 연결 오류: {e}")

def run_simulator():
    print("=" * 50)
    print("  통합형 하드웨어 가상 센서 시뮬레이터 시작!")
    print("=" * 50)
    print("자세를 선택하세요:")
    print("  1. 바른자세\n  2. 거북목\n  3. 기대기\n  4. 다리꼬기\n  5. 자동 변환 모드\n  q. 종료")
    print("=" * 50)

    postures = list(POSTURE_PATTERNS.keys())

    while True:
        choice = input("\n선택 (1~5, q): ").strip()
        if choice == "q":
            break
        elif choice in ["1", "2", "3", "4"]:
            posture = postures[int(choice) - 1]
            try:
                while True:
                    send_data(posture)
                    time.sleep(0.5)
            except KeyboardInterrupt:
                print("\n전송 중단. 메뉴로 돌아갑니다.")
        elif choice == "5":
            try:
                while True:
                    posture = random.choice(postures)
                    print(f"\n[자동] '{posture}' 상태 시뮬레이션 중...")
                    for _ in range(10):  # 한 자세당 5초간 유지하며 전송
                        send_data(posture)
                        time.sleep(0.5)
            except KeyboardInterrupt:
                print("\n자동 모드 중단.")

if __name__ == "__main__":
    run_simulator()
