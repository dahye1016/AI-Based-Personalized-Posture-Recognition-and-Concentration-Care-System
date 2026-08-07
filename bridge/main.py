"""
PoseLab Seat 브리지 — Core 보드(USB Serial) 와 FastAPI 서버를 연결합니다.

★ 왜 이게 필요한가
   방석센서 Core 보드는 USB 로 'PC' 에 붙습니다. 폰에 직접 안 붙습니다.
   그래서 기존의 [ESP32 -> BLE -> 폰] 구조는 성립하지 않고,
   [Core -> USB -> PC(이 브리지) -> 서버 -> 폰] 이 되어야 합니다.

사용법
------
  # 1) 센서 없이 개발 (지금 이 상태)
  python main.py --mock                    # 정자세 고정
  python main.py --mock --posture 오른다리꼬기
  python main.py --mock --auto             # 자세가 저절로 바뀜

  # 2) 실물 센서 연결 (일요일)
  python main.py --port auto               # 포트 자동 탐색
  python main.py --port COM5               # 윈도우
  python main.py --port /dev/ttyACM0       # 리눅스/맥

  # 3) 자세 등록(캘리브레이션) — 앱 '초기 설정' 화면과 같은 동작
  python main.py --port auto --calibrate 정자세 --seconds 3

옵션
----
  --server   서버 주소 (기본 http://127.0.0.1:8000)
  --hz       서버로 보내는 빈도 (기본 2Hz). 센서는 훨씬 빠르게 오지만
             그걸 다 저장하면 DB가 터지므로 여기서 평균내어 줄입니다.
  --raw      들어온 프레임을 콘솔에 그대로 출력 (배선 확인용)
"""

import argparse
import sys
import time
from typing import List, Optional

import features
import mock_source
import protocol
from layout import N_CHANNELS

try:
    import requests
except ImportError:
    requests = None


# ---------------------------------------------------------------- 시리얼 소스
class SerialSource:
    """실제 Core 보드에서 프레임을 읽는 소스."""

    def __init__(self, port: str, baudrate: int = protocol.BAUDRATE):
        try:
            import serial
        except ImportError:
            sys.exit("pyserial 이 없습니다.  pip install pyserial")

        resolved = protocol.find_port(None if port == "auto" else port)
        if not resolved:
            sys.exit("시리얼 포트를 찾지 못했습니다. USB 케이블과 드라이버를 확인하세요.")

        self.ser = serial.Serial(resolved, baudrate, timeout=1)
        print(f"[serial] {resolved} @ {baudrate} 연결됨")

        time.sleep(0.3)
        sample = self.ser.read(2048)
        self.parser = protocol.sniff(sample)
        print(f"[serial] 프로토콜 자동판별: {self.parser.name}")

        self._pending: List[List[int]] = list(self.parser.feed(sample))

    def read_frame(self) -> Optional[List[int]]:
        while not self._pending:
            chunk = self.ser.read(4096)
            if not chunk:
                return None
            self._pending.extend(self.parser.feed(chunk))
        return self._pending.pop(0)

    def close(self):
        self.ser.close()


# ---------------------------------------------------------------- 서버 전송
def post(server: str, path: str, payload: dict) -> Optional[dict]:
    if requests is None:
        print("[warn] requests 미설치 — 전송 생략")
        return None
    try:
        r = requests.post(f"{server}{path}", json=payload, timeout=3)
        if r.status_code == 200:
            return r.json()
        print(f"[warn] {path} -> HTTP {r.status_code}: {r.text[:120]}")
    except Exception as e:
        print(f"[warn] 서버 전송 실패: {e}")
    return None


def average(frames: List[List[int]]) -> List[int]:
    n = len(frames)
    return [round(sum(f[i] for f in frames) / n) for i in range(N_CHANNELS)]


# ---------------------------------------------------------------- 모드
def run_calibration(source, server: str, label: str, seconds: float):
    """자세 등록: N초 동안 모은 프레임의 평균을 서버에 기준값으로 저장."""
    print(f"[calib] '{label}' 자세로 앉아주세요. {seconds}초간 측정합니다...")
    frames, t0 = [], time.time()
    while time.time() - t0 < seconds:
        f = source.read_frame()
        if f:
            frames.append(f)
    if not frames:
        sys.exit("[calib] 프레임을 하나도 못 받았습니다. 연결을 확인하세요.")

    avg = average(frames)
    feat = features.extract(avg)
    print(f"[calib] {len(frames)} 프레임 평균 | "
          f"CoF=({feat['cof_x']:.2f},{feat['cof_y']:.2f}) "
          f"LR={feat['lr_balance']:+.2f} FB={feat['fb_balance']:+.2f}")

    res = post(server, "/calibration", {
        "label": label, "frame": avg, "features": feat, "samples": len(frames),
    })
    print("[calib] 등록 완료:", res or "(서버 응답 없음)")


def run_stream(source, server: str, hz: float, show_raw: bool):
    interval = 1.0 / hz
    print(f"[stream] {hz}Hz 로 서버 전송 시작. 중단하려면 Ctrl+C")
    buf: List[List[int]] = []
    last_send = time.time()
    fps_count, fps_t0 = 0, time.time()

    try:
        while True:
            frame = source.read_frame()
            if frame is None:
                print("[stream] 데이터가 끊겼습니다. 재시도...")
                time.sleep(0.5)
                continue
            buf.append(frame)
            fps_count += 1

            if show_raw:
                print(" ".join(f"{v:4d}" for v in frame))

            now = time.time()
            if now - last_send >= interval and buf:
                avg = average(buf)
                buf.clear()
                last_send = now
                feat = features.extract(avg)
                res = post(server, "/sensor-frame", {"frame": avg, "features": feat})
                if res:
                    print(f"  자세: {res.get('posture'):<8} "
                          f"신뢰도 {res.get('confidence', 0):.2f} | "
                          f"sum={feat['sum']:6.0f} "
                          f"CoF=({feat['cof_x']:.2f},{feat['cof_y']:.2f}) "
                          f"| {fps_count / (now - fps_t0):.0f} fps")
                fps_count, fps_t0 = 0, now
    except KeyboardInterrupt:
        print("\n[stream] 종료")


def main():
    ap = argparse.ArgumentParser(description="PoseLab Seat -> 서버 브리지")
    ap.add_argument("--port", help="시리얼 포트 ('auto' 가능)")
    ap.add_argument("--mock", action="store_true", help="센서 없이 가상 데이터 사용")
    ap.add_argument("--posture", default="정자세", help="mock 고정 자세")
    ap.add_argument("--auto", action="store_true", help="mock 자세 자동 전환")
    ap.add_argument("--server", default="http://127.0.0.1:8000")
    ap.add_argument("--hz", type=float, default=2.0)
    ap.add_argument("--calibrate", metavar="LABEL", help="자세 등록 모드")
    ap.add_argument("--seconds", type=float, default=3.0)
    ap.add_argument("--raw", action="store_true")
    args = ap.parse_args()

    if not args.mock and not args.port:
        ap.error("--port 또는 --mock 중 하나는 필요합니다")

    if args.mock:
        source = mock_source.MockSource(
            posture=args.posture, mode="auto" if args.auto else "fixed")
        print(f"[mock] 가상 센서 모드 (자세: {args.posture}"
              f"{', 자동전환' if args.auto else ''})")
    else:
        source = SerialSource(args.port)

    try:
        if args.calibrate:
            run_calibration(source, args.server, args.calibrate, args.seconds)
        else:
            run_stream(source, args.server, args.hz, args.raw)
    finally:
        source.close()


if __name__ == "__main__":
    main()
