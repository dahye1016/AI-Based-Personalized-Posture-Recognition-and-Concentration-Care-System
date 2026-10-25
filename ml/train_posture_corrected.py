"""
train_posture_corrected.py — 7자세 64ch 모델 (정자세 보정 포함) 학습 + TFLite 변환

데이터
  - 실측: data/train_7cls/real_27.csv.gz
      feat/yewon data/raw_64ch 27녹화 (아로1022·다혜·준서·예원, 사람마다 7자세, 겹치면 최신 녹화,
      준서 정자세 제외, 다혜 미착석은 전부 0 으로 생성)
  - 더미: data/train_7cls/dummy_30p.csv.gz — gen_dummy_from_real.py 로 실측에서 만든 가상 30명
  - 둘 다 좌우 반전(+라벨 스왑) 해서 두 배로 쓴다.

모델 (TFLite 하나에 전부 들어 있음)
  입력  [1, 128] float32 = [지금 프레임 원시값 ch0~63] + [캘리브레이션 기준값 ch0~63]
        (norm_stats_gbt.json 과 같은 계약. 기준값 64개는 받기만 하고 쓰지 않는다)
  특징  채널별 비율(값/전체 합) 64 + log(전체 합) + 등받이 비율·등받이 왼쪽 비율·오른 무릎 비율
  분류  MLP 128-64 -> 7자세 확률
  보정  모델이 왼쪽/오른쪽 기울기라고 해도 등받이 좌우(5~85%)와 무릎(20~90%)이 균형이면 정자세.
        등받이에 많이 기대는 사람(아로)의 정자세를 기울기로 착각하는 문제 대응.
  출력  [1, 7] 확률 (label_order 순서, argmax 사용)

실행: python ml/train_posture_corrected.py   (tensorflow, pandas, numpy 필요)
결과: ml/posture_model_corrected.tflite, ml/norm_stats_corrected.json, ml/runs/corrected/
"""
import json, os, sys
from pathlib import Path
import numpy as np, pandas as pd
import tensorflow as tf

ROOT = Path(__file__).resolve().parents[1]
REAL = ROOT / "data/train_7cls/real_27.csv.gz"
DUMMY = ROOT / "data/train_7cls/dummy_30p.csv.gz"
OUT_TFLITE = ROOT / "ml/posture_model_corrected.tflite"
OUT_JSON = ROOT / "ml/norm_stats_corrected.json"
RUNS = ROOT / "ml/runs/corrected"

LABELS = ["not_sitting", "sitting_straight", "lean_forward", "cross_leg_right",
          "cross_leg_left", "lean_right", "lean_left"]
CH = [f"ch{i}" for i in range(64)]
FLIP = np.concatenate([np.arange(a, b)[::-1] for a, b in [(0, 10), (10, 24), (24, 32), (32, 42), (42, 56), (56, 64)]])
SWAP = {"cross_leg_right": "cross_leg_left", "cross_leg_left": "cross_leg_right",
        "lean_right": "lean_left", "lean_left": "lean_right"}
BACK_L = list(range(37, 42)) + list(range(49, 56)) + list(range(60, 64))
BACK_R = list(range(32, 37)) + list(range(42, 49)) + list(range(56, 60))
SEED = 42
DUMMY_EVERY = 5      # 더미는 5프레임마다 1개 (실측보다 너무 많아지지 않게)


def mask(idx):
    m = np.zeros((64, 1), np.float32); m[idx] = 1; return tf.constant(m)


class Features(tf.keras.layers.Layer):
    """원시값 64 -> 특징 68. TFLite 안에서 그대로 계산된다."""
    def __init__(self, **kw):
        super().__init__(**kw)
        self.mL, self.mR = mask(BACK_L), mask(BACK_R)
        self.mKL, self.mKR = mask(list(range(24, 28))), mask(list(range(28, 32)))

    def call(self, x):
        t = tf.reduce_sum(x, 1, keepdims=True)
        bl, br = x @ self.mL, x @ self.mR; b = bl + br
        kl, kr = x @ self.mKL, x @ self.mKR
        return tf.concat([x / tf.maximum(t, 1.0), tf.math.log1p(t) / 10.0,
                          b / tf.maximum(t, 1.0), bl / tf.maximum(b, 1.0), kr / tf.maximum(kl + kr, 1.0)], 1)


class StraightCorrection(tf.keras.layers.Layer):
    """기울기 판정인데 등받이 좌우·무릎이 균형이면 정자세(1)로 바꾼다."""
    def __init__(self, **kw):
        super().__init__(**kw)
        self.mL, self.mR = mask(BACK_L), mask(BACK_R)
        self.mKL, self.mKR = mask(list(range(24, 28))), mask(list(range(28, 32)))

    def call(self, inputs):
        x, p = inputs
        bl, br = x @ self.mL, x @ self.mR; b = bl + br
        kl, kr = x @ self.mKL, x @ self.mKR
        bL = bl / tf.maximum(b, 1.0) * 100; kR = kr / tf.maximum(kl + kr, 1.0) * 100
        bal = (b >= 100) & (bL > 5) & (bL < 85) & (kl + kr >= 100) & (kR > 20) & (kR < 90)
        top = tf.argmax(p, 1, output_type=tf.int32)[:, None]
        lean = tf.equal(top, 5) | tf.equal(top, 6)
        straight = tf.one_hot(tf.fill(tf.shape(top)[:1], 1), 7, dtype=p.dtype)
        return tf.where(bal & lean, straight, p)


def build(seed=SEED):
    tf.keras.utils.set_random_seed(seed)
    inp = tf.keras.Input((128,), name="raw_and_baseline")
    x = inp[:, :64]
    h = Features()(x)
    h = tf.keras.layers.Dense(128, activation="relu")(h)
    h = tf.keras.layers.Dropout(0.2)(h)
    h = tf.keras.layers.Dense(64, activation="relu")(h)
    p = tf.keras.layers.Dense(7, activation="softmax", name="probs")(h)
    train = tf.keras.Model(inp, p)
    final = tf.keras.Model(inp, StraightCorrection()([x, p]))
    train.compile(optimizer=tf.keras.optimizers.Adam(1e-3), loss="sparse_categorical_crossentropy", metrics=["accuracy"])
    return train, final


def xy(df):
    X = df[CH].to_numpy(np.float32); y = np.array([LABELS.index(v) for v in df.posture])
    Xf = X[:, FLIP]; yf = np.array([LABELS.index(SWAP.get(LABELS[v], LABELS[v])) for v in y])
    return np.vstack([X, Xf]), np.r_[y, yf]


def to128(X): return np.hstack([X, np.zeros_like(X)]).astype(np.float32)


def fit(train_df, epochs=15):
    X, y = xy(train_df)
    w = len(y) / (7 * np.bincount(y, minlength=7))          # 자세별 균형
    tr, fin = build()
    tr.fit(to128(X), y, epochs=epochs, batch_size=512, verbose=0, sample_weight=w[y], shuffle=True)
    return fin, tr


def main():
    real = pd.read_csv(REAL); dum = pd.read_csv(DUMMY).iloc[::DUMMY_EVERY]
    RUNS.mkdir(parents=True, exist_ok=True)

    # 1) 사람 단위 평가: 한 명 빼고(실측) 학습, 그 사람으로 평가. 더미는 그 사람 없이 만든 게 아니라 참고값.
    rows = []
    persons = sorted(real.person.unique()) if "--lopo" in sys.argv else []
    for q in persons:
        fin, tr = fit(pd.concat([real[real.person != q], dum]))
        te = real[real.person == q]; Xe = to128(te[CH].to_numpy(np.float32)); ye = te.posture.to_numpy()
        raw = np.array(LABELS)[tr.predict(Xe, verbose=0).argmax(1)]
        cor = np.array(LABELS)[fin.predict(Xe, verbose=0).argmax(1)]
        per = {p: round(float((cor[ye == p] == p).mean() * 100), 1) for p in LABELS if (ye == p).any()}
        rows.append({"person": q, "acc_before_correction": round(float((raw == ye).mean() * 100), 1),
                     "acc_after_correction": round(float((cor == ye).mean() * 100), 1), "per_posture_after": per})
        print(rows[-1])
    lopo = {"method": "leave-one-person-out (실측). 더미는 30명 전체 사용(평가 대상의 실측이 재료라 약간 유리)",
            "persons": rows,
            "mean_before": round(float(np.mean([r["acc_before_correction"] for r in rows])), 1) if rows else None,
            "mean_after": round(float(np.mean([r["acc_after_correction"] for r in rows])), 1) if rows else None}

    # 2) 최종 모델: 4명 실측 + 더미 전부
    fin, _ = fit(pd.concat([real, dum]))
    conv = tf.lite.TFLiteConverter.from_keras_model(fin)
    OUT_TFLITE.write_bytes(conv.convert())

    # 3) TFLite 검증: Keras 와 같은 답인지 + 실측 정답률
    it = tf.lite.Interpreter(model_path=str(OUT_TFLITE)); it.allocate_tensors()
    i, o = it.get_input_details()[0], it.get_output_details()[0]
    X = to128(real[CH].to_numpy(np.float32)); kp = fin.predict(X, verbose=0).argmax(1); tp = []
    for row in X:
        it.set_tensor(i["index"], row[None]); it.invoke(); tp.append(it.get_tensor(o["index"])[0].argmax())
    tp = np.array(tp); agree = float((tp == kp).mean())
    train_acc = float((np.array(LABELS)[tp] == real.posture.to_numpy()).mean())
    print(f"TFLite 입력 {list(i['shape'])} 출력 {list(o['shape'])} / Keras 일치 {agree*100:.2f}% / 실측(학습에 포함) {train_acc*100:.1f}%")

    stats = {
        "label_order": LABELS, "class_index": {l: k for k, l in enumerate(LABELS)}, "num_classes": 7,
        "model_io": {"tflite_file": OUT_TFLITE.name, "input_shape": [1, 128], "input_dtype": "float32",
                     "input_layout": "값 128개 = [지금 프레임 원시값 ch0~63] + [캘리브레이션 기준값 ch0~63]. 정규화하지 말 것. 기준값은 쓰지 않으므로 0 이어도 됨",
                     "output_shape": [1, 7], "output": "7자세 확률 (argmax 가 label_order 인덱스). 정자세 보정 포함",
                     "keras_vs_tflite_agreement": agree},
        "raw_input": True,
        "channel_layout": "ch0~31 좌석, ch32~63 등받이",
        "model": {"type": "특징(채널 비율 64 + log 합 + 등받이 비율·등받이 왼쪽 비율·오른 무릎 비율) -> MLP 128-64 -> softmax",
                  "correction": "argmax 가 lean_left/lean_right 인데 등받이 합>=100, 등받이 왼쪽 비율 5~85%, 무릎 합>=100, 오른 무릎 비율 20~90% 이면 sitting_straight",
                  "train_data": {"real": REAL.name + f" ({len(real)}프레임, 27녹화)", "dummy": DUMMY.name + f" (1/{DUMMY_EVERY} 샘플)", "flip": "좌우 반전 + 라벨 스왑으로 2배"}},
        "trained_on_persons": sorted(real.person.unique().tolist()),
        "person_split_eval": lopo,
        "train_set_accuracy": train_acc,
    }
    OUT_JSON.write_text(json.dumps(stats, ensure_ascii=False, indent=2))
    (RUNS / "lopo_report.json").write_text(json.dumps(lopo, ensure_ascii=False, indent=2))
    print("저장:", OUT_TFLITE.name, OUT_JSON.name, f"({OUT_TFLITE.stat().st_size/1e3:.0f}KB)")
    if agree < 0.999: sys.exit("⚠️ TFLite 와 Keras 예측이 다릅니다")


if __name__ == "__main__":
    main()
