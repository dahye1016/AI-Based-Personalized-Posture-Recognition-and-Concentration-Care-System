"""
train_posture_2p.py — 지금 기기(labchair) 녹화 두 사람(다혜·아로)으로 학습한 앱용 모델

바뀐 점 (train_posture_device.py 대비)
  - 다혜 정자세: 커넥터 수리 후 녹화(8d14eeb, 19:35)로 되돌림.
    (8ccd170 의 17:06 녹화는 좌석 오른쪽 16칸이 전부 0 — 이걸로 배우면 '오른쪽 0 = 정자세' 가 됨)
  - 아로 7자세 녹화 추가: data/test_64ch/rec7-labchair-aro.csv (앱 BLE 10Hz, 자세당 약 15초, 일어선 줄 제외)
  - 사람마다 녹화 길이가 달라서, 기기 데이터는 사람별로 비슷한 양이 되게 반복.
  - 기기 더미(가상 사용자)는 사람마다 따로 만들어 합침.
  - 앞숙임 규칙 없음. 빈 방석(합 < 300)만 not_sitting.
검증 (--eval): 기기 사람 한 명을 학습에서 빼고 그 사람으로 채점 (처음 앉는 사람 기준)
실행: python ml/train_posture_2p.py [--eval]
"""
import glob, json, sys
from pathlib import Path
import numpy as np, pandas as pd, tensorflow as tf

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "ml"))
EVAL = "--eval" in sys.argv
sys.argv = sys.argv[:1]
import train_posture_corrected as T  # noqa: E402
import train_posture_device as D  # noqa: E402
import gen_dummy_device as G  # noqa: E402

CH, L = T.CH, np.array(T.LABELS)
DEV_FRAMES = 5000          # 기기 데이터는 사람마다 자세당 약 이만큼이 되게 반복
DEV_DUMMY_PEOPLE = 15      # 사람마다 가상 사용자 수


def load_device():
    out = []
    for f in sorted(glob.glob(str(ROOT / "data/test_64ch/*.csv"))):
        d = pd.read_csv(f)
        d["person"] = "dev_aro" if "aro" in Path(f).name else "dev_dahye"
        out.append(d[CH + ["person", "posture"]])
    d = pd.concat(out, ignore_index=True)
    return d[(d.posture != "not_sitting") & (d[CH].sum(axis=1) >= D.EMPTY_SUM)]


def device_part(dev, seed=0):
    parts = []
    for i, (q, g) in enumerate(dev.groupby("person")):
        rep = int(np.clip(round(DEV_FRAMES / g.groupby("posture").size().mean()), 1, 40))
        parts += [g] * rep
        parts.append(G.make(g, n_people=DEV_DUMMY_PEOPLE, frames=600, seed=seed + i).iloc[::D.DEV_DUMMY_EVERY])
    return parts


def train_on(real, dum, dev):
    return D.train(pd.concat([real, dum] + device_part(dev), ignore_index=True))


def main():
    real, dum, _ = D.load()
    dev = load_device()
    print("기기 데이터:", dev.groupby(["person", "posture"]).size().unstack(0).to_dict())
    report = {}
    if EVAL:
        for q in sorted(dev.person.unique()):
            m = train_on(real, dum, dev[dev.person != q])
            report[q + "_빼고학습"] = D.score(m, dev[dev.person == q])
            print(q, "(학습에서 뺌):", report[q + "_빼고학습"], flush=True)

    final = train_on(real, dum, dev)
    D.OUT.write_bytes(tf.lite.TFLiteConverter.from_keras_model(final).convert())
    it = tf.lite.Interpreter(model_path=str(D.OUT))
    X = np.vstack([dev[CH].to_numpy(np.float32), np.zeros((5, 64), np.float32)])
    inp = np.hstack([X, np.zeros_like(X)])
    it.resize_tensor_input(0, [len(inp), 128]); it.allocate_tensors()
    it.set_tensor(it.get_input_details()[0]["index"], inp); it.invoke()
    agree = float((it.get_tensor(it.get_output_details()[0]["index"]).argmax(1) == final.predict(inp, verbose=0).argmax(1)).mean())
    report["학습포함_기기"] = {q: D.score(final, g) for q, g in dev.groupby("person")}
    report["학습포함_예전4명"] = {q: D.score(final, g)[0] for q, g in real.groupby("person")}
    print("학습 포함 채점:", report["학습포함_기기"], report["학습포함_예전4명"], "TFLite 일치", agree)

    # 앱/PC 도구용 가중치 (live_predict.py)
    dens = [l for l in final.layers if isinstance(l, tf.keras.layers.Dense)]
    np.savez(ROOT / "ml/posture_model_corrected_weights.npz",
             W1=dens[0].get_weights()[0].T, b1=dens[0].get_weights()[1],
             W2=dens[1].get_weights()[0].T, b2=dens[1].get_weights()[1],
             W3=dens[2].get_weights()[0].T, b3=dens[2].get_weights()[1])

    st = json.loads(D.OUT_JSON.read_text())
    st["model_io"]["output"] = "7칸 확률 (argmax 가 label_order 인덱스). 빈 방석(64채널 합 < 300)이면 not_sitting, 앉아 있으면 6자세 중 판정"
    st["model"].pop("forward_guard", None); st["model"].pop("straight_fix", None)
    st["model"]["train_data"]["device"] = "data/test_64ch labchair: 다혜 6자세(정자세는 8d14eeb 수리 후 녹화) + 아로 rec7 7자세, 사람별 자세당 약 5000프레임이 되게 반복"
    st["model"]["train_data"]["device_dummy"] = f"gen_dummy_device.py 로 사람마다 가상 {DEV_DUMMY_PEOPLE}명"
    st["model"]["script"] = "ml/train_posture_2p.py"
    st["device_eval"] = report
    st.pop("device_robustness", None)
    D.OUT_JSON.write_text(json.dumps(st, ensure_ascii=False, indent=2))
    print("저장:", D.OUT.name, D.OUT_JSON.name)
    if agree < 0.999: sys.exit("⚠️ TFLite 와 Keras 예측이 다름")


if __name__ == "__main__":
    main()
