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

필요 패키지: pyserial
"""

import argparse
import csv
import os
import sys
import time

try:
    import serial
    from serial.tools import list_ports
except ImportError:
    sys.exit("pyserial 이 없습니다.  pip install pyserial")

BAUD = 2_000_000
NUM_CHANNELS = 32
OUT_DIR = os.path.join("data", "raw")

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


def summarize(frames, dropped, all_zero, ch_sum, ch_max, actual, out_path, posture):
    print("\n" + "=" * 62)
    print(f"저장: {out_path}")
    print(f"총 프레임      : {frames}")
    print(f"실제 fps       : {frames / actual:.1f}  (수집 시간 {actual:.1f}s)")
    print(f"버린 줄        : {dropped}")

    if frames == 0:
        print("프레임을 하나도 못 받았습니다. baud/포트/펌웨어 출력을 확인해 주세요.")
        print("=" * 62)
        return

    zero_pct = all_zero / frames * 100
    print(f"전 채널 0 프레임: {all_zero} ({zero_pct:.1f}%)")
    if zero_pct > 50:
        print("  ⚠️ 절반 이상이 빈 프레임입니다. 아무도 안 앉았거나 배선 문제일 수 있습니다.")

    report_balance(ch_sum, posture)

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
    print("=" * 62)


def main():
    ap = argparse.ArgumentParser(description="32채널 매트 시리얼 수집기")
    ap.add_argument("--person", required=True, help="피험자 식별자 (예: yewon)")
    ap.add_argument("--posture", required=True,
                    help="자세 이름 문자열 (예: sitting_straight). 숫자 클래스 아님")
    ap.add_argument("--trial", required=True, type=int, help="시행 번호 (예: 1)")
    ap.add_argument("--duration", type=float, default=30.0, help="수집 시간(초), 기본 30")
    ap.add_argument("--port", default=None, help="시리얼 포트 직접 지정 (생략 시 자동 탐색)")
    args = ap.parse_args()

    port = choose_port(args.port)

    os.makedirs(OUT_DIR, exist_ok=True)
    out_path = os.path.join(OUT_DIR, f"{args.person}_{args.posture}_{args.trial}.csv")
    if os.path.exists(out_path):
        ans = input(f"\n{out_path} 이 이미 있습니다. 덮어쓸까요? [y/N] ").strip().lower()
        if ans != "y":
            sys.exit("취소했습니다. --trial 번호를 바꿔서 다시 실행해 주세요.")

    print(f"\n포트 {port} @ {BAUD} baud 로 연결합니다...")
    try:
        ser = serial.Serial(port, BAUD, timeout=1)
    except serial.SerialException as e:
        sys.exit(f"포트를 열지 못했습니다: {e}")

    time.sleep(2)  # 보드 리셋되는 경우가 있어 안정화 대기

    header = (["frame", "timestamp"]
              + [f"ch{i}" for i in range(NUM_CHANNELS)]
              + ["person", "posture", "trial"])

    try:
        with open(out_path, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(header)

            print(f"피험자 {args.person} / 자세 {args.posture} / 시행 {args.trial} "
                  f"/ {args.duration:.0f}초")
            countdown(3)
            result = collect(ser, args.duration, writer, args.person, args.posture, args.trial)
    except KeyboardInterrupt:
        print("\n\n사용자가 중단했습니다. 여기까지 받은 내용은 파일에 남아 있습니다.")
        return
    finally:
        ser.close()

    summarize(*result, out_path, args.posture)


if __name__ == "__main__":
    main()
