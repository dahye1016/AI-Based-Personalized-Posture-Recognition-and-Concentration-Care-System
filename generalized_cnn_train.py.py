import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder
import torch
import torch.nn as nn
import torch.optim as optim

# 1. 모델 클래스 정의
class PostureCNN(nn.Module):
    def __init__(self, num_classes):
        super(PostureCNN, self).__init__()
        self.conv1 = nn.Conv1d(1, 32, kernel_size=3, stride=1, padding=1)
        self.pool = nn.MaxPool1d(kernel_size=2, stride=2)
        
        self.fc1 = None 
        self.fc2 = nn.Linear(64, num_classes) # 데이터에서 자동으로 계산된 클래스 개수 적용

    def forward(self, x):
        x = self.pool(torch.relu(self.conv1(x)))
        x = x.view(x.size(0), -1)  
        
        if self.fc1 is None:
            flatten_dim = x.size(1) 
            self.fc1 = nn.Linear(flatten_dim, 64).to(x.device)
            
        x = torch.relu(self.fc1(x))
        x = self.fc2(x)
        return x

# 2. 데이터 불러오기 및 철저한 전처리
file_path = r'C:/Users/jungd/OneDrive/바탕 화면/user1.features_labels.csv'
df = pd.read_csv(file_path)

# 2-1. 첫 번째 열(timestamp) 제거 (학습에 필요 없음)
if 'timestamp' in df.columns:
    df = df.drop(columns=['timestamp'])

# 2-2. 결측치(NaN) 처리 -> 빈 칸은 해당 컬럼의 평균값으로 채우고, 남은 빈칸은 0으로 채움
df = df.fillna(df.mean(numeric_only=True))
df = df.fillna(0)

# 2-3. X(특징)와 y(라벨) 분리
X = df.iloc[:, :-1].values # 센서 특징 값들
y_raw = df.iloc[:, -1].values # 원래 라벨 (문자열 또는 섞인 형태)

# 2-4. 문자로 된 자세 라벨을 컴퓨터가 인식하는 숫자(0부터 시작)로 인코딩
le = LabelEncoder()
y = le.fit_transform(y_raw.astype(str)) # 무조건 문자열 변환 후 변환
num_classes = len(le.classes_)

print("--- 데이터 분석 결과 ---")
print(f"총 데이터 개수: {len(X)}개")
print(f"입력 특징(Feature) 개수: {X.shape[1]}개")
print(f"분류할 자세(Class) 종류 [{num_classes}종]: {le.classes_}")
print("------------------------\n")

# 3. 학습용/테스트용 데이터 분리
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

# 4. 모델, 손실함수, 최적화 설정
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
model = PostureCNN(num_classes=num_classes).to(device)
criterion = nn.CrossEntropyLoss()
optimizer = optim.Adam(model.parameters(), lr=0.001)

# 5. 데이터 텐서 변환 및 형태 조정
inputs = torch.tensor(X_train).float().unsqueeze(1).to(device)
labels = torch.tensor(y_train).long().to(device)

# 6. 학습 시작
print("학습을 시작합니다...")
model.train()

for epoch in range(10):
    optimizer.zero_grad()
    
    outputs = model(inputs)
    loss = criterion(outputs, labels) 
    
    loss.backward()
    optimizer.step()

    print(f"Epoch {epoch+1:02d}/10, Loss: {loss.item():.4f}")

print("\n🎉 학습 완료!")
