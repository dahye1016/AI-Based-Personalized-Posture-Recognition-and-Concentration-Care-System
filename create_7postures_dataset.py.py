import numpy as np
import pandas as pd

# 1. 설정값 정의 (자세당 500개씩 총 3,500줄 데이터 생성)
num_samples_per_posture = 500  
np.random.seed(42)  

data_list = []

# 2. 논문 기반 7가지 자세별 압력 규칙 생성 (0 ~ 1023 범위)
for i in range(num_samples_per_posture):
    
    # --- [p0: 앉지 않음] 모든 센서 값이 거의 0에 수렴 ---
    data_list.append([
        np.random.normal(5, 3), np.random.normal(5, 3),     # F_Left, F_Right
        np.random.normal(5, 3), np.random.normal(5, 3),     # B_Left, B_Right
        np.random.normal(2, 1), np.random.normal(2, 1),     # BR_Left, BR_Right
        "p0_앉지않음"
    ])

    # --- [p1: 정자세] 방석과 등받이에 압력이 고르게 분포 ---
    data_list.append([
        np.random.normal(700, 50), np.random.normal(700, 50),
        np.random.normal(650, 50), np.random.normal(650, 50),
        np.random.normal(500, 40), np.random.normal(500, 40),
        "p1_정자세"
    ])

    # --- [p2: 앞으로 숙이기 / 거북목] 체중이 앞으로 쏠려 등받이는 0에 가깝고 앞쪽 대폭 상승 ---
    data_list.append([
        np.random.normal(850, 40), np.random.normal(850, 40),
        np.random.normal(400, 50), np.random.normal(400, 50),
        np.random.normal(15, 5),   np.random.normal(15, 5),
        "p2_앞으로숙이기"
    ])

    # --- [p3: 오른다리 꼬기] 오른쪽 엉덩이에 압력이 심하게 집중 ---
    data_list.append([
        np.random.normal(350, 50), np.random.normal(900, 40),  # 오른쪽 방석 상승
        np.random.normal(300, 50), np.random.normal(850, 40),  # 오른쪽 방석 상승
        np.random.normal(450, 40), np.random.normal(450, 40),
        "p3_오른다리꼬기"
    ])

    # --- [p4: 왼다리 꼬기] 왼쪽 엉덩이에 압력이 심하게 집중 ---
    data_list.append([
        np.random.normal(900, 40), np.random.normal(350, 50),  # 왼쪽 방석 상승
        np.random.normal(850, 40), np.random.normal(300, 50),  # 왼쪽 방석 상승
        np.random.normal(450, 40), np.random.normal(450, 40),
        "p4_왼다리꼬기"
    ])

    # --- [p5: 오른쪽 기대기] 엉덩이 우측과 등받이 우측으로 압력 쏠림 ---
    data_list.append([
        np.random.normal(500, 50), np.random.normal(750, 50),
        np.random.normal(450, 50), np.random.normal(700, 50),
        np.random.normal(200, 30), np.random.normal(650, 40),  # 등받이 오른쪽 상승
        "p5_오른쪽기대기"
    ])

    # --- [p6: 왼쪽 기대기] 엉덩이 좌측과 등받이 좌측으로 압력 쏠림 ---
    data_list.append([
        np.random.normal(750, 50), np.random.normal(500, 50),
        np.random.normal(700, 50), np.random.normal(450, 50),
        np.random.normal(650, 40), np.random.normal(200, 30),  # 등받이 왼쪽 상승
        "p6_왼쪽기대기"
    ])

# 3. 데이터프레임 변환 및 클리핑 (0~1023 정수 범위 고정)
columns = ['F_Left', 'F_Right', 'B_Left', 'B_Right', 'BR_Left', 'BR_Right', 'Label']
df = pd.DataFrame(data_list, columns=columns)
numeric_cols = columns[:-1]
df[numeric_cols] = df[numeric_cols].clip(0, 1023).astype(int)

# 4. CSV 파일로 저장
df.to_csv('chair_7_postures_data.csv', index=False, encoding='utf-8-sig')
print("논문 기반 7가지 자세 가상 데이터셋 생성 완료!")
