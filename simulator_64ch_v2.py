"""
simulator_64ch_v2.py

[v1과 다른 점]
v1은 채널 64개를 각각 독립적으로 정규분포(mean, std)에서 뽑았습니다.
이러면 채널별 평균/표준편차는 실제 데이터와 같아 보여도, 인접 칸끼리
값이 이어지는 실제 압력 데이터의 "공간적 상관관계"가 전혀 재현되지
않아서, 모델이 한 번도 본 적 없는 비현실적인 패턴이 만들어졌습니다.
(학습 정확도는 80%대인데 시뮬레이터 테스트는 거의 못 맞히는 원인이었음)

v2는 새로 값을 만들어내지 않고, chair_64ch_posture_data.csv에 있는
"실제로 관측된 행(row)"을 자세별로 그대로 무작위 추출해서 보냅니다.
-> 상관관계 구조가 100% 보존되므로, 시뮬레이터 결과가 학습 때 측정한
   정확도(80%대)에 가깝게 나와야 정상입니다.
"""

import random
import time

import pandas as pd
import requests

SERVER_URL = "http://127.0.0.1:8000/sensor-data"
DATA_PATH = "chair_64ch_posture_data.csv"

df = pd.read_csv(DATA_PATH)
SEAT_COLS = [f"seat_{i+1}" for i in range(32)]
BACK_COLS = [f"back_{i+1}" for i in range(32)]
ALL_COLS = SEAT_COLS + BACK_COLS

# 자세별로 실제 행들을 미리 나눠서 보관 (전송할 때마다 여기서 무작위로 뽑아 씀)
POSTURE_ROWS = {
    label: sub[ALL_COLS].to_dict("records")
    for label, sub in df.groupby("Label")
}
print("자세별 실제 샘플 개수:", {k: len(v) for k, v in POSTURE_ROWS.items()})


def generate_sensor_data(posture: str) -> dict:
    row = random.choice(POSTURE_ROWS[posture])  # 실제 관측된 행 그대로 사용
    data = dict(row)
    data["posture"] = posture
    return data


def send_data(posture: str):
    data = generate_sensor_data(posture)
    try:
        response = requests.post(SERVER_URL, json=data, timeout=5, proxies={"http": None, "https": None})
        if response.status_code == 200:
            res = response.json()
            match = "✅ 일치" if res.get("cnn_posture") == posture else "❓"
            display = res.get("cnn_posture_display", "")
            print(f"의도: {posture} | CNN: {res.get('cnn_posture')}({display}) {match}")
        else:
            print(f"❌ 전송 실패: {response.status_code}")
    except requests.exceptions.Timeout:
        print("❌ 타임아웃: 서버 응답이 없어요.")
    except requests.exceptions.ConnectionError as e:
        print(f"❌ 서버 연결 실패: {e}")
    except Exception as e:
        print(f"❌ 서버 연결 오류: {e}")


def send_data_verbose(posture: str):
    data = generate_sensor_data(posture)
    try:
        response = requests.post(SERVER_URL, json=data, timeout=5, proxies={"http": None, "https": None})
        if response.status_code != 200:
            print(f"❌ 전송 실패: {response.status_code}")
            return
        res = response.json()
        match = "✅ 일치" if res.get("cnn_posture") == posture else "❓"
        display = res.get("cnn_posture_display", "")
        print(f"의도: {posture} | CNN: {res.get('cnn_posture')}({display}) {match}")
        rs = res.get("region_summary", {})
        if rs:
            print(
                f"  방석  우엉덩={rs['right_hip']:6.1f} 좌엉덩={rs['left_hip']:6.1f} "
                f"우허벅={rs['right_mid']:6.1f} 좌허벅={rs['left_mid']:6.1f} "
                f"우무릎={rs['right_knee']:6.1f} 좌무릎={rs['left_knee']:6.1f}"
            )
            print(
                f"  등받이(임시격자) 상L={rs['back_upper_left']:6.1f} 상R={rs['back_upper_right']:6.1f} "
                f"하L={rs['back_lower_left']:6.1f} 하R={rs['back_lower_right']:6.1f}"
            )
    except requests.exceptions.Timeout:
        print("❌ 타임아웃: 서버 응답이 없어요.")
    except requests.exceptions.ConnectionError as e:
        print(f"❌ 서버 연결 실패: {e}")
    except Exception as e:
        print(f"❌ 서버 연결 오류: {e}")


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


def run_simulator():
    postures = list(POSTURE_ROWS.keys())
    verbose = False

    print("=" * 60)
    print("  64채널 자세 시뮬레이터 v2 (실측 행 그대로 재생)")
    print("=" * 60)
    for i, p in enumerate(postures, 1):
        name = DISPLAY_NAMES.get(p, p)
        print(f"  {i}. {p} - {name}")
    print("  v. 상세보기 켜기/끄기")
    print("  q. 종료")
    print("=" * 60)

    while True:
        mode = "상세보기 ON" if verbose else "상세보기 OFF"
        choice = input(f"\n[{mode}] 선택 (1~{len(postures)}, v, q): ").strip()
        if choice == "q":
            print("시뮬레이터 종료!")
            break
        elif choice.lower() == "v":
            verbose = not verbose
            print(f"-> 상세보기 {'켜짐' if verbose else '꺼짐'}")
            continue
        elif choice.isdigit() and 1 <= int(choice) <= len(postures):
            posture = postures[int(choice) - 1]
            sender = send_data_verbose if verbose else send_data
            print(f"\n'{posture}({DISPLAY_NAMES.get(posture, posture)})' 모드로 데이터 전송 시작! (멈추려면 Ctrl+C)")
            try:
                while True:
                    sender(posture)
                    time.sleep(0.5)
            except KeyboardInterrupt:
                print(f"\n'{posture}' 전송 중단. 메뉴로 돌아갑니다.")
        else:
            print(f"1~{len(postures)}, v, 또는 q를 입력해줘!")


if __name__ == "__main__":
    run_simulator()
