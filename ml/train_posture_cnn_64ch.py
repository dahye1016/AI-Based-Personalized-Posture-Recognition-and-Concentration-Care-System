"""
train_posture_cnn_64ch.py

extract_64ch_dataset.py로 만든 chair_64ch_posture_data.csv
(방석 32채널 + 등받이 32채널 = 64채널, 8종 자세 p1~p8)로
1D-CNN을 학습합니다.

train_posture_cnn.py(6채널 버전)와 구조는 동일하고, 입력 차원만
64로 바뀌었습니다 (fc1 입력 크기: 96 -> 1024).
"""

import json
import numpy as np
import pandas as pd
import torch
import torch.nn as nn
import torch.optim as optim
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder


# =====================================================================
# 1. 1D-CNN 모델 정의
# =====================================================================
class PostureCNN64(nn.Module):
    def __init__(self, num_classes: int):
        super(PostureCNN64, self).__init__()
        self.conv1 = nn.Conv1d(in_channels=1, out_channels=32, kernel_size=3, padding=1)
        self.pool = nn.MaxPool1d(kernel_size=2)
        # 64채널 -> Pool(kernel=2) 통과 후 32개로 줄어듦 -> 32채널 * 32 = 1024
        self.fc1 = nn.Linear(1024, 128)
        self.fc2 = nn.Linear(128, num_classes)

    def forward(self, x):
        x = torch.relu(self.conv1(x))
        x = self.pool(x)
        x = x.view(x.size(0), -1)
        x = torch.relu(self.fc1(x))
        x = self.fc2(x)
        return x


# =====================================================================
# 2. 데이터 로드 및 Z-Score 정규화
# =====================================================================
DATA_PATH = "chair_64ch_posture_data.csv"

df = pd.read_csv(DATA_PATH)

SEAT_COLS = [f"seat_{i+1}" for i in range(32)]
BACK_COLS = [f"back_{i+1}" for i in range(32)]
SENSOR_COLS = SEAT_COLS + BACK_COLS  # 순서 고정: 방석 32개 -> 등받이 32개

df_X = df[SENSOR_COLS]
y_raw = df["Label"].values

sensor_mean = df_X.mean().values  # (64,)
sensor_std = df_X.std().values    # (64,)


def z_score_normalize(x, mean, std):
    return (x - mean) / (std + 1e-7)


X = z_score_normalize(df_X.values, sensor_mean, sensor_std)

le = LabelEncoder()
y = le.fit_transform(y_raw)
num_classes = len(le.classes_)

print("=" * 60)
print(f"총 데이터 개수: {len(X)}개, 입력 채널: {len(SENSOR_COLS)}개")
print(f"분류할 자세 종류 ({num_classes}종): {list(le.classes_)}")
print("=" * 60)

# =====================================================================
# 3. 학습/테스트 분리
# =====================================================================
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42, stratify=y
)

device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
model = PostureCNN64(num_classes=num_classes).to(device)
criterion = nn.CrossEntropyLoss()
optimizer = optim.Adam(model.parameters(), lr=0.001)

train_inputs = torch.tensor(X_train).float().unsqueeze(1).to(device)  # (N, 1, 64)
train_labels = torch.tensor(y_train).long().to(device)
test_inputs = torch.tensor(X_test).float().unsqueeze(1).to(device)
test_labels = torch.tensor(y_test).long().to(device)

# =====================================================================
# 4. 학습 루프 (미니배치)
# =====================================================================
EPOCHS = 30
BATCH_SIZE = 64
n_samples = train_inputs.size(0)

print("\n학습을 시작합니다...")
model.train()
for epoch in range(EPOCHS):
    perm = torch.randperm(n_samples)
    epoch_loss = 0.0
    for i in range(0, n_samples, BATCH_SIZE):
        idx = perm[i:i + BATCH_SIZE]
        batch_x = train_inputs[idx]
        batch_y = train_labels[idx]

        optimizer.zero_grad()
        outputs = model(batch_x)
        loss = criterion(outputs, batch_y)
        loss.backward()
        optimizer.step()
        epoch_loss += loss.item() * batch_x.size(0)

    if (epoch + 1) % 5 == 0 or epoch == 0:
        print(f"Epoch {epoch+1:02d}/{EPOCHS}, Loss: {epoch_loss / n_samples:.4f}")

# =====================================================================
# 5. 테스트셋 정확도 평가
# =====================================================================
model.eval()
with torch.no_grad():
    test_outputs = model(test_inputs)
    preds = torch.argmax(test_outputs, dim=1)
    accuracy = (preds == test_labels).float().mean().item()

print("\n" + "=" * 60)
print(f"🎯 테스트셋 정확도: {accuracy * 100:.2f}%")
print("=" * 60)

if accuracy < 0.85:
    print("⚠️  목표 정확도(85%) 미달입니다. 데이터 품질/에폭/모델 구조를 점검하세요.")

# =====================================================================
# 6. 가중치 + 정규화 통계 + 라벨 순서 저장
# =====================================================================
torch.save(model.state_dict(), "posture_model_64ch.pt")
print("\n✅ posture_model_64ch.pt 저장 완료")

norm_stats = {
    "seat_cols_order": SEAT_COLS,
    "back_cols_order": BACK_COLS,
    "sensor_cols_order": SENSOR_COLS,  # seat_1~32 -> back_1~32 순서
    "mean": sensor_mean.tolist(),
    "std": sensor_std.tolist(),
    "label_classes": list(le.classes_),
    "num_classes": num_classes,
    "test_accuracy": accuracy,
}
with open("norm_stats_64ch.json", "w", encoding="utf-8") as f:
    json.dump(norm_stats, f, ensure_ascii=False, indent=2)
print("✅ norm_stats_64ch.json 저장 완료")
