import pandas as pd
import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder

# =====================================================================
# [다혜님 기존 12.py 구조 100% 계승] 1. 1D-CNN 모델 정의 부분
# =====================================================================
class PostureCNN(nn.Module):
    def __init__(self):
        super(PostureCNN, self).__init__()
        # 1D-CNN 특징 추출 (입력 채널 1, 출력 채널 32)
        self.conv1 = nn.Conv1d(in_channels=1, out_channels=32, kernel_size=3, padding=1)
        self.pool = nn.MaxPool1d(kernel_size=2)
        
        # 💡 [차원 맞춤 계산] 6개 센서 특징이 Pool(kernel_size=2)을 거치면 3개로 줄어듭니다.
        # 출력 채널 32 * 줄어든 특징 3 = 총 96개의 차원이 Flatten 됩니다.
        # 기존 12.py의 흐름과 주석 의도를 완벽하게 반영하여 96으로 설정했습니다!
        self.fc1 = nn.Linear(96, 64) 
        self.fc2 = nn.Linear(64, 7)  # p0부터 p6까지 총 7가지 자세 분류

    def forward(self, x):
        x = torch.relu(self.conv1(x))
        x = self.pool(x)
        x = x.view(x.size(0), -1)    # 다혜님 기존 코드의 Flatten 방식 유지
        x = torch.relu(self.fc1(x))
        x = self.fc2(x)
        return x

# =====================================================================
# [다혜님 기존 Z-score.py 구조 100% 계승] 2. 데이터 로드 및 Z-Score 정규화
# =====================================================================
# 1. 생성된 가상 데이터셋 파일 불러오기
file_path = 'chair_7_postures_data.csv'
df = pd.read_csv(file_path)

# 2. X(센서 특징 6개)와 y(자세 정답 라벨) 분리
df_X = df.iloc[:, :-1]        # F_Left, F_Right, B_Left, B_Right, BR_Left, BR_Right
y_raw = df.iloc[:, -1].values  # 'p1_정자세' 같은 문자열 라벨

# ⭐ [다혜님 코드 핵심 함수] 열별로 평균과 표준편차를 구해 Z-Score(Z값) 계산
def z_score_normalize(x):
    return (x - np.mean(x)) / (np.std(x) + 1e-7)

# 기존 .apply() 방식 그대로 Z값을 연산합니다.
df_normalized = df_X.apply(z_score_normalize)
X = df_normalized.values      # 정규화 완료된 Z값 데이터 배열화

# 문자열 자세 이름을 PyTorch가 인덱스로 인식할 수 있게 숫자(0~6)로 안전하게 변환
le = LabelEncoder()
y = le.fit_transform(y_raw)

print("=" * 50)
print("--- [Z-Score 완료] 가상 데이터 전처리 결과 확인 ---")
print(df_normalized.head())
print(f"\n최종 분류할 자세 종류 (총 {len(le.classes_)}종): {list(le.classes_)}")
print("=" * 50 + "\n")

# =====================================================================
# 3. 학습 데이터 분리 및 PyTorch 1D-CNN 학습 루프
# =====================================================================
# 학습용과 테스트용 데이터 분리 (8:2 비율)
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

# 모델, 손실함수, 최적화(Adam) 설정
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
model = PostureCNN().to(device)
criterion = nn.CrossEntropyLoss()
optimizer = optim.Adam(model.parameters(), lr=0.001)

# PyTorch 1D-CNN 입력 형태로 차원 생성 (Batch, Channel=1, Features=6)
inputs = torch.tensor(X_train).float().unsqueeze(1).to(device)
labels = torch.tensor(y_train).long().to(device)

# 학습 시작
print("가상 데이터셋으로 1D-CNN 모델 학습을 시작합니다...")
model.train()

for epoch in range(10):
    optimizer.zero_grad()
    
    outputs = model(inputs)
    loss = criterion(outputs, labels) # 차원과 라벨 맵핑이 완벽하여 에러가 나지 않습니다.
    
    loss.backward()
    optimizer.step()

    print(f"Epoch {epoch+1:02d}/10, Loss: {loss.item():.4f}")

print("\n🎉 7가지 자세 가상 데이터셋 기반 학습이 오류 없이 완벽하게 끝났습니다!")
