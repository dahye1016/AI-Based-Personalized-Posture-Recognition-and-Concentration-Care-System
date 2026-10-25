"""방석 + 등받이 64채널 실측 수집 도구 (8자세, 2포트 동시 수신).

모드
  ports   연결된 시리얼 포트 목록 확인
  tap     센서를 손으로 눌러 어떤 채널이 반응하는지 실시간 확인 (등받이 채널 매핑용)
  record  자세 하나를 카운트다운 후 N초 기록해서 CSV 저장
  menu    8자세를 순서 섞어 연속 기록 (참가자 1명 분량)

포트 지정 (시리얼 소스)
  2포트  --seat-port COM3 --back-port COM4     방석 보드와 등받이 보드를 각각 연결 (권장)
  1포트  --port COM3                           한 줄에 64개(방석32+등받이32)가 들어오는 보드,
                                               또는 32개만 들어오는 등받이 단독 보드(--back-only)

  어느 보드가 어느 포트인지 모르겠으면:  python collect_back.py ports
  → 한 보드만 뽑았다 꽂으면서 목록이 어떻게 바뀌는지 보면 됩니다.

시리얼 형식: 2,000,000 baud, 한 줄 "v1,v2,...,v32\\n" (보드 하나당 32개).
   펌웨어 출력이 다르면 parse_line() 만 고치면 됩니다.

2포트 동기화
  두 보드의 시계가 서로 다르므로, PC 가 각 줄을 받은 시각을 기준으로
  --hz (기본 20) 간격마다 "방석 최신값 + 등받이 최신값"을 한 행으로 묶어 저장한다.
  어느 한쪽 값이 --max-age 초(기본 0.2)보다 오래됐으면 그 시점은 건너뛴다.
  저장 후 두 보드 도착 시각의 평균 차이(skew)를 알려준다.

저장 형식 (CSV 컬럼)  data/raw_back/<자세>/<사람>_<자세>_t<회차>_<시각>.csv
  timestamp,person,trial,posture,seat_0..seat_31,back_0..back_31
  → ml/prepare_chair_data.py 가 이 형식을 그대로 읽는다.

자세 (앱 순서 0~6과 동일, posture_names.py)
  not_sitting, sitting_straight, lean_forward, cross_leg_right,
  cross_leg_left, lean_right, lean_left

사용 예
  python collect_back.py ports
  python collect_back.py tap --seat-port COM3 --back-port COM4
  python collect_back.py record --posture sitting_straight --person aro --trial 1 --seat-port COM3 --back-port COM4
  python collect_back.py menu --person aro --repeat 3 --seat-port COM3 --back-port COM4
  python collect_back.py menu --person aro --source sim        # 하드웨어 없이 동작 확인
"""
import argparse
import csv
import os
import random
import sys
import threading
import time
from datetime import datetime

POSTURES = [
    "not_sitting",       # 0
    "sitting_straight",  # 1
    "lean_forward",      # 2
    "cross_leg_right",   # 3
    "cross_leg_left",    # 4
    "lean_right",        # 5
    "lean_left",         # 6
]

# 참가자에게 읽어 줄 자세 안내
GUIDE = {
    "not_sitting": "의자에서 완전히 일어나 있기 (방석·등받이 모두 닿지 않게)",
    "sitting_straight": "엉덩이를 깊이 넣고 등을 등받이에 편하게 붙인 바른 자세",
    "lean_forward": "상체를 앞으로 숙여서 등이 등받이에서 완전히 떨어지게 (등받이에 닿으면 안 됨)",
    "cross_leg_right": "오른다리를 왼다리 위로 꼬고, 등은 평소처럼",
    "cross_leg_left": "왼다리를 오른다리 위로 꼬고, 등은 평소처럼",
    "lean_right": "상체를 오른쪽으로 기대기 (몸이 오른쪽으로 쏠리게)",
    "lean_left": "상체를 왼쪽으로 기대기 (몸이 왼쪽으로 쏠리게)",
}

N_SEAT = 32
N_BACK = 32
HEADER = (
    ["timestamp", "person", "trial", "posture"]
    + [f"seat_{i}" for i in range(N_SEAT)]
    + [f"back_{i}" for i in range(N_BACK)]
)

# 등받이 줄 구분 — 팀 저장소 sensor_layout.dart 와 같은 10/14/8 구조 (back_i = 64ch 프레임의 ch32+i)
#   허리 줄 back_0~9 (ch32~41) / 중간 줄 back_10~23 (ch42~55) / 어깨 줄 back_24~31 (ch56~63)
BACK_WAIST = range(0, 10)
BACK_MID = range(10, 24)
BACK_SHOULDER = range(24, 32)
BACK_TORSO = list(BACK_WAIST) + list(BACK_MID)   # 어깨 줄을 뺀 등 부분
TOUCH_THRESHOLD = 20  # 기존 tap 모드와 같은 "반응 있음" 기준 (원시값)


def parse_line(line, back_only=False):
    """시리얼 한 줄 -> (seat[32], back[32]) 또는 None. (1포트 모드용)"""
    parts = [p.strip() for p in line.strip().split(",") if p.strip() != ""]
    try:
        vals = [float(p) for p in parts]
    except ValueError:
        return None
    if len(vals) == N_BACK and back_only:
        return [0.0] * N_SEAT, vals
    if len(vals) == N_SEAT + N_BACK:
        return vals[:N_SEAT], vals[N_SEAT:]
    return None


def parse_board_line(line):
    """보드 하나(32채널)의 한 줄 -> [32 float] 또는 None. (2포트 모드용)"""
    parts = [p.strip() for p in line.strip().split(",") if p.strip() != ""]
    if len(parts) != 32:
        return None
    try:
        return [float(p) for p in parts]
    except ValueError:
        return None


# ---------------------------------------------------------------------
# 입력 소스
# ---------------------------------------------------------------------
class SerialSource:
    """1포트: read() 가 (seat, back, t) 를 돌려준다."""

    def __init__(self, port, baud, back_only):
        import serial  # pip install pyserial

        self.ser = serial.Serial(port, baud, timeout=1)
        time.sleep(2)
        self.ser.reset_input_buffer()
        self.back_only = back_only

    def read(self):
        while True:
            raw = self.ser.readline().decode("utf-8", errors="ignore")
            if not raw:
                return None
            frame = parse_line(raw, self.back_only)
            if frame:
                return frame[0], frame[1], time.time()

    def reset(self):
        self.ser.reset_input_buffer()


class _BoardReader(threading.Thread):
    def __init__(self, port, baud, name):
        super().__init__(daemon=True)
        import serial

        self.name_ = name
        self.ser = serial.Serial(port, baud, timeout=1)
        self.lock = threading.Lock()
        self.latest = None      # (values, t_recv)
        self.count = 0
        self.dropped = 0
        self.running = True

    def run(self):
        while self.running:
            try:
                raw = self.ser.readline().decode("utf-8", errors="ignore")
            except Exception:
                time.sleep(0.05)
                continue
            if not raw:
                continue
            vals = parse_board_line(raw)
            if vals is None:
                self.dropped += 1
                continue
            with self.lock:
                self.latest = (vals, time.time())
                self.count += 1

    def get(self):
        with self.lock:
            return self.latest

    def stop(self):
        self.running = False


class DualSerialSource:
    """2포트: 방석 보드와 등받이 보드를 각각 읽는 스레드 두 개.
    read() 는 --hz 간격으로 (seat, back, t) 를 돌려주고, 두 값의 수신 시각 차이를 기록한다."""

    def __init__(self, seat_port, back_port, baud, hz=20.0, max_age=0.2):
        self.seat = _BoardReader(seat_port, baud, "seat")
        self.back = _BoardReader(back_port, baud, "back")
        time.sleep(2)  # 보드 리셋 대기
        self.seat.ser.reset_input_buffer()
        self.back.ser.reset_input_buffer()
        self.seat.start()
        self.back.start()
        self.period = 1.0 / hz
        self.max_age = max_age
        self._next = time.time()
        self.skews = []
        self.stale = 0

    def reset(self):
        self.skews = []
        self.stale = 0
        self._next = time.time()

    def read(self):
        now = time.time()
        wait = self._next - now
        if wait > 0:
            time.sleep(wait)
        self._next = max(self._next + self.period, time.time() - self.period)
        s, b = self.seat.get(), self.back.get()
        now = time.time()
        if s is None or b is None:
            return None
        if now - s[1] > self.max_age or now - b[1] > self.max_age:
            self.stale += 1
            return None
        self.skews.append(abs(s[1] - b[1]))
        return s[0], b[0], now


class SimSource:
    def __init__(self):
        self.t0 = time.time()

    def reset(self):
        pass

    def read(self):
        time.sleep(0.05)
        seat = [random.random() * 5 + (60 if i < 10 else 0) for i in range(N_SEAT)]
        back = [random.random() * 5 for _ in range(N_BACK)]
        k = int((time.time() - self.t0) * 2) % N_BACK
        back[k] += 200
        return seat, back, time.time()


def make_source(args):
    if args.source == "sim":
        return SimSource()
    if args.seat_port or args.back_port:
        if not (args.seat_port and args.back_port):
            sys.exit("2포트 모드는 --seat-port 와 --back-port 를 둘 다 줘야 합니다.")
        return DualSerialSource(args.seat_port, args.back_port, args.baud, args.hz, args.max_age)
    if not args.port:
        sys.exit("포트가 필요합니다: --seat-port COM3 --back-port COM4 (또는 --port COM3). "
                 "목록 확인: python collect_back.py ports")
    return SerialSource(args.port, args.baud, args.back_only)


# ---------------------------------------------------------------------
# 모드
# ---------------------------------------------------------------------
def cmd_ports(_args):
    try:
        from serial.tools import list_ports
    except ImportError:
        sys.exit("pyserial 이 없습니다.  pip install pyserial")
    ports = list(list_ports.comports())
    if not ports:
        print("시리얼 포트가 없습니다. 케이블(데이터 케이블인지)과 드라이버를 확인하세요.")
        return
    for p in ports:
        print(f"  {p.device:<8} {p.description}")
    print("\n보드를 하나씩 뽑았다 꽂아서 어느 포트가 방석/등받이인지 확인하세요.")


def cmd_tap(args):
    src = make_source(args)
    print("센서 한 칸씩 눌러보세요. 반응한 등받이 채널 상위 3개를 표시합니다. Ctrl+C 로 종료.")
    base = None
    try:
        while True:
            fr = src.read()
            if fr is None:
                continue
            back = fr[1]
            if base is None:
                base = back[:]
                print("baseline 저장 (지금은 센서에서 손을 떼세요)")
                continue
            diff = sorted(((back[i] - base[i], i) for i in range(N_BACK)), reverse=True)
            top = [(f"back_{i}", round(d, 1)) for d, i in diff[:3] if d > TOUCH_THRESHOLD]
            if top:
                print(top)
    except KeyboardInterrupt:
        print("종료")


def _mean(xs):
    xs = list(xs)
    return sum(xs) / len(xs) if xs else 0.0


def check_recording(posture, rows):
    """기록 직후 가설 기준으로 빠르게 점검. 어디까지나 참고용이다."""
    seat_all = [r[4:4 + N_SEAT] for r in rows]
    back_all = [r[4 + N_SEAT:] for r in rows]
    back_mean = _mean(_mean(b) for b in back_all)
    torso = _mean(_mean(b[i] for i in BACK_TORSO) for b in back_all)
    shoulder = _mean(_mean(b[i] for i in BACK_SHOULDER) for b in back_all)
    seat_mean = _mean(_mean(s) for s in seat_all)
    seat_zero = max(max(s) for s in seat_all) == 0
    print(f"  방석 평균 {seat_mean:.1f} | 등받이 평균 {back_mean:.1f} (허리·중간 {torso:.1f} / 어깨 {shoulder:.1f})")

    warns = []
    if posture == "not_sitting":
        mx = max(max(b) for b in back_all)
        if mx > TOUCH_THRESHOLD:
            warns.append(f"not_sitting 인데 등받이 최댓값이 {mx:.1f} (0 근처여야 함)")
    else:
        if seat_zero:
            warns.append("방석 값이 전부 0 — 방석 보드가 연결/수신되고 있는지 확인")
        if posture == "lean_forward" and back_mean > TOUCH_THRESHOLD:
            warns.append("앞으로 숙이기인데 등받이 값이 큼 — 등이 등받이에 닿았을 수 있음")
        if posture == "sitting_straight" and back_mean <= TOUCH_THRESHOLD:
            warns.append("정자세인데 등받이 값이 작음 — 등받이 센서 수신 확인")
    for w in warns:
        print(f"  ⚠️ {w}  → 다시 찍거나 파일명에 _reject 를 붙여 보관")
    return not warns


def record_one(src, args, posture, trial):
    out_dir = os.path.join(args.out, posture)
    os.makedirs(out_dir, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    path = os.path.join(out_dir, f"{args.person}_{posture}_t{trial}_{stamp}.csv")
    print(f"\n[{posture}] trial {trial}")
    print(f"  자세: {GUIDE[posture]}")
    print("  일어났다가 다시 앉아서 자세를 잡으세요.")
    for s in range(args.countdown, 0, -1):
        print(f"  {s}...", end="\r", flush=True)
        time.sleep(1)
    print(f"  기록 시작 ({args.seconds}초)    ")
    src.reset()
    rows = []
    end = time.time() + args.seconds
    while time.time() < end:
        fr = src.read()
        if fr is None:
            continue
        seat, back, t = fr
        rows.append([t, args.person, trial, posture] + seat + back)
    if not rows:
        print("  ⚠️ 프레임을 하나도 받지 못했습니다. 포트·보드 연결을 확인하세요. 저장하지 않습니다.")
        return None
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(HEADER)
        w.writerows(rows)
    print(f"  저장: {path} ({len(rows)}프레임)")
    if isinstance(src, DualSerialSource):
        sk = src.skews
        print(f"  두 보드 수신 시각 차이 평균 {_mean(sk) * 1000:.1f}ms / 최대 {max(sk) * 1000:.1f}ms, "
              f"건너뛴 시점 {src.stale}회")
        print(f"  버린 줄: 방석 {src.seat.dropped}, 등받이 {src.back.dropped}")
    check_recording(posture, rows)
    return path


def cmd_record(args):
    if args.posture not in POSTURES:
        sys.exit(f"posture 는 {POSTURES} 중 하나")
    src = make_source(args)
    record_one(src, args, args.posture, args.trial)


def cmd_menu(args):
    src = make_source(args)
    order = []
    for r in range(1, args.repeat + 1):
        batch = POSTURES[:]
        if not args.ordered:
            random.shuffle(batch)
        order += [(p, r) for p in batch]
    print(f"총 {len(order)}회 기록 예정 (참가자 {args.person}, 자세 {len(POSTURES)}종 x {args.repeat}회)")
    for posture, trial in order:
        input(f"\n준비되면 Enter -> 다음: {posture} (trial {trial})")
        record_one(src, args, posture, trial)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    ap.add_argument("mode", choices=["ports", "tap", "record", "menu"])
    ap.add_argument("--source", choices=["serial", "sim"], default="serial")
    ap.add_argument("--seat-port", help="방석 보드 포트 (예: COM3)")
    ap.add_argument("--back-port", help="등받이 보드 포트 (예: COM4)")
    ap.add_argument("--port", help="보드 하나만 쓸 때의 포트")
    ap.add_argument("--baud", type=int, default=2000000)
    ap.add_argument("--back-only", action="store_true", help="1포트 모드에서 한 줄에 등받이 32값만 들어오는 경우")
    ap.add_argument("--hz", type=float, default=20.0, help="2포트 모드의 저장 주기 (기본 20Hz)")
    ap.add_argument("--max-age", type=float, default=0.2, help="2포트 모드: 이보다 오래된 값은 건너뜀 (초)")
    ap.add_argument("--person", default="p1")
    ap.add_argument("--posture")
    ap.add_argument("--trial", type=int, default=1)
    ap.add_argument("--repeat", type=int, default=3)
    ap.add_argument("--ordered", action="store_true", help="menu 에서 자세 순서를 섞지 않고 고정 순서로")
    ap.add_argument("--seconds", type=int, default=10)
    ap.add_argument("--countdown", type=int, default=3)
    ap.add_argument("--out", default="data/raw_back")
    args = ap.parse_args()
    {"ports": cmd_ports, "tap": cmd_tap, "record": cmd_record, "menu": cmd_menu}[args.mode](args)


if __name__ == "__main__":
    main()
