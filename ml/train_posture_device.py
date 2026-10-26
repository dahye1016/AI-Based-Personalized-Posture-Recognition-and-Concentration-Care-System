"""
train_posture_device.py — 지금 기기(labchair) 녹화를 넣어 다시 학습한 앱용 모델

데이터
  - 예전 실측 27녹화 + 더미 30명 (data/train_7cls/)  — 9caf369 와 같음
  - 지금 기기 7자세 녹화 (data/test_64ch/, 2026-10-26 dahye, 커넥터 수리 후) 를 5배 가중으로 추가
  - 그 녹화로 만든 가상 사용자 30명 더미 (ml/gen_dummy_device.py — 체중·의자(등받이·무릎)·자세 강도 변화)
  - 미착석은 학습에서 뺌. 모두 좌우 반전 + '반쯤 기댄' 자세 추가 (train_posture_corrected.py 와 같음)
출력
  - ml/posture_model_corrected.tflite (앱이 읽는 이름 그대로), 입력 [1,128], 출력 [1,7]
  - 빈 방석(64채널 합 < 300) 이면 not_sitting, 앉아 있으면 6자세 중 판정 (not_sitting 칸 0)
  - 기준값(입력 뒤쪽 64칸)은 쓰지 않음
검증 (--eval)
  - labchair 녹화 앞 60% 로 학습, 뒤 40% 로 채점 + 예전 사람 한 명씩 빼고 채점
실행: python ml/train_posture_device.py [--eval]
"""
import glob, json, sys
from pathlib import Path
import numpy as np, pandas as pd, tensorflow as tf

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "ml"))
EVAL = "--eval" in sys.argv
sys.argv = sys.argv[:1]
import train_posture_corrected as T  # noqa: E402
import gen_dummy_device as G  # noqa: E402
USE_DEV_DUMMY = True
DEV_DUMMY_EVERY = 3    # 기기 더미는 3프레임마다 1개

DEVICE_GLOB = str(ROOT / "data/test_64ch/*.csv")
DEVICE_WEIGHT = 5
EMPTY_SUM = 300.0
OUT = ROOT / "ml/posture_model_corrected.tflite"
OUT_JSON = ROOT / "ml/norm_stats_corrected.json"
CH, L = T.CH, np.array(T.LABELS)


class SeatedOnly(tf.keras.layers.Layer):
    """앉아 있으면 not_sitting 칸 0, 빈 방석이면 not_sitting 으로 고정."""
    def call(self, inputs):
        x, p = inputs
        q = p * tf.constant([[0.0, 1, 1, 1, 1, 1, 1]], dtype=p.dtype)
        q = q / tf.maximum(tf.reduce_sum(q, 1, keepdims=True), 1e-7)
        empty = tf.reduce_sum(x, 1, keepdims=True) < EMPTY_SUM
        one = tf.one_hot(tf.zeros(tf.shape(x)[:1], tf.int32), 7, dtype=p.dtype)
        return tf.where(empty, one, q)


def load():
    real = pd.read_csv(ROOT / "data/train_7cls/real_27.csv.gz")
    dum = pd.read_csv(ROOT / "data/train_7cls/dummy_30p.csv.gz").iloc[::T.DUMMY_EVERY]
    dev = pd.concat([pd.read_csv(f) for f in sorted(glob.glob(DEVICE_GLOB))])
    dev["person"] = "labchair"
    keep = lambda d: d[d.posture != "not_sitting"]
    return keep(real), keep(dum), keep(dev)


def pred(model, X):
    out = model.predict(np.hstack([X, np.zeros_like(X)]).astype(np.float32), verbose=0)
    return L[out.argmax(1)]


def score(model, df):
    X = df[CH].to_numpy(np.float32); y = df.posture.to_numpy(); p = pred(model, X)
    per = {k: round(float((p[y == k] == k).mean() * 100), 1) for k in T.LABELS if (y == k).any()}
    return round(float((p == y).mean() * 100), 1), per


def train(df):
    m, _ = T.fit(df)
    inp = m.input
    return tf.keras.Model(inp, SeatedOnly(name="seated_only")([inp[:, :64], m.output]))


def main():
    real, dum, dev = load()
    ddum_all = [G.make(dev).iloc[::DEV_DUMMY_EVERY]] if USE_DEV_DUMMY else []
    report = {}
    if EVAL:
        tr, te = [], []
        for _, g in dev.groupby("posture"):
            k = int(len(g) * 0.6); tr.append(g.iloc[:k]); te.append(g.iloc[k + 50:])
        trd = pd.concat(tr)
        ddum = [G.make(trd).iloc[::DEV_DUMMY_EVERY]] if USE_DEV_DUMMY else []   # 더미도 앞 60% 로만 만듦
        m = train(pd.concat([real, dum] + [trd] * DEVICE_WEIGHT + ddum))
        report["device_time_split"] = score(m, pd.concat(te))
        print("labchair 뒤 40% (학습 안 함):", report["device_time_split"])
        lopo = {}
        for q in sorted(real.person.unique()):
            m = train(pd.concat([real[real.person != q], dum] + [dev] * DEVICE_WEIGHT + ddum_all))
            lopo[q] = score(m, real[real.person == q]); print(q, "(학습에서 뺌):", lopo[q])
        report["old_persons_lopo"] = lopo

    final = train(pd.concat([real, dum] + [dev] * DEVICE_WEIGHT + ddum_all))
    OUT.write_bytes(tf.lite.TFLiteConverter.from_keras_model(final).convert())

    # TFLite 검사: Keras 와 같은지, 빈 방석 -> not_sitting, 앉음 -> not_sitting 없음
    it = tf.lite.Interpreter(model_path=str(OUT))
    allX = pd.concat([real, dev])[CH].to_numpy(np.float32)
    allX = np.vstack([allX, np.zeros((20, 64), np.float32)])
    inp = np.hstack([allX, np.zeros_like(allX)])
    it.resize_tensor_input(0, [len(inp), 128]); it.allocate_tensors()
    it.set_tensor(it.get_input_details()[0]["index"], inp); it.invoke()
    pt = it.get_tensor(it.get_output_details()[0]["index"]).argmax(1)
    agree = float((pt == final.predict(inp, verbose=0).argmax(1)).mean())
    seated = allX.sum(1) >= EMPTY_SUM
    print(f"TFLite-Keras 일치 {agree*100:.2f}% / 빈 방석->앉지 않음 {(pt[~seated] == 0).mean()*100:.0f}% / 앉음->앉지 않음 {(pt[seated] == 0).sum()}개")
    print("학습에 포함된 labchair:", score(final, dev))

    st = json.loads(OUT_JSON.read_text())
    st["model_io"]["input_layout"] = "값 128개 = [지금 프레임 원시값 ch0~63] + [기준값 ch0~63]. 정규화하지 말 것. 기준값은 쓰지 않음 (0 이어도 됨)"
    st["model_io"]["output"] = "7칸 확률 (argmax 가 label_order 인덱스). 빈 방석(64채널 합 < 300)이면 not_sitting, 앉아 있으면 6자세 중 판정"
    st["model"] = {"type": "특징(채널 비율·전체 합·등받이 비율·등받이 좌우·무릎 좌우) -> MLP 128-64 -> softmax, 규칙 없음(빈 방석 제외)",
                   "train_data": {"old_real": "data/train_7cls/real_27.csv.gz (미착석 제외)", "dummy": "data/train_7cls/dummy_30p.csv.gz (1/5, 미착석 제외)",
                                  "device": f"data/test_64ch (labchair, 2026-10-26 dahye) x{DEVICE_WEIGHT}",
                                  "device_dummy": "ml/gen_dummy_device.py 로 labchair 녹화에서 만든 가상 30명 (체중·등받이·무릎·자세 강도 변화, 1/3 샘플)", "flip": "좌우 반전 + 라벨 스왑", "partial": "반쯤 기댄 자세"},
                   "script": "ml/train_posture_device.py"}
    st["device_eval"] = report or st.get("device_eval")
    st.pop("labchair_eval", None)
    OUT_JSON.write_text(json.dumps(st, ensure_ascii=False, indent=2))
    print("저장:", OUT.name, OUT_JSON.name, f"({OUT.stat().st_size/1e3:.0f}KB)")
    if agree < 0.999:
        sys.exit("⚠️ TFLite 와 Keras 예측이 다름")


if __name__ == "__main__":
    main()
