"""
train_posture_straight_fix.py — 60d0bb4 모델에서 시작해 '정자세'가 더 잘 나오게 조금만 더 학습

문제: 60d0bb4 는 정자세에 다른 자세가 조금(25%)만 섞여도 오른다리꼬기 등으로 판정할 때가 있음.
방법: 60d0bb4 가중치(ml/posture_model_corrected_weights.npz)에서 시작해,
      원래 학습 데이터 + '정자세에 다른 자세를 0~35% 섞은 프레임 = 정자세' 를 넣어 낮은 학습률로 몇 번 더 학습.
      (반대로 60% 이상 섞인 프레임은 그 자세로 둬서 나쁜 자세 검출은 유지)
      앞숙임 규칙은 넣지 않음 (60d0bb4 와 같은 구조).
실행: python ml/train_posture_straight_fix.py
"""
import glob, sys
from pathlib import Path
import numpy as np, pandas as pd, tensorflow as tf

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "ml")); sys.argv = sys.argv[:1]
import train_posture_corrected as T  # noqa: E402
import train_posture_device as D  # noqa: E402
import gen_dummy_device as G  # noqa: E402

STRAIGHT_MIX_MAX, OTHER_MIX_MIN = 0.35, 0.6
EPOCHS, LR = 4, 2e-4


def mixes(df, n=400, seed=7):
    """사람마다 정자세와 다른 자세를 섞는다: a<=0.35 -> 정자세, a>=0.6 -> 그 자세."""
    rng = np.random.default_rng(seed); out = []
    for q, d in df.groupby("person"):
        st = d[d.posture == "sitting_straight"][T.CH].to_numpy(np.float32)
        if len(st) == 0: continue
        for p in ["lean_forward", "cross_leg_right", "cross_leg_left", "lean_right", "lean_left"]:
            o = d[d.posture == p][T.CH].to_numpy(np.float32)
            if len(o) == 0: continue
            for lo, hi, lab in ((0.0, STRAIGHT_MIX_MAX, "sitting_straight"), (OTHER_MIX_MIN, 1.0, p)):
                a = rng.uniform(lo, hi, (n, 1)).astype(np.float32)
                X = np.rint((1 - a) * st[rng.integers(len(st), size=n)] + a * o[rng.integers(len(o), size=n)]); X[X < 20] = 0
                f = pd.DataFrame(X, columns=T.CH); f["person"] = q; f["posture"] = lab; out.append(f)
    return pd.concat(out, ignore_index=True)


def build_from_weights():
    W = np.load(ROOT / "ml/posture_model_corrected_weights.npz")
    tr, _ = T.build()
    dens = [l for l in tr.layers if isinstance(l, tf.keras.layers.Dense)]
    for l, (w, b) in zip(dens, [("W1", "b1"), ("W2", "b2"), ("W3", "b3")]):
        l.set_weights([W[w].T, W[b]])
    tr.compile(optimizer=tf.keras.optimizers.Adam(LR), loss="sparse_categorical_crossentropy", metrics=["accuracy"])
    return tr


def main():
    real, dum, dev = D.load()
    ddum = G.make(dev).iloc[::D.DEV_DUMMY_EVERY]
    base = pd.concat([real, dum] + [dev] * D.DEVICE_WEIGHT + [ddum])
    df = pd.concat([base, T.partial_lean(base), mixes(pd.concat([real, dev] + [dev] * 2 + [ddum]))], ignore_index=True)
    X, y = T.xy(df)
    w = len(y) / (7 * np.maximum(np.bincount(y, minlength=7), 1))
    tf.keras.utils.set_random_seed(T.SEED)
    m = build_from_weights()
    m.fit(T.to128(X), y, epochs=EPOCHS, batch_size=512, verbose=2, sample_weight=w[y], shuffle=True)
    final = tf.keras.Model(m.input, D.SeatedOnly(name="seated_only")([m.input[:, :64], m.output]))
    D.OUT.write_bytes(tf.lite.TFLiteConverter.from_keras_model(final).convert())
    dens = [l for l in m.layers if isinstance(l, tf.keras.layers.Dense)]
    np.savez(ROOT / "ml/posture_model_corrected_weights.npz",
             **{k: v for (wk, bk), l in zip([("W1", "b1"), ("W2", "b2"), ("W3", "b3")], dens)
                for k, v in ((wk, l.get_weights()[0].T), (bk, l.get_weights()[1]))})
    print("저장:", D.OUT)


if __name__ == "__main__":
    main()
