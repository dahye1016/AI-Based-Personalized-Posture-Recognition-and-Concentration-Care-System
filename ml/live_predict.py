"""
live_predict.py — 앉은 채로 지금 모델(posture_model_corrected)의 판정을 PC에서 실시간으로 본다 (저장 안 함)

앱을 거치지 않고 모델만 확인하는 도구. 0.5초마다 한 줄:
  판정 자세, 자세별 확률, 좌석·무릎·등받이 합, 등받이 비율·좌우
--save 를 주면 같은 화면을 보면서 원시값을 CSV 로도 남긴다 (모델이 틀릴 때 보내주면 원인 분석에 씀).

필요 패키지: numpy, pyserial   (텐서플로 필요 없음)
가중치: ml/posture_model_corrected_weights.npz  (posture_model_corrected.tflite 에서 뽑은 것, 값 동일)

사용 (Windows, 저장소 맨 위 폴더):
    python ml/live_predict.py --port COM8 --port-back COM7
    python ml/live_predict.py --port COM8 --port-back COM7 --save straight_check.csv
멈추기: Ctrl+C
"""
import argparse, os, sys, threading, time
import numpy as np
try:
    import serial
except ImportError:
    sys.exit("pyserial 이 없습니다.  pip install pyserial")

BAUD, N = 2_000_000, 32
LABELS = ["not_sitting", "sitting_straight", "lean_forward", "cross_leg_right",
          "cross_leg_left", "lean_right", "lean_left"]
KO = {"not_sitting": "앉지않음", "sitting_straight": "정자세", "lean_forward": "앞숙임",
      "cross_leg_right": "오른다리꼬기", "cross_leg_left": "왼다리꼬기",
      "lean_right": "오른기대기", "lean_left": "왼기대기"}
BACK_L = list(range(37, 42)) + list(range(49, 56)) + list(range(60, 64))
BACK_R = list(range(32, 37)) + list(range(42, 49)) + list(range(56, 60))
EMPTY_SUM = 300.0
FORWARD_BACK_SHARE = 0.015   # 앉아 있는데 등받이 비율이 이보다 작으면 앞숙임 (add_forward_guard.py 와 같음)

W = np.load(os.path.join(os.path.dirname(os.path.abspath(__file__)), "posture_model_corrected_weights.npz"))


def predict(x):
    """tflite 와 같은 계산 (Features -> Dense128 -> Dense64 -> softmax -> 앉음 판정 -> 등받이 안 닿으면 앞숙임)."""
    x = np.asarray(x, np.float32)
    t = x.sum()
    if t < EMPTY_SUM:
        p = np.zeros(7, np.float32); p[0] = 1; return p
    bl, br = x[BACK_L].sum(), x[BACK_R].sum(); b = bl + br
    kl, kr = x[24:28].sum(), x[28:32].sum()
    f = np.r_[x / max(t, 1), np.log1p(t) / 10, b / max(t, 1), bl / max(b, 1), kr / max(kl + kr, 1)]
    h = np.maximum(W["W1"] @ f + W["b1"], 0)
    h = np.maximum(W["W2"] @ h + W["b2"], 0)
    z = W["W3"] @ h + W["b3"]; p = np.exp(z - z.max()); p /= p.sum()
    p[0] = 0; p /= p.sum()
    if b / max(t, 1) < FORWARD_BACK_SHARE:
        p = np.zeros(7, np.float32); p[2] = 1
    return p


def parse(line):
    a = line.strip().split(",")
    if len(a) != N: return None
    try: return [int(v) for v in a]
    except ValueError: return None


class Reader(threading.Thread):
    def __init__(self, port):
        super().__init__(daemon=True)
        self.ser = serial.Serial(port, BAUD, timeout=1); self.latest = [0] * N; self.t = 0.0

    def run(self):
        while True:
            try: v = parse(self.ser.readline().decode("utf-8", errors="ignore"))
            except Exception: continue
            if v is not None: self.latest, self.t = v, time.time()


def main():
    ap = argparse.ArgumentParser(description="지금 모델 판정 실시간 확인")
    ap.add_argument("--port", required=True, help="좌석 보드 포트 (예: COM8)")
    ap.add_argument("--port-back", required=True, help="등받이 보드 포트 (예: COM7)")
    ap.add_argument("--save", help="원시값을 저장할 CSV 파일 이름 (선택)")
    args = ap.parse_args()
    seat, back = Reader(args.port), Reader(args.port_back); seat.start(); back.start()
    out = open(args.save, "w", encoding="utf-8") if args.save else None
    if out: out.write("time," + ",".join(f"ch{i}" for i in range(64)) + ",pred\n")
    print("앉아서 자세를 잡으세요. Ctrl+C 로 멈춥니다.\n")
    hist = []
    try:
        while True:
            time.sleep(0.5)
            if time.time() - seat.t > 1 or time.time() - back.t > 1:
                print("  (보드 데이터를 기다리는 중... 포트·연결 확인)"); continue
            x = np.array(seat.latest + back.latest, np.float32)
            p = predict(x); k = LABELS[int(p.argmax())]
            hist = (hist + [k])[-10:]
            sm = max(set(hist), key=hist.count)
            s, kn, b = x[:24].sum(), x[24:32].sum(), x[32:].sum()
            bl = x[BACK_L].sum()
            top = sorted(range(7), key=lambda i: -p[i])[:3]
            print(f"{KO[k]:7s} (5초 다수결 {KO[sm]}) | " + " ".join(f"{KO[LABELS[i]]} {p[i]*100:3.0f}%" for i in top)
                  + f" | 좌석{s:6.0f} 무릎{kn:5.0f} 등{b:6.0f} 등비율{100*b/max(x.sum(),1):4.0f}% 등왼{100*bl/max(b,1):4.0f}%")
            if out: out.write(f"{time.time():.2f}," + ",".join(str(int(v)) for v in x) + f",{k}\n"); out.flush()
    except KeyboardInterrupt:
        print("\n끝." + (f" 저장: {args.save}" if out else ""))
    finally:
        if out: out.close()


if __name__ == "__main__":
    main()
