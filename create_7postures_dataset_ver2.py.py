import numpy as np
import pandas as pd

num_samples_per_posture = 500  
np.random.seed(42)  
data_list = []

for i in range(num_samples_per_posture):
    # p0: 앉지 않음
    data_list.append([np.random.normal(5, 3), np.random.normal(5, 3), np.random.normal(5, 3), np.random.normal(5, 3), np.random.normal(2, 1), np.random.normal(2, 1), "p0_앉지않음"])
    # p1: 정자세
    data_list.append([np.random.normal(700, 50), np.random.normal(700, 50), np.random.normal(650, 50), np.random.normal(650, 50), np.random.normal(500, 40), np.random.normal(500, 40), "p1_정자세"])
    # p2: 앞으로 숙이기 (거북목)
    data_list.append([np.random.normal(850, 40), np.random.normal(850, 40), np.random.normal(400, 50), np.random.normal(400, 50), np.random.normal(15, 5), np.random.normal(15, 5), "p2_앞으로숙이기"])
    # p3: 오른다리 꼬기
    data_list.append([np.random.normal(350, 50), np.random.normal(900, 40), np.random.normal(300, 50), np.random.normal(850, 40), np.random.normal(450, 40), np.random.normal(450, 40), "p3_오른다리꼬기"])
    # p4: 왼다리 꼬기
    data_list.append([np.random.normal(900, 40), np.random.normal(350, 50), np.random.normal(850, 40), np.random.normal(300, 50), np.random.normal(450, 40), np.random.normal(450, 40), "p4_왼다리꼬기"])
    # p5: 오른쪽 기대기
    data_list.append([np.random.normal(500, 50), np.random.normal(750, 50), np.random.normal(450, 50), np.random.normal(700, 50), np.random.normal(200, 30), np.random.normal(650, 40), "p5_오른쪽기대기"])
    # p6: 왼쪽 기대기
    data_list.append([np.random.normal(750, 50), np.random.normal(500, 50), np.random.normal(700, 50), np.random.normal(450, 50), np.random.normal(650, 40), np.random.normal(200, 30), "p6_왼쪽기대기"])

columns = ['F_Left', 'F_Right', 'B_Left', 'B_Right', 'BR_Left', 'BR_Right', 'Label']
df = pd.DataFrame(data_list, columns=columns)
df[columns[:-1]] = df[columns[:-1]].clip(0, 1023).astype(int)
df.to_csv('chair_7_postures_data.csv', index=False, encoding='utf-8-sig')
print("7가지 자세 가상 데이터셋 생성 완료!")
