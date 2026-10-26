"""
live_check.py — 앉은 채로 좌석·등받이 압력을 실시간으로 보는 확인용 도구 (저장 안 함)

매트 위치를 맞출 때 쓴다. 0.5초마다 아래를 한 줄씩 보여준다.
  - 좌석 좌우 비율, 등받이 좌우 비율, 등받이가 전체에서 차지하는 비율
  - 등받이 줄(허리/중간/어깨)별 좌우 합

채널 좌우 기준은 lib/models/sensor_layout.dart 와 같다.
  좌석  : 왼쪽 0~4, 10~16, 24~27 / 오른쪽 5~9, 17~23, 28~31
  등받이: 오른쪽 32~36, 42~48, 56~59 / 왼쪽 37~41, 49~55, 60~63  (중간 줄 42~55 는 추정)

목표 (학습 데이터의 정자세와 비슷한 상태):
  - 등받이 비율 10~30%
  - 등받이 좌우 각각 30% 이상 (한쪽이 0 이면 매트가 치우쳤거나 들뜬 것)

사용 (Windows):
    python ml/live_check.py --port COM8 --port-back COM7
멈추기: Ctrl+C
필요 패키지: pyserial
"""
import argparse
import sys
import threading
import time

try:
    import serial
except ImportError:
    sys.exit("pyserial 이 없습니다.  pip install pyserial")

BAUD = 2_000_000
N = 32

SEAT_L = list(range(0, 5)) + list(range(10, 17)) + list(range(24, 28))
SEAT_R = list(range(5, 10)) + list(range(17, 24)) + list(range(28, 32))
# 등받이 보드 기준 번호(0~31) = 64ch 번호 - 32
BACK_ROWS = {
    "허리": (list(range(0, 5)), list(range(5, 10))),     # (오른쪽, 왼쪽) = ch32~36 / ch37~41
    "중간": (list(range(10, 17)), list(range(17, 24))),  # ch42~48 / ch49~55 (추정)
    "어깨": (list(range(24, 28)), list(range(28, 32))),  # ch56~59 / ch60~63
}


def parse_line(line):
    parts = line.strip().split(",")
    if len(parts) != N:
        return None
    try:
        return [int(p) for p in parts]
    except ValueError:
        return None


class Reader(threading.Thread):
    """보드 하나에서 최신 프레임을 계속 읽어 둔다."""

    def __init__(self, port):
        super().__init__(daemon=True)
        self.ser = serial.Serial(port, BAUD, timeout=1)
        self.latest = [0] * N
        self.t = 0.0

    def run(self):
        while True:
            try:
                v = parse_line(self.ser.readline().decode("utf-8", errors="ignore"))
            except Exception:
                continue
            if v is not None:
                self.latest, self.t = v, time.time()


def pct(a, b):
    return 100.0 * a / b if b > 0 else 0.0


def bar(p, width=20):
    n = int(round(p / 100 * width))
    return "#" * n + "." * (width - n)


def main():
    ap = argparse.ArgumentParser(description="좌석·등받이 압력 실시간 확인")
    ap.add_argument("--port", required=True, help="좌석 보드 포트 (예: COM8)")
    ap.add_argument("--port-back", required=True, help="등받이 보드 포트 (예: COM7)")
    args = ap.parse_args()

    seat, back = Reader(args.port), Reader(args.port_back)
    seat.start(); back.start()
    print("앉아서 바른 자세를 잡으세요. Ctrl+C 로 멈춥니다.\n")
    try:
        while True:
            time.sleep(0.5)
            now = time.time()
            if now - seat.t > 1 or now - back.t > 1:
                print("  (보드 데이터를 기다리는 중... 포트·연결 확인)")
                continue
            s, b = seat.latest, back.latest
            sl, sr = sum(s[i] for i in SEAT_L), sum(s[i] for i in SEAT_R)
            rows = {k: (sum(b[i] for i in r), sum(b[i] for i in l)) for k, (r, l) in BACK_ROWS.items()}
            br = sum(v[0] for v in rows.values()); bl = sum(v[1] for v in rows.values())
            total = sl + sr + bl + br
            back_share = pct(bl + br, total)
            back_left = pct(bl, bl + br)
            ok = "OK" if 10 <= back_share <= 35 and 30 <= back_left <= 70 else "조정 필요"
            print(f"좌석 왼{pct(sl, sl + sr):5.1f}% | 등받이 비율 {back_share:5.1f}% | "
                  f"등받이 왼 {back_left:5.1f}% [{bar(back_left)}] 오 | "
                  + "  ".join(f"{k} 오{r:5d}/왼{l:5d}" for k, (r, l) in rows.items())
                  + f"  -> {ok}")
    except KeyboardInterrupt:
        print("\n끝.")


if __name__ == "__main__":
    main()
