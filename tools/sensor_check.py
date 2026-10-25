"""
방석 FSR 센서 점검: 시리얼로 N초 동안 읽고 채널별 압력을 보여줍니다.

사용법:
    pip install pyserial
    python tools/sensor_check.py                 # 포트 자동 탐색, 15초
    python tools/sensor_check.py --port /dev/cu.usbserial-0001
    python tools/sensor_check.py --port COM3 --seconds 30
    python tools/sensor_check.py --port COM7 --baud 2000000   # PoseLab 32ch 매트

이해하는 출력 형식 (레포의 펌웨어 3종 모두):
    120,0,845,33                        (fsr_serial_check / fsr_ble 의 "전송: ...")
    {"sensor_1":120,"sensor_2":0,...}   (firmware/posture_sensor_esp32)
    센서값: 845                          (fsr_test, 1채널)
"""
import argparse
import json
import os
import re
import sys
import time

try:
    import serial
    from serial.tools import list_ports
except ImportError:
    sys.exit("pyserial 이 필요합니다:  pip install pyserial")

BAR_WIDTH = 30
NUMBER_LINE = re.compile(r"^-?\d+(\s*,\s*-?\d+)*$")


def find_port():
    ports = list(list_ports.comports())
    keywords = ("usbserial", "usbmodem", "SLAB", "wchusb", "ttyUSB", "ttyACM", "CP210", "CH340", "USB")
    for p in ports:
        text = f"{p.device} {p.description} {p.hwid}"
        if any(k.lower() in text.lower() for k in keywords):
            return p.device
    if ports:
        return ports[0].device
    sys.exit("시리얼 포트를 못 찾았습니다. USB 연결을 확인하거나 --port 로 지정하세요.")


def parse_line(line):
    """한 줄에서 채널 값 리스트를 뽑습니다. 센서 데이터가 아니면 None."""
    line = line.strip()
    if not line:
        return None
    # JSON 형식 {"sensor_1": ...}
    start = line.find("{")
    if start != -1:
        try:
            obj = json.loads(line[start:line.rfind("}") + 1])
            keys = sorted((k for k in obj if k.startswith("sensor_")),
                          key=lambda k: int(k.split("_")[1]))
            if keys:
                return [int(obj[k]) for k in keys]
        except (ValueError, TypeError):
            pass
        return None
    # "전송: 1,2,3" / "센서값: 845" 처럼 앞에 글자가 붙은 경우
    if ":" in line:
        line = line.split(":", 1)[1].strip()
    if NUMBER_LINE.match(line):
        return [int(v) for v in line.split(",")]
    return None


def bar(value, vmax):
    filled = int(round(BAR_WIDTH * min(value, vmax) / vmax)) if vmax else 0
    return "█" * filled + "·" * (BAR_WIDTH - filled)


def main():
    ap = argparse.ArgumentParser(description="방석 FSR 센서 채널별 압력 확인")
    ap.add_argument("--port", help="시리얼 포트 (생략하면 자동 탐색)")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--seconds", type=float, default=15)
    ap.add_argument("--max", type=int, default=4095,
                    help="막대 그래프 최대값 (ESP32 원시값 4095, 서버 전송값이면 1023)")
    ap.add_argument("--csv", help="측정값을 저장할 CSV 경로 (선택)")
    args = ap.parse_args()
    if os.name == "nt":
        os.system("")  # 윈도우 콘솔에서 화면 덮어쓰기(ANSI) 켜기

    port = args.port or find_port()
    print(f"포트 {port} @ {args.baud} 연결 중...")
    ser = serial.Serial()
    ser.port, ser.baudrate, ser.timeout = port, args.baud, 0.2
    # 윈도우에서 DTR/RTS가 켜진 채 열리면 ESP32가 리셋 상태로 멈춰 아무것도 안 보냄
    ser.dtr = False
    ser.rts = False
    ser.open()
    time.sleep(1.5)
    ser.reset_input_buffer()

    samples = []      # (경과초, [값...])
    others = []       # 센서값이 아닌 줄 (로그 확인용)
    start = time.time()
    shown_lines = 0
    total_bytes = 0
    last_draw = -1.0
    print(f"{args.seconds:.0f}초 동안 측정합니다. 방석에 앉았다 일어났다 해보세요.\n")

    try:
        while (elapsed := time.time() - start) < args.seconds:
            chunk = ser.readline()
            total_bytes += len(chunk)
            raw = chunk.decode("utf-8", errors="replace")
            if not raw:
                continue
            values = parse_line(raw)
            if values is None:
                if raw.strip():
                    others.append(raw.strip())
                continue
            samples.append((elapsed, values))
            # 화면은 초당 10번만 갱신 (50fps 보드도 버벅이지 않게)
            if elapsed - last_draw < 0.1:
                continue
            last_draw = elapsed

            # 실시간 표시 (이전 출력 위에 덮어쓰기)
            if shown_lines:
                sys.stdout.write(f"\x1b[{shown_lines}A")
            out = [f"  {elapsed:5.1f}s / {args.seconds:.0f}s   샘플 {len(samples)}개"]
            for i, v in enumerate(values):
                out.append(f"  CH{i + 1:<2} {v:5d} {bar(v, args.max)}")
            sys.stdout.write("\n".join(line + "\x1b[K" for line in out) + "\n")
            sys.stdout.flush()
            shown_lines = len(out)
    except KeyboardInterrupt:
        print("\n중단됨")
    finally:
        ser.close()

    print()
    if not samples:
        print(f"센서 데이터를 한 줄도 못 받았습니다. (받은 바이트: {total_bytes})")
        print("연결된 포트 목록:")
        for p in list_ports.comports():
            print(f"    {p.device:<8} {p.description}")
        if others:
            print("대신 받은 출력 (마지막 5줄):")
            for o in others[-5:]:
                print("   ", o)
            print("→ fsr_ble 펌웨어는 BLE 연결 전엔 값을 안 보냅니다. "
                  "arduino/fsr_serial_check 스케치를 올려서 다시 해보세요.")
        else:
            print("→ 위 목록에서 ESP32(CP210x / CH340 / USB-SERIAL) 포트로 --port 지정,")
            print("  보드의 EN(RST) 버튼을 한 번 눌러보고, 시리얼 모니터가 열려있으면 닫으세요.")
            print("  보드에 fsr_ble 펌웨어가 올라가 있으면 BLE 연결 전엔 값을 안 보냅니다")
            print("  → arduino/fsr_serial_check 스케치를 올리세요.")
        return

    n_ch = max(len(v) for _, v in samples)
    duration = samples[-1][0] - samples[0][0]
    rate = (len(samples) - 1) / duration if duration > 0 else 0
    print(f"=== 결과: {len(samples)}개 샘플, {duration:.1f}초, 약 {rate:.1f}Hz ===")
    print(f"  {'채널':<5}{'최소':>7}{'평균':>8}{'최대':>7}{'변화폭':>8}   상태")
    for ch in range(n_ch):
        vals = [v[ch] for _, v in samples if len(v) > ch]
        lo, hi, avg = min(vals), max(vals), sum(vals) / len(vals)
        span = hi - lo
        if hi == 0:
            status = "항상 0 → 배선/센서 확인"
        elif lo >= args.max * 0.98:
            status = "항상 최대 → 단락/풀업 확인"
        elif span < args.max * 0.02:
            status = "거의 안 변함 → 눌러도 반응 없는지 확인"
        else:
            status = "OK (반응함)"
        print(f"  CH{ch + 1:<3}{lo:>7}{avg:>8.0f}{hi:>7}{span:>8}   {status}")

    if args.csv:
        with open(args.csv, "w", encoding="utf-8") as f:
            f.write("time_s," + ",".join(f"ch{i + 1}" for i in range(n_ch)) + "\n")
            for t, v in samples:
                f.write(f"{t:.3f}," + ",".join(map(str, v)) + "\n")
        print(f"\nCSV 저장: {args.csv}")


if __name__ == "__main__":
    main()
