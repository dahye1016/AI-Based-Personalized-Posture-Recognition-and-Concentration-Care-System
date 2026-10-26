"""
build_model_no_not_sitting.py — 9caf369 모델을 그대로 쓰고 '앉지 않음'만 바꾼 앱용 모델 만들기

재학습하지 않는다. 9caf369 의 TFLite(ml/runs/corrected/base_9caf369.tflite)에서 학습된 가중치를
그대로 꺼내 같은 구조의 Keras 모델에 넣고, 출력 뒤에 두 가지만 붙인다.
  1) 앉아 있을 때: not_sitting(0번) 칸을 0 으로 만들고 나머지 6자세 확률을 합 1 로 다시 맞춤
     -> 앉아 있으면 6자세 중에서만 판정 (6자세 사이의 1등은 9caf369 와 같음)
  2) 빈 방석(64채널 합 < 300): 출력을 not_sitting 으로 고정
  3) 등받이 자동 배수: 입력 뒤쪽 64칸(앱이 넣어주는 앉은 처음 5초 기준값)의 등받이 비율을 보고,
     학습 때 비율(16%)에 맞게 지금 프레임의 등받이(ch32~63)를 1~5배 키운 뒤 모델에 넣음.
     기준값이 0 이면(앱이 기준값을 안 넣으면) 1배 = 9caf369 와 똑같이 동작
     (실측: 빈 방석 합 최대 23, 앉았을 때 합 최소 1,145)

입출력은 그대로: 입력 [1,128] (원시 64 + 기준값 64, 기준값은 등받이 배수 계산에만 씀), 출력 [1,7] (label_order 순서)
결과: ml/posture_model_corrected.tflite (덮어씀)
실행: python ml/build_model_no_not_sitting.py
"""
import sys
from pathlib import Path
import numpy as np
import tensorflow as tf

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "ml"))
sys.argv = sys.argv[:1]
import train_posture_corrected as T  # noqa: E402  (Features 층·채널 정의를 같이 씀)

BASE = ROOT / "ml/runs/corrected/base_9caf369.tflite"
OUT = ROOT / "ml/posture_model_corrected.tflite"
EMPTY_SUM = 300.0
TARGET_BACK_SHARE = 16.0   # 학습 데이터 정자세의 등받이 비율(%)
MAX_BACK_GAIN = 5.0


class BackGain(tf.keras.layers.Layer):
    """기준값(앉은 처음 5초 평균, 입력 뒤쪽 64칸)의 등받이 비율을 보고 지금 프레임의 등받이(ch32~63)를 키운다.
    배수 = TARGET_BACK_SHARE / 기준값 등받이 비율, 1~MAX_BACK_GAIN 로 제한.
    기준값이 없거나(합 0) 등받이를 거의 안 댄 기준값(0.5% 미만)이면 1배."""
    def call(self, inp):
        x, base = inp[:, :64], inp[:, 64:]
        tot = tf.reduce_sum(base, 1, keepdims=True)
        back = tf.reduce_sum(base[:, 32:], 1, keepdims=True)
        share = back / tf.maximum(tot, 1.0) * 100.0
        gain = tf.clip_by_value(TARGET_BACK_SHARE / tf.maximum(share, 1e-3), 1.0, MAX_BACK_GAIN)
        gain = tf.where(share >= 0.5, gain, tf.ones_like(gain))
        return tf.concat([x[:, :32], x[:, 32:] * gain], 1)


class SeatedOnly(tf.keras.layers.Layer):
    """앉아 있으면 not_sitting 칸 0, 빈 방석이면 not_sitting 으로 고정."""
    def call(self, inputs):
        x, p = inputs
        m = tf.constant([[0.0, 1, 1, 1, 1, 1, 1]], dtype=p.dtype)
        q = p * m
        q = q / tf.maximum(tf.reduce_sum(q, 1, keepdims=True), 1e-7)
        empty = tf.reduce_sum(x, 1, keepdims=True) < EMPTY_SUM
        one = tf.one_hot(tf.zeros(tf.shape(x)[:1], tf.int32), 7, dtype=p.dtype)
        return tf.where(empty, one, q)


def base_weights():
    it = tf.lite.Interpreter(model_path=str(BASE), experimental_preserve_all_tensors=True)
    it.allocate_tensors()
    w = {}
    for t in it.get_tensor_details():
        n = t["name"]
        for key in ("dense_8_1/MatMul", "dense_9_1/MatMul", "probs_1/MatMul"):
            if n.endswith(key):
                w[key] = it.get_tensor(t["index"]).T            # TFLite [out,in] -> Keras [in,out]
        for key in ("dense_8_1/Relu;functional_4_1/dense_8_1/BiasAdd", "dense_9_1/Relu;functional_4_1/dense_9_1/BiasAdd", "probs_1/BiasAdd"):
            if n.endswith(key) and len(t["shape"]) == 1:
                w[key] = it.get_tensor(t["index"])
    return [w["dense_8_1/MatMul"], w["dense_8_1/Relu;functional_4_1/dense_8_1/BiasAdd"],
            w["dense_9_1/MatMul"], w["dense_9_1/Relu;functional_4_1/dense_9_1/BiasAdd"],
            w["probs_1/MatMul"], w["probs_1/BiasAdd"]]


def main():
    inp = tf.keras.Input((128,), name="raw_and_baseline")
    x_raw = inp[:, :64]
    x = BackGain(name="back_gain")(inp)          # 등받이 자동 배수 (기준값 사용)
    h = T.Features()(x)
    d1 = tf.keras.layers.Dense(128, activation="relu"); d2 = tf.keras.layers.Dense(64, activation="relu")
    d3 = tf.keras.layers.Dense(7, activation="softmax")
    p = d3(d2(d1(h)))
    W = base_weights()
    d1.set_weights(W[0:2]); d2.set_weights(W[2:4]); d3.set_weights(W[4:6])
    base_like = tf.keras.Model(inp, p)
    final = tf.keras.Model(inp, SeatedOnly(name="seated_only")([x_raw, p]))

    # 검사 1: 옮긴 가중치가 9caf369 와 같은 확률을 내는지
    import pandas as pd
    real = pd.read_csv(ROOT / "data/train_7cls/real_27.csv.gz")
    X = real[T.CH].to_numpy(np.float32); X128 = np.hstack([X, np.zeros_like(X)])
    it = tf.lite.Interpreter(model_path=str(BASE)); it.resize_tensor_input(0, [len(X128), 128]); it.allocate_tensors()
    it.set_tensor(it.get_input_details()[0]["index"], X128); it.invoke()
    p_base = it.get_tensor(it.get_output_details()[0]["index"])
    diff = float(np.abs(base_like.predict(X128, verbose=0) - p_base).max())
    print(f"9caf369 와 확률 차이 최대 {diff:.2e}")
    if diff > 1e-4:
        sys.exit("⚠️ 가중치 옮기기 실패")

    OUT.write_bytes(tf.lite.TFLiteConverter.from_keras_model(final).convert())

    # 검사 2: 새 TFLite — 앉은 프레임에서 6자세 1등이 9caf369 와 같은지, 빈 방석은 not_sitting 인지
    it = tf.lite.Interpreter(model_path=str(OUT)); it.resize_tensor_input(0, [len(X128), 128]); it.allocate_tensors()
    it.set_tensor(it.get_input_details()[0]["index"], X128); it.invoke()
    p_new = it.get_tensor(it.get_output_details()[0]["index"])
    seated = X.sum(1) >= EMPTY_SUM
    same = float((p_new[seated].argmax(1) == p_base[seated][:, 1:].argmax(1) + 1).mean())
    empty_ok = float((p_new[~seated].argmax(1) == 0).mean())
    ns_seated = int((p_new[seated].argmax(1) == 0).sum())
    print(f"앉은 프레임: 9caf369 의 6자세 1등과 같음 {same*100:.2f}% / 앉지 않음 판정 {ns_seated}개")
    print(f"빈 방석 프레임: 앉지 않음 {empty_ok*100:.1f}%")
    print(f"저장: {OUT.name} ({OUT.stat().st_size/1e3:.0f}KB)")
    if same < 0.9999 or empty_ok < 1 or ns_seated:
        sys.exit("⚠️ 검사 실패")

    # 검사 3: 등받이가 약한 의자 흉내 — 등받이를 줄이고 기준값(정자세 처음 50프레임)을 같이 넣었을 때
    import pandas as pd  # noqa
    L = np.array(T.LABELS); rows = []
    for f in (1.0, 0.5, 0.3, 0.2):
        accs = []
        for q, d in real.groupby("person"):
            Xq = d[T.CH].to_numpy(np.float32).copy(); yq = d.posture.to_numpy()
            if not (yq == "sitting_straight").any(): continue
            Xq[:, 32:] *= f; Xq = np.rint(Xq); Xq[Xq < 20] = 0
            B = np.repeat(Xq[yq == "sitting_straight"][:50].mean(0, keepdims=True), len(Xq), 0)
            it.resize_tensor_input(0, [len(Xq), 128]); it.allocate_tensors()
            it.set_tensor(it.get_input_details()[0]["index"], np.hstack([Xq, B]).astype(np.float32)); it.invoke()
            pq = L[it.get_tensor(it.get_output_details()[0]["index"]).argmax(1)]
            accs.append(((pq == yq).mean(), (pq[yq == "sitting_straight"] == "sitting_straight").mean()))
        a = np.mean(accs, 0); rows.append((f, a[0], a[1]))
        print(f"등받이 {int(f*100):3d}% + 기준값: 전체 {a[0]*100:5.1f}% / 정자세 {a[1]*100:5.1f}%")
    if rows[2][2] < 0.9:
        sys.exit("⚠️ 등받이 30% 에서 정자세가 90% 미만")


if __name__ == "__main__":
    main()
