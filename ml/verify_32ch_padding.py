"""
verify_32ch_padding.py

가설 검증용 스크립트 (학습·변환 안 함. 추론만 한다).

  질문: 등받이 센서가 아직 없어서 back_1~32 를 전부 0으로 채워 넣어도
        posture_model_64ch.tflite 의 판정이 유지되는가?

  (A) 원본 64ch 입력 그대로 추론
  (B) back_1~32 를 raw 단계에서 0으로 만든 뒤 같은 mean/std 로 정규화해 추론

  ※ 0 채우기는 반드시 "정규화 전(raw)"에 해야 실제 상황(등받이 매트 없음 =
     물리 압력 0)과 같아진다. 정규화 후 0을 넣으면 "평균값이 들어온 것"이
     되어버려서 전혀 다른 실험이 된다.

실행:  cd ml && python verify_32ch_padding.py
필요:  tensorflow(또는 tflite_runtime / ai_edge_litert), numpy, pandas, scikit-learn
       + 같은 폴더의 posture_model_64ch.tflite, norm_stats_64ch.json,
         chair_64ch_posture_data.csv
"""

import json
from collections import Counter

import numpy as np
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder


def load_interpreter(model_path: str):
    """tf.lite -> ai_edge_litert -> tflite_runtime 순으로 인터프리터를 찾는다."""
    try:
        import tensorflow as tf

        return tf.lite.Interpreter(model_path=model_path)
    except ImportError:
        pass
    try:
        from ai_edge_litert.interpreter import Interpreter

        return Interpreter(model_path=model_path)
    except ImportError:
        pass
    from tflite_runtime.interpreter import Interpreter

    return Interpreter(model_path=model_path)


def load_data():
    """학습 때와 동일한 방식(random_state=42, stratify)으로 테스트셋을 재현.

    convert_to_tflite.py 의 load_test_split() 과 같은 분할이지만,
    여기서는 raw 값을 0으로 덮어써야 하므로 정규화 전 raw 를 그대로 들고 간다.
    """
    with open("norm_stats_64ch.json", "r", encoding="utf-8") as f:
        norm_stats = json.load(f)

    sensor_cols = norm_stats["sensor_cols_order"]  # seat_1..32 -> back_1..32 순서 고정
    mean = np.array(norm_stats["mean"], dtype=np.float32)
    std = np.array(norm_stats["std"], dtype=np.float32)
    label_classes = norm_stats["label_classes"]

    df = pd.read_csv("chair_64ch_posture_data.csv")
    X_raw = df[sensor_cols].values.astype(np.float32)

    le = LabelEncoder()
    le.classes_ = np.array(label_classes)
    y_all = le.transform(df["Label"].values)

    _, X_test_raw, _, y_test = train_test_split(
        X_raw, y_all, test_size=0.2, random_state=42, stratify=y_all
    )

    back_idx = [i for i, c in enumerate(sensor_cols) if c.startswith("back_")]
    return X_test_raw, y_test, mean, std, label_classes, back_idx


def predict_all(interpreter, X_norm: np.ndarray) -> np.ndarray:
    interpreter.allocate_tensors()
    inp = interpreter.get_input_details()[0]
    out = interpreter.get_output_details()[0]
    shape = inp["shape"]

    preds = np.empty(len(X_norm), dtype=np.int64)
    for i in range(len(X_norm)):
        interpreter.set_tensor(inp["index"], X_norm[i].reshape(shape).astype(np.float32))
        interpreter.invoke()
        preds[i] = int(np.argmax(interpreter.get_tensor(out["index"])))
    return preds


def per_label_accuracy(y_true, y_pred, label_classes):
    rows = []
    for k, name in enumerate(label_classes):
        m = y_true == k
        n = int(m.sum())
        acc = float((y_pred[m] == k).mean()) if n else float("nan")
        rows.append((name, n, acc))
    return rows


def main():
    X_raw, y_test, mean, std, label_classes, back_idx = load_data()
    print(f"테스트 샘플 {len(X_raw)}개 / 클래스 {len(label_classes)}종 {label_classes}")
    print(f"등받이 채널 인덱스 {back_idx[0]}~{back_idx[-1]} ({len(back_idx)}개)\n")

    denom = std + 1e-7

    # (A) 원본 64ch
    Xa = (X_raw - mean) / denom

    # (B) raw 단계에서 등받이 0 -> 동일 mean/std 로 정규화
    X_raw_b = X_raw.copy()
    X_raw_b[:, back_idx] = 0.0
    Xb = (X_raw_b - mean) / denom

    interpreter = load_interpreter("posture_model_64ch.tflite")
    pred_a = predict_all(interpreter, Xa)
    pred_b = predict_all(interpreter, Xb)

    acc_a = float((pred_a == y_test).mean())
    acc_b = float((pred_b == y_test).mean())
    flipped = int((pred_a != pred_b).sum())

    print("=" * 62)
    print(f"(A) 원본 64ch        정확도: {acc_a * 100:6.2f}%")
    print(f"(B) 등받이 0패딩     정확도: {acc_b * 100:6.2f}%")
    print(f"    차이: {(acc_b - acc_a) * 100:+.2f}%p")
    print(f"    예측이 뒤바뀐 샘플: {flipped} / {len(y_test)} ({flipped / len(y_test) * 100:.2f}%)")
    print("=" * 62)

    print("\n[라벨별 정확도]")
    print(f"  {'label':<6}{'n':>6}{'A':>10}{'B':>10}{'차이':>10}")
    ra = per_label_accuracy(y_test, pred_a, label_classes)
    rb = per_label_accuracy(y_test, pred_b, label_classes)
    for (name, n, a), (_, _, b) in zip(ra, rb):
        print(f"  {name:<6}{n:>6}{a * 100:>9.1f}%{b * 100:>9.1f}%{(b - a) * 100:>+9.1f}p")

    print("\n[예측이 바뀐 방향]  A예측 -> B예측 (건수)")
    changes = Counter(
        (label_classes[pa], label_classes[pb])
        for pa, pb in zip(pred_a, pred_b)
        if pa != pb
    )
    for (a_name, b_name), cnt in changes.most_common():
        print(f"  {a_name} -> {b_name}: {cnt}")

    print("\n[B에서 새로 틀린 것 / 새로 맞은 것]")
    newly_wrong = int(((pred_a == y_test) & (pred_b != y_test)).sum())
    newly_right = int(((pred_a != y_test) & (pred_b == y_test)).sum())
    print(f"  A맞음 -> B틀림: {newly_wrong}")
    print(f"  A틀림 -> B맞음: {newly_right}")


if __name__ == "__main__":
    main()
