#공공 데이터셋(Kaggle 등) 로드 및 결측치 처리.

#Z-Score 정규화: 실시간 데이터에 적용할 (x - mean) / std 수식 함수화 (이후 캘리브레이션의 기초).

import pandas as pd
import numpy as np

# 1. 데이터 로드 (컬럼명이 없으므로 header=None 설정)
df = pd.read_csv('ConfLongDemo_JSI.csv', header=None)

# 2. 6개 센서값 데이터만 추출 (4, 5, 6번 열이 수치 데이터입니다)
# 연습을 위해 숫자 데이터를 복사해서 6개 컬럼으로 만듭니다.
sensor_data = df.iloc[:, [4, 5, 6, 4, 5, 6]] 
sensor_data.columns = ['s1', 's2', 's3', 's4', 's5', 's6']

# 3. 결측치 처리 (PPT 계획 내용)
df_clean = sensor_data.fillna(sensor_data.mean())

# 4. Z-Score 정규화 함수화 (다혜님 파트의 꽃!)
def z_score_normalize(x):
    return (x - np.mean(x)) / (np.std(x) + 1e-7)

# 함수 적용
df_normalized = df_clean.apply(z_score_normalize)

print("--- 전처리 완료된 데이터 (상위 5개) ---")
print(df_normalized.head())

# 빈칸이 몇 개인지 확인
print(df.isnull().sum())


import pandas as pd
import numpy as np



# Z-Score 정규화 함수 정의
def z_score_normalize(x):
    # 사진에 나온 np.mean과 np.std를 쓰려면 위에서 import numpy as np를 해야 합니다.
    return (x - np.mean(x)) / (np.std(x) + 1e-7)

# 숫자 데이터가 있는 4, 5, 6번 열에 적용
# (df.iloc[:, 4:7]은 4, 5, 6번째 열을 의미해요)
df_normalized = df.iloc[:, 4:7].apply(z_score_normalize)

# 결과 확인
print("--- 정규화 완료 데이터 ---")
print(df_normalized.head())



#6개 센서값을 1차원 배열로 변환하는 Data Loader 작성.


# 1. 6개 센서 데이터 선택 (연습용으로 4, 5, 6번 열을 두 번 복사해서 6개로 만듭니다)
# 실전에서는 s1, s2, s3, s4, s5, s6 컬럼을 사용하게 됩니다.
sensor_6 = np.concatenate([df_normalized.values, df_normalized.values], axis=1)

# 2. 1D-CNN은 3차원 입력을 받습니다: (데이터 개수, 채널, 센서 개수)
# 우리 센서는 6개이므로 뒤쪽 숫자가 6이 되어야 합니다.
data_loader_final = sensor_6.reshape(-1, 1, 6)

print("--- Data Loader 작성 완료 ---")
print("최종 데이터 모양 (Shape):", data_loader_final.shape)
print("첫 번째 샘플 데이터:\n", data_loader_final[0])



import torch
import torch.nn as nn

class PostureCNN(nn.Module):
    def __init__(self):
        super(PostureCNN, self).__init__()
        # 1. Conv1D: 6개 센서의 특징 추출
        self.conv1 = nn.Conv1d(in_channels=1, out_channels=32, kernel_size=3, padding=1)
        # 2. MaxPool1D: 중요한 정보만 남기기
        self.pool = nn.MaxPool1d(kernel_size=2)
        # 3. Dense Layer (Fully Connected): 5종 자세로 분류
        self.fc1 = nn.Linear(32 * 3, 64) # (채널수 * 줄어든 데이터길이)
        self.fc2 = nn.Linear(64, 5)     # 최종 출력: 5 (자세 5종)

    def forward(self, x):
        x = torch.relu(self.conv1(x))
        x = self.pool(x)
        x = x.view(x.size(0), -1) # Flatten (평탄화)
        x = torch.relu(self.fc1(x))
        x = self.fc2(x)
        return x

model = PostureCNN()
print(model)


# 학습된 모델의 가중치 저장
torch.save(model.state_dict(), 'posture_model.pt')
print("가중치 파일 저장 완료! (.pt)")
