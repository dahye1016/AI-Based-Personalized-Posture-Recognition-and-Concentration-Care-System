"""
add_forward_guard.py — 지금 모델(60d0bb4 가중치 그대로)에 '등받이가 안 닿으면 앞숙임'을 넣어 다시 TFLite 로 만든다

이유: 앞숙임은 모든 녹화에서 등받이 비율(등받이 합/전체 합)이 0~1% 인데,
      실제로 앉았을 때 무릎 압력이 녹화보다 커서 모델이 오른기대기·왼다리꼬기로 헷갈림.
규칙: 앉아 있고(64채널 합 >= 300) 등받이 비율 < 1.5% 이면 lean_forward.
      나머지는 기존 모델 그대로 (가중치: ml/posture_model_corrected_weights.npz).
실행: python ml/add_forward_guard.py   (tensorflow 필요)
"""
from pathlib import Path
import numpy as np, tensorflow as tf

ROOT = Path(__file__).resolve().parents[1]
W = np.load(ROOT / "ml/posture_model_corrected_weights.npz")
OUT = ROOT / "ml/posture_model_corrected.tflite"
EMPTY_SUM, FORWARD_BACK_SHARE = 300.0, 0.015
BACK_L = list(range(37, 42)) + list(range(49, 56)) + list(range(60, 64))
BACK_R = list(range(32, 37)) + list(range(42, 49)) + list(range(56, 60))


def m(idx):
    a = np.zeros((64, 1), np.float32); a[idx] = 1; return tf.constant(a)


class Model(tf.Module):
    def __init__(self):
        self.mL, self.mR, self.mKL, self.mKR = m(BACK_L), m(BACK_R), m(list(range(24, 28))), m(list(range(28, 32)))
        self.w = {k: tf.constant(W[k]) for k in W.files}

    @tf.function(input_signature=[tf.TensorSpec([None, 128], tf.float32, name="raw_and_baseline")])
    def __call__(self, inp):
        x = inp[:, :64]
        t = tf.reduce_sum(x, 1, keepdims=True)
        bl, br = x @ self.mL, x @ self.mR; b = bl + br
        kl, kr = x @ self.mKL, x @ self.mKR
        f = tf.concat([x / tf.maximum(t, 1.0), tf.math.log1p(t) / 10.0, b / tf.maximum(t, 1.0),
                       bl / tf.maximum(b, 1.0), kr / tf.maximum(kl + kr, 1.0)], 1)
        h = tf.nn.relu(f @ tf.transpose(self.w["W1"]) + self.w["b1"])
        h = tf.nn.relu(h @ tf.transpose(self.w["W2"]) + self.w["b2"])
        p = tf.nn.softmax(h @ tf.transpose(self.w["W3"]) + self.w["b3"])
        q = p * tf.constant([[0.0, 1, 1, 1, 1, 1, 1]])
        q = q / tf.maximum(tf.reduce_sum(q, 1, keepdims=True), 1e-7)
        n = tf.shape(x)[:1]
        q = tf.where(b / tf.maximum(t, 1.0) < FORWARD_BACK_SHARE, tf.one_hot(tf.fill(n, 2), 7), q)
        return tf.where(t < EMPTY_SUM, tf.one_hot(tf.fill(n, 0), 7), q)


if __name__ == "__main__":
    mod = Model()
    conv = tf.lite.TFLiteConverter.from_concrete_functions([mod.__call__.get_concrete_function()], mod)
    OUT.write_bytes(conv.convert())
    print("저장:", OUT, f"{OUT.stat().st_size/1e3:.0f}KB")
