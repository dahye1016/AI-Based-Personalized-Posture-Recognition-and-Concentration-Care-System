"""
tflite_demo.py

posture_model_64ch.tflite가 실제로 잘 작동하는지 눈으로 확인하는 데모.
chair_64ch_posture_data.csv에서 실제 행을 하나씩 랜덤으로 뽑아서
TFLite 모델에 넣고, "실제 라벨 vs TFLite 예측"을 계속 출력합니다.

실행 위치: tf_env 가상환경 (TFLite 변환할 때 쓴 그 환경)
필요 파일 (같은 폴더): posture_model_64ch.tflite, norm_stats_64ch.json,
                        chair_64ch_posture_data.csv

실행:
    tf_env\\Scripts\\activate   (아직 활성화 안 했다면)
    python tflite_demo.py
"""

import json
import random
import time

import numpy as np
import pandas as pd
import tensorflow as tf

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


def main():
    with open("norm_stats_64ch.json", "r", encoding="utf-8") as f:
        norm_stats = json.load(f)
    sensor_cols = norm_stats["sensor_cols_order"]
    mean = np.array(norm_stats["mean"], dtype=np.float32)
    std = np.array(norm_stats["std"], dtype=np.float32)

    df = pd.read_csv("chair_64ch_posture_data.csv")

    interpreter = tf.lite.Interpreter(model_path="posture_model_64ch.tflite")
    interpreter.allocate_tensors()
    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()
    expected_shape = input_details[0]["shape"]

    print("=" * 60)
    print("  TFLite 모델 실시간 판정 데모")
    print("  (chair_64ch_posture_data.csv에서 실제 행을 하나씩 뽑아 판정)")
    print("=" * 60)
    print("Ctrl+C로 멈출 수 있어요.\n")

    correct = 0
    total = 0
    try:
        while True:
            row = df.sample(1).iloc[0]
            true_label = row["Label"]
            raw = row[sensor_cols].values.astype(np.float32)

            norm = (raw - mean) / (std + 1e-7)
            x = norm.reshape(expected_shape).astype(np.float32)

            interpreter.set_tensor(input_details[0]["index"], x)
            interpreter.invoke()
            out = interpreter.get_tensor(output_details[0]["index"])
            pred_idx = int(np.argmax(out))
            pred_label = norm_stats["label_classes"][pred_idx]

            total += 1
            match = pred_label == true_label
            correct += int(match)
            mark = "✅ 일치" if match else "❓"

            print(
                f"실제: {true_label}({DISPLAY_NAMES.get(true_label,'')}) | "
                f"TFLite 예측: {pred_label}({DISPLAY_NAMES.get(pred_label,'')}) {mark} "
                f"| 누적 정확도: {correct}/{total} ({correct/total*100:.1f}%)"
            )
            time.sleep(0.5)
    except KeyboardInterrupt:
        print("\n데모 종료.")


if __name__ == "__main__":
    main()
