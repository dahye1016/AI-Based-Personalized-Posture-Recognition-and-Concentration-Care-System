"""
convert_to_tflite.py

posture_model_64ch.pt (PyTorch)를 모바일 앱에서 쓸 수 있는 TFLite로
변환하고, 변환 전/후 모델의 테스트셋 정확도를 비교해서 변환 과정에서
성능이 깨지지 않았는지 검증합니다.

변환 경로: PyTorch -> ONNX -> TensorFlow SavedModel -> TFLite
(PyTorch는 TFLite로 바로 내보내는 기능이 없어서, 이 경로가 표준입니다.)

필요 패키지 (기존 패키지에 추가로 설치):
    pip install onnx onnxscript onnx2tf tensorflow

실행 전 준비물 (같은 폴더에 있어야 함):
    - posture_model_64ch.pt   (train_posture_cnn_64ch.py 실행 결과물)
    - norm_stats_64ch.json    (〃)
    - chair_64ch_posture_data.csv  (테스트셋 재현용 - 학습 때와 동일한
      random_state=42, test_size=0.2로 나눠야 같은 테스트 데이터가 나옴)

실행:
    python convert_to_tflite.py
"""

import json
import numpy as np
import pandas as pd
import torch
import torch.nn as nn
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder


# =====================================================================
# 1. 모델 구조 (train_posture_cnn_64ch.py와 완전히 동일해야 함)
# =====================================================================
class PostureCNN64(nn.Module):
    def __init__(self, num_classes: int):
        super(PostureCNN64, self).__init__()
        self.conv1 = nn.Conv1d(in_channels=1, out_channels=32, kernel_size=3, padding=1)
        self.pool = nn.MaxPool1d(kernel_size=2)
        self.fc1 = nn.Linear(1024, 128)
        self.fc2 = nn.Linear(128, num_classes)

    def forward(self, x):
        x = self.pool(torch.relu(self.conv1(x)))
        x = x.view(x.size(0), -1)
        x = torch.relu(self.fc1(x))
        x = self.fc2(x)
        return x


def load_test_split():
    """학습 때와 동일한 방식(같은 random_state)으로 테스트셋을 재현."""
    with open("norm_stats_64ch.json", "r", encoding="utf-8") as f:
        norm_stats = json.load(f)

    df = pd.read_csv("chair_64ch_posture_data.csv")
    sensor_cols = norm_stats["sensor_cols_order"]
    mean = np.array(norm_stats["mean"], dtype=np.float32)
    std = np.array(norm_stats["std"], dtype=np.float32)

    X_all = ((df[sensor_cols].values - mean) / (std + 1e-7)).astype(np.float32)
    le = LabelEncoder()
    le.classes_ = np.array(norm_stats["label_classes"])
    y_all = le.transform(df["Label"].values)

    _, X_test, _, y_test = train_test_split(
        X_all, y_all, test_size=0.2, random_state=42, stratify=y_all
    )
    return X_test, y_test, norm_stats


def convert(pt_path="posture_model_64ch.pt", out_path="posture_model_64ch.tflite"):
    with open("norm_stats_64ch.json", "r", encoding="utf-8") as f:
        norm_stats = json.load(f)
    num_classes = norm_stats["num_classes"]

    # ---- 1) PyTorch 모델 로드 ----
    model = PostureCNN64(num_classes=num_classes)
    model.load_state_dict(torch.load(pt_path, map_location="cpu"))
    model.eval()

    # ---- 2) PyTorch -> ONNX ----
    dummy_input = torch.randn(1, 1, 64)
    onnx_path = "posture_model_64ch.onnx"
    torch.onnx.export(
        model, dummy_input, onnx_path,
        input_names=["input"], output_names=["output"],
        dynamic_axes={"input": {0: "batch"}, "output": {0: "batch"}},
        opset_version=13,
    )
    print(f"✅ 1단계 완료: PyTorch -> ONNX ({onnx_path})")

    # ---- 3) ONNX -> TFLite (onnx2tf 사용) ----
    # onnx-tf(구식, 최신 onnx와 호환 안 됨) 대신 활발히 관리되는 onnx2tf를 씁니다.
    # onnx2tf는 saved_model과 tflite(float32/float16/int8)를 한 번에 만들어줍니다.
    import subprocess

    output_dir = "posture_model_64ch_tf"
    subprocess.run(
        ["onnx2tf", "-i", onnx_path, "-o", output_dir, "-osd"],
        check=True,
    )
    print(f"✅ 2~3단계 완료: ONNX -> TFLite (결과물: {output_dir}/ 폴더)")

    # onnx2tf가 만든 float32 tflite 파일을 표준 위치로 복사
    import glob
    import shutil

    candidates = glob.glob(f"{output_dir}/*float32*.tflite")
    if not candidates:
        raise FileNotFoundError(f"{output_dir} 폴더에서 float32 tflite 파일을 못 찾았어요. 폴더 안을 직접 확인해주세요.")
    shutil.copy(candidates[0], out_path)
    print(f"✅ 최종 파일 저장: {out_path} (원본: {candidates[0]})")

    return model, out_path


def verify(pt_model, tflite_path):
    import tensorflow as tf

    X_test, y_test, norm_stats = load_test_split()
    label_classes = norm_stats["label_classes"]

    # ---- PyTorch 모델 정확도 ----
    pt_model.eval()
    with torch.no_grad():
        inputs = torch.tensor(X_test).float().unsqueeze(1)  # (N, 1, 64)
        outputs = pt_model(inputs)
        pt_preds = torch.argmax(outputs, dim=1).numpy()
    pt_accuracy = (pt_preds == y_test).mean()

    # ---- TFLite 모델 정확도 ----
    interpreter = tf.lite.Interpreter(model_path=tflite_path)
    interpreter.allocate_tensors()
    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()

    tflite_preds = []
    expected_shape = input_details[0]["shape"]  # 예: [1, 1, 64] 또는 [1, 64, 1]
    for i in range(len(X_test)):
        x = X_test[i].reshape(expected_shape).astype(np.float32)
        interpreter.set_tensor(input_details[0]["index"], x)
        interpreter.invoke()
        out = interpreter.get_tensor(output_details[0]["index"])
        tflite_preds.append(int(np.argmax(out)))
    tflite_preds = np.array(tflite_preds)
    tflite_accuracy = (tflite_preds == y_test).mean()

    # ---- 두 모델의 예측이 서로 얼마나 일치하는지 (변환 과정에서 손실 있었는지) ----
    agreement = (pt_preds == tflite_preds).mean()

    print("\n" + "=" * 60)
    print(f"PyTorch  모델 테스트 정확도: {pt_accuracy * 100:.2f}%")
    print(f"TFLite   모델 테스트 정확도: {tflite_accuracy * 100:.2f}%")
    print(f"두 모델 예측 일치율(변환 손실 확인용): {agreement * 100:.2f}%")
    print("=" * 60)

    if agreement < 0.95:
        print("⚠️  두 모델의 예측이 5% 이상 달라요. 변환 과정에서 정밀도 손실이 있었을 수 있습니다.")
    else:
        print("🎉 변환이 정상적으로 이루어졌습니다 (예측 결과가 거의 동일).")

    return {
        "pt_accuracy": float(pt_accuracy),
        "tflite_accuracy": float(tflite_accuracy),
        "agreement": float(agreement),
        "label_classes": label_classes,
    }


if __name__ == "__main__":
    pt_model, tflite_path = convert()
    result = verify(pt_model, tflite_path)
    with open("tflite_verification_result.json", "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)
    print("\n✅ 검증 결과를 tflite_verification_result.json에 저장했습니다.")
