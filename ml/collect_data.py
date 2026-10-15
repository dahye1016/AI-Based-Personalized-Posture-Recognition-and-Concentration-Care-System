"""
collect_data.py — 32채널 방석 매트 실측 데이터 수집기 (시리얼 전용)

펌웨어가 2,000,000 baud 로 50fps 출력하는 "값1, 값2, ..., 값32\\n" 형식을 그대로 받아
data/raw/{person}_{posture}_{trial}.csv 로 저장한다.
(노이즈컷 raw<20 -> 0 은 펌웨어에서 이미 적용됨. 여기서는 가공하지 않는다.)

posture 는 숫자가 아니라 문자열로 받는다. 클래스 번호 체계가 나중에 바뀌어도
이미 모은 데이터가 죽지 않도록 하기 위한 것이다. 자세 목록은 코드에 하드코딩하지
않으므로 팀 합의 전에도 아무 이름으로 모을 수 있다.

사용 예:
    python collect_data.py --person yewon --posture sitting_straight --trial 1
    python collect_data.py --person yewon --posture cross_leg_right --trial 2 --duration 60
    python collect_data.py --person dahye --posture not_sitting --trial 1 --port /dev/cu.usbserial-0001

64채널 (좌석 + 등받이 보드 2대 동시 수집):
    python collect_data.py --person yewon --posture sitting_straight --trial 1 \\
        --port /dev/cu.usbmodem5C843561931 --port-back /dev/cu.usbmodem5C843561121

    좌석 ch0~31, 등받이 ch32~63 을 한 행으로 합쳐 data/raw_64ch/ 에 저장한다.
    (data/raw/ 는 32ch 전용 — 전처리·증강이 폴더째 읽으므로 섞지 않는다.)
    두 보드 시각은 안 맞지만 둘 다 PC 수신 시각으로 찍으므로 상관없다.
    병합 규칙:
      - 좌석 프레임이 올 때마다 한 행. 등받이는 그 시점까지 받은 최신 프레임을 붙인다.
      - 등받이 최신값이 100ms 보다 오래됐으면 그 행은 버린다. 0 으로 채우지 않는다
        (등받이 0 은 '등을 안 댐'이라는 진짜 신호라 끊김과 섞이면 안 된다).
      - 500ms 넘는 끊김은 요약에 경고로 남긴다.

필요 패키지: pyserial
"""

import argparse
import csv
import os
import queue
import sys
import threading
import time

try:
    import serial
    from serial.tools import list_ports
except ImportError:
    sys.exit("pyserial 이 없습니다.  pip install pyserial")

BAUD = 2_000_000
NUM_CHANNELS = 32
OUT_DIR = os.path.join("data", "raw")
OUT_DIR_64 = os.path.join("data", "raw_64ch")  # --port-back 사용 시 (64ch)

# 2포트 병합 기준 (초)
BACK_MAX_AGE = 0.1     # 등받이 최신값이 이보다 오래되면 그 행은 버린다
GAP_WARN = 0.5         # 이보다 긴 수신 공백은 끊김으로 보고한다
STALE_WARN_PCT = 5.0   # 버린 행이 이 비율을 넘으면 재촬영 권장

# 포트 이름에 이걸 포함하면 우선 추천 (macOS USB-시리얼 브리지 칩 계열)
PREFERRED = ("usbserial", "wchusbserial", "usbmodem", "SLAB_USBtoUART")

# 매트 좌표계 (실측 확정)
RIGHT_HIP = range(0, 5)
LEFT_HIP = range(5, 10)
RIGHT_THIGH = range(10, 17)
LEFT_THIGH = range(17, 24)
RIGHT_KNEE = range(24, 28)
LEFT_KNEE = range(28, 32)

RIGHT = list(RIGHT_HIP) + list(RIGHT_THIGH) + list(RIGHT_KNEE)
LEFT = list(LEFT_HIP) + list(LEFT_THIGH) + list(LEFT_KNEE)
HIP = list(RIGHT_HIP) + list(LEFT_HIP)          # 0~9
THIGH = list(RIGHT_THIGH) + list(LEFT_THIGH)    # 10~23
KNEE = list(RIGHT_KNEE) + list(LEFT_KNEE)       # 24~31

# 좌우 한쪽이 이 비율을 넘으면 치우쳐 앉은 것으로 본다
BALANCE_WARN = 65.0

# 이 접두사로 시작하는 자세는 좌우 불균형이 정상이라 경고를 띄우지 않는다.
# (자세 목록 자체는 하드코딩하지 않는다 — 접두사만 본다)
ASYMMETRIC_PREFIXES = ("lean_", "cross_leg_")


def list_serial_ports():
    """/dev/cu.* 계열만 추려서 (추천 우선) 정렬해 돌려준다."""
    ports = [p for p in list_ports.comports() if "/dev/cu." in p.device]
    ports.sort(key=lambda p: (not any(k in p.device for k in PREFERRED), p.device))
    return ports


def choose_port(explicit: str | None) -> str:
    """포트를 고른다. --port 로 직접 준 경우 그대로 사용."""
    if explicit:
        return explicit

    ports = list_serial_ports()
    if not ports:
        sys.exit("시리얼 포트를 못 찾았습니다. 보드가 연결돼 있는지, 케이블이 "
                 "데이터 케이블인지 확인해 주세요.")

    print("\n사용 가능한 시리얼 포트:")
    for i, p in enumerate(ports):
        star = " ←추천" if any(k in p.device for k in PREFERRED) else ""
        print(f"  [{i}] {p.device}  ({p.description}){star}")

    if len(ports) == 1:
        print(f"\n하나뿐이라 자동 선택: {ports[0].device}")
        return ports[0].device

    while True:
        raw = input(f"\n번호 선택 [0-{len(ports) - 1}], 종료는 q: ").strip()
        if raw.lower() == "q":
            sys.exit("종료했습니다.")
        if raw.isdigit() and 0 <= int(raw) < len(ports):
            return ports[int(raw)].device
        print("  다시 입력해 주세요. (종료하려면 q)")


def parse_line(line: str):
    """'값1, 값2, ... 값32' -> [int] * 32. 형식이 어긋나면 None."""
    parts = line.strip().split(",")
    if len(parts) != NUM_CHANNELS:
        return None
    try:
        return [int(p) for p in parts]
    except ValueError:
        return None


def countdown(seconds: int = 3):
    print("\n자세를 잡아 주세요.")
    for i in range(seconds, 0, -1):
        print(f"  {i}...", flush=True)
        time.sleep(1)
    print("  수집 시작!\n")


def collect(ser, duration: float, writer, person: str, posture: str, trial: int):
    """duration 초 동안 읽어서 writer 에 기록. (frames, dropped, 채널합계들) 반환."""
    frames = 0
    dropped = 0
    all_zero = 0
    ch_sum = [0] * NUM_CHANNELS
    ch_max = [0] * NUM_CHANNELS

    ser.reset_input_buffer()  # 버퍼에 쌓여 있던 옛 프레임 버리고 시작
    start = time.time()
    last_print = 0.0

    while True:
        elapsed = time.time() - start
        if elapsed >= duration:
            break

        try:
            line = ser.readline().decode("utf-8", errors="ignore")
        except serial.SerialException as e:
            print(f"\n시리얼 오류로 중단: {e}")
            break
        if not line:
            continue

        values = parse_line(line)
        if values is None:
            dropped += 1
            continue

        ts = time.time()
        writer.writerow([frames, f"{ts:.6f}"] + values + [person, posture, trial])

        frames += 1
        if not any(values):
            all_zero += 1
        for i, v in enumerate(values):
            ch_sum[i] += v
            if v > ch_max[i]:
                ch_max[i] = v

        if elapsed - last_print >= 0.5:
            last_print = elapsed
            print(f"\r  남은 시간 {duration - elapsed:5.1f}s | 프레임 {frames:5d} "
                  f"| 버림 {dropped:4d}", end="", flush=True)

    actual = time.time() - start
    print()
    return frames, dropped, all_zero, ch_sum, ch_max, actual


def _reader(ser, tag, q, stop):
    """한 포트를 계속 읽어 (태그, PC 수신 시각, 값 또는 None) 을 큐에 넣는다."""
    while not stop.is_set():
        try:
            line = ser.readline().decode("utf-8", errors="ignore")
        except Exception as e:  # 포트 닫힘·분리 등
            if not stop.is_set():
                q.put((tag, time.time(), e))
            return
        if line:
            q.put((tag, time.time(), parse_line(line)))


def collect_dual(ser, ser_back, duration: float, writer,
                 person: str, posture: str, trial: int):
    """좌석·등받이 두 포트를 동시에 읽어 64ch 한 행으로 기록한다.

    좌석 프레임 기준으로 행을 만들고, 등받이는 최신값을 붙인다.
    반환은 collect() 와 같은 6개 + 보드별 정보(back).
    """
    frames = 0
    dropped = 0
    all_zero = 0              # 좌석 ch0~31 이 전부 0 인 행 (기존 의미 유지)
    ch_sum = [0] * (NUM_CHANNELS * 2)
    ch_max = [0] * (NUM_CHANNELS * 2)
    back = {
        "seat_frames": 0, "back_frames": 0,
        "seat_dropped": 0, "back_dropped": 0,
        "stale": 0, "back_all_zero": 0,
        "gaps": {"seat": [], "back": []},   # (시작 초, 길이 초)
    }
    last_seen = {"seat": None, "back": None}
    latest_back = None  # (수신 시각, values)

    q = queue.Queue()
    stop = threading.Event()
    ser.reset_input_buffer()
    ser_back.reset_input_buffer()
    threads = [threading.Thread(target=_reader, args=(s, tag, q, stop), daemon=True)
               for s, tag in ((ser, "seat"), (ser_back, "back"))]

    start = time.time()
    last_print = 0.0
    for t in threads:
        t.start()

    try:
        while True:
            elapsed = time.time() - start
            if elapsed >= duration:
                break

            try:
                tag, ts, values = q.get(timeout=0.1)
            except queue.Empty:
                continue
            if isinstance(values, Exception):
                print(f"\n{'좌석' if tag == 'seat' else '등받이'} 시리얼 오류로 중단: {values}")
                break
            if values is None:
                back[f"{tag}_dropped"] += 1
                dropped += 1
                continue

            prev = last_seen[tag]
            if prev is not None and ts - prev > GAP_WARN:
                back["gaps"][tag].append((prev - start, ts - prev))
            last_seen[tag] = ts

            if tag == "back":
                back["back_frames"] += 1
                latest_back = (ts, values)
                continue

            back["seat_frames"] += 1
            if latest_back is None or ts - latest_back[0] > BACK_MAX_AGE:
                back["stale"] += 1
                continue

            row = values + latest_back[1]
            writer.writerow([frames, f"{ts:.6f}"] + row + [person, posture, trial])

            frames += 1
            if not any(values):
                all_zero += 1
            if not any(latest_back[1]):
                back["back_all_zero"] += 1
            for i, v in enumerate(row):
                ch_sum[i] += v
                if v > ch_max[i]:
                    ch_max[i] = v

            if elapsed - last_print >= 0.5:
                last_print = elapsed
                print(f"\r  남은 시간 {duration - elapsed:5.1f}s | 행 {frames:5d} "
                      f"| 버림 {dropped:4d} | 등받이 늦음 {back['stale']:4d}",
                      end="", flush=True)
    finally:
        stop.set()

    end = time.time()
    # 끝까지 안 들어온 꼬리 구간도 끊김으로 본다
    for tag in ("seat", "back"):
        prev = last_seen[tag]
        if prev is None:
            back["gaps"][tag].append((0.0, end - start))
        elif end - prev > GAP_WARN:
            back["gaps"][tag].append((prev - start, end - prev))

    actual = end - start
    print()
    return frames, dropped, all_zero, ch_sum, ch_max, actual, back


def zone_sum(ch_sum, idx):
    return sum(ch_sum[i] for i in idx)


def report_balance(ch_sum, posture: str):
    """좌우 균형과 앞뒤 분포를 출력한다. 값 자체는 가공하지 않는다."""
    total = sum(ch_sum)
    if total <= 0:
        print("\n[좌우 균형 / 앞뒤 분포] 압력이 전혀 없어 계산할 수 없습니다.")
        return

    left = zone_sum(ch_sum, LEFT)
    right = zone_sum(ch_sum, RIGHT)
    left_pct = left / total * 100
    right_pct = right / total * 100

    print(f"\n[좌우 균형]  좌 {left_pct:.1f}%  /  우 {right_pct:.1f}%")

    exempt = posture.startswith(ASYMMETRIC_PREFIXES)
    if exempt:
        print(f"  ('{posture}' 는 불균형이 정상인 자세라 경고를 띄우지 않습니다)")
    elif max(left_pct, right_pct) > BALANCE_WARN:
        side = "왼쪽" if left_pct > right_pct else "오른쪽"
        print(f"  ⚠️ {side}으로 치우쳐 앉았을 수 있음. 재촬영 권장 "
              f"(한쪽 {max(left_pct, right_pct):.1f}% > {BALANCE_WARN:.0f}%)")

    hip_pct = zone_sum(ch_sum, HIP) / total * 100
    thigh_pct = zone_sum(ch_sum, THIGH) / total * 100
    knee_pct = zone_sum(ch_sum, KNEE) / total * 100
    print(f"[앞뒤 분포]  엉덩이 {hip_pct:.1f}%  /  허벅지 {thigh_pct:.1f}%  "
          f"/  무릎 {knee_pct:.1f}%")


def report_boards(frames, ch_sum, actual, back):
    """64ch 전용: 보드별 수신 fps, 버린 행, 끊김, 좌석:등받이 압력 비율."""
    print("\n[보드별 수신]")
    print(f"  좌석   : {back['seat_frames']:5d} 프레임 ({back['seat_frames'] / actual:5.1f} fps)"
          f"  파싱 실패 {back['seat_dropped']}")
    print(f"  등받이 : {back['back_frames']:5d} 프레임 ({back['back_frames'] / actual:5.1f} fps)"
          f"  파싱 실패 {back['back_dropped']}")
    seat_n = back["seat_frames"]
    stale_pct = back["stale"] / seat_n * 100 if seat_n else 0.0
    print(f"  저장 행: {frames:5d} 행     ({frames / actual:5.1f} fps)"
          f"  버린 행(등받이 {BACK_MAX_AGE * 1000:.0f}ms 초과) {back['stale']} ({stale_pct:.1f}%)")
    if stale_pct > STALE_WARN_PCT:
        print(f"  ⚠️ 버린 행이 {STALE_WARN_PCT:.0f}% 를 넘습니다. 등받이 연결 확인 후 재촬영 권장")

    for tag, name in (("seat", "좌석"), ("back", "등받이")):
        gaps = back["gaps"][tag]
        if gaps:
            s, longest = max(gaps, key=lambda g: g[1])
            print(f"  ⚠️ {name} {GAP_WARN * 1000:.0f}ms 넘는 끊김 {len(gaps)}건 "
                  f"(최장 {longest:.2f}s, {s:.1f}s 지점)")

    if frames == 0:
        return

    seat_total = sum(ch_sum[:NUM_CHANNELS])
    back_total = sum(ch_sum[NUM_CHANNELS:])
    both = seat_total + back_total
    if both > 0:
        print(f"\n[좌석 : 등받이 압력]  좌석 {seat_total / both * 100:.1f}%  "
              f"/  등받이 {back_total / both * 100:.1f}%")
        if back_total > seat_total:
            print("  ⚠️ 등받이 압력이 좌석보다 큽니다. --port / --port-back 이 "
                  "바뀌었을 수 있으니 확인해 주세요.")
    back_zero_pct = back["back_all_zero"] / frames * 100
    print(f"등받이 전 채널 0 행: {back['back_all_zero']} ({back_zero_pct:.1f}%)  "
          f"(등을 안 댄 시간 비율)")


def report_back_channels(frames, ch_sum, ch_max):
    """64ch 전용: 등받이 ch32~63 평균·최대와 죽은 채널."""
    print("\n[등받이 채널별 평균 / 최대]  (평균·최대가 모두 0이면 죽은 채널 의심)")
    dead = []
    for i in range(NUM_CHANNELS, NUM_CHANNELS * 2):
        avg = ch_sum[i] / frames
        mark = ""
        if ch_max[i] == 0:
            dead.append(i)
            mark = "  ← 죽은 채널?"
        print(f"  ch{i:02d}  평균 {avg:8.1f}  최대 {ch_max[i]:5d}{mark}")

    if dead:
        print(f"\n⚠️ 한 번도 값이 안 잡힌 등받이 채널 {len(dead)}개: {dead}")


def summarize(frames, dropped, all_zero, ch_sum, ch_max, actual, out_path, posture,
              back=None):
    print("\n" + "=" * 62)
    print(f"저장: {out_path}")
    print(f"총 프레임      : {frames}")
    print(f"실제 fps       : {frames / actual:.1f}  (수집 시간 {actual:.1f}s)")
    print(f"버린 줄        : {dropped}")
    if back is not None:
        report_boards(frames, ch_sum, actual, back)

    if frames == 0:
        print("프레임을 하나도 못 받았습니다. baud/포트/펌웨어 출력을 확인해 주세요.")
        print("=" * 62)
        return

    zero_pct = all_zero / frames * 100
    print(f"전 채널 0 프레임: {all_zero} ({zero_pct:.1f}%)")
    if zero_pct > 50:
        print("  ⚠️ 절반 이상이 빈 프레임입니다. 아무도 안 앉았거나 배선 문제일 수 있습니다.")

    report_balance(ch_sum[:NUM_CHANNELS], posture)  # 좌우·앞뒤는 좌석 기준

    print("\n[채널별 평균 / 최대]  (평균·최대가 모두 0이면 죽은 채널 의심)")
    dead = []
    for i in range(NUM_CHANNELS):
        avg = ch_sum[i] / frames
        mark = ""
        if ch_max[i] == 0:
            dead.append(i)
            mark = "  ← 죽은 채널?"
        print(f"  ch{i:02d}  평균 {avg:8.1f}  최대 {ch_max[i]:5d}{mark}")

    if dead:
        print(f"\n⚠️ 한 번도 값이 안 잡힌 채널 {len(dead)}개: {dead}")
    if back is not None:
        report_back_channels(frames, ch_sum, ch_max)
    print("=" * 62)


def main():
    ap = argparse.ArgumentParser(description="32채널 매트 시리얼 수집기 (--port-back 시 64채널)")
    ap.add_argument("--person", required=True, help="피험자 식별자 (예: yewon)")
    ap.add_argument("--posture", required=True,
                    help="자세 이름 문자열 (예: sitting_straight). 숫자 클래스 아님")
    ap.add_argument("--trial", required=True, type=int, help="시행 번호 (예: 1)")
    ap.add_argument("--duration", type=float, default=30.0, help="수집 시간(초), 기본 30")
    ap.add_argument("--port", default=None, help="시리얼 포트 직접 지정 (생략 시 자동 탐색)")
    ap.add_argument("--port-back", default=None,
                    help="등받이 보드 포트. 주면 좌석+등받이 64ch 로 data/raw_64ch/ 에 저장")
    args = ap.parse_args()

    port = choose_port(args.port)
    port_back = args.port_back
    if port_back is not None and port_back == port:
        sys.exit("--port 와 --port-back 이 같습니다. 좌석·등받이 포트를 각각 지정해 주세요.")

    out_dir = OUT_DIR_64 if port_back else OUT_DIR
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, f"{args.person}_{args.posture}_{args.trial}.csv")
    if os.path.exists(out_path):
        ans = input(f"\n{out_path} 이 이미 있습니다. 덮어쓸까요? [y/N] ").strip().lower()
        if ans != "y":
            sys.exit("취소했습니다. --trial 번호를 바꿔서 다시 실행해 주세요.")

    print(f"\n포트 {port} @ {BAUD} baud 로 연결합니다...")
    try:
        ser = serial.Serial(port, BAUD, timeout=1)
    except serial.SerialException as e:
        sys.exit(f"포트를 열지 못했습니다: {e}")

    ser_back = None
    if port_back:
        print(f"등받이 포트 {port_back} @ {BAUD} baud 로 연결합니다...")
        try:
            ser_back = serial.Serial(port_back, BAUD, timeout=1)
        except serial.SerialException as e:
            ser.close()
            sys.exit(f"등받이 포트를 열지 못했습니다: {e}")

    time.sleep(2)  # 보드 리셋되는 경우가 있어 안정화 대기

    n_ch = NUM_CHANNELS * 2 if ser_back else NUM_CHANNELS
    header = (["frame", "timestamp"]
              + [f"ch{i}" for i in range(n_ch)]
              + ["person", "posture", "trial"])

    try:
        with open(out_path, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(header)

            print(f"피험자 {args.person} / 자세 {args.posture} / 시행 {args.trial} "
                  f"/ {args.duration:.0f}초")
            countdown(3)
            if ser_back:
                *result, back = collect_dual(ser, ser_back, args.duration, writer,
                                             args.person, args.posture, args.trial)
            else:
                result = collect(ser, args.duration, writer, args.person, args.posture, args.trial)
                back = None
    except KeyboardInterrupt:
        print("\n\n사용자가 중단했습니다. 여기까지 받은 내용은 파일에 남아 있습니다.")
        return
    finally:
        ser.close()
        if ser_back:
            ser_back.close()

    summarize(*result, out_path, args.posture, back=back)


if __name__ == "__main__":
    main()
