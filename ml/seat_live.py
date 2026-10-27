"""누르는 값을 실시간으로 매트 모양 그대로 보여줌 (화면 제자리 갱신, 초당 10번)
사용: python3 -u ml/seat_live.py [포트] [back]  (포트 생략 = 좌석 121 / back 이면 931)      종료: Ctrl+C"""
import sys, time, serial
SEAT_PORT, BACK_PORT = "/dev/cu.usbmodem5C843561121", "/dev/cu.usbmodem5C843561931"   # 10/27 보드 교체 후 기준
args = sys.argv[1:]
BACK = "back" in args
args = [a for a in args if a != "back"]
PORT = args[0] if args else (BACK_PORT if BACK else SEAT_PORT)
sys.argv = [sys.argv[0], PORT] + (["back"] if BACK else [])
s = serial.Serial(PORT, 2_000_000, timeout=1)
if BACK:   # 등받이: 허리(아래) 0~9 / 중간 10~23 / 어깨(위) 24~31. 등받이는 오른쪽이 앞번호 (sensor_layout.dart)
    ROWS = [("어깨(위)", list(range(24,32))), ("중간", list(range(10,24))), ("허리(아래)", list(range(0,10)))]
    LEFT = list(range(5,10)) + list(range(17,24)) + list(range(28,32))
else:
    ROWS = [("뒤(엉덩이)", list(range(0,10))), ("가운데(허벅지)", list(range(10,24))), ("앞(무릎)", list(range(24,32)))]
    LEFT = list(range(0,5)) + list(range(10,17)) + list(range(24,28))
BAR = " ░▒▓█"
def cell(v):
    k = 0 if v <= 50 else min(4, 1 + v // 500)
    return f"{BAR[k]*2}{v:4d}"
mx = [0]*32; last = 0
print("\033[2J", end="")
try:
    while True:
        v = s.readline().decode(errors="ignore").strip().split(",")
        if len(v) != 32: continue
        try: v = [int(x) for x in v]
        except ValueError: continue
        mx = [max(a, b) for a, b in zip(mx, v)]
        if time.time() - last < 0.1: continue
        last = time.time()
        l = sum(v[i] for i in LEFT); r = sum(v) - l
        out = ["\033[H", f"{'등받이' if BACK else '좌석'}  포트 {sys.argv[1]}   합 {sum(v):6d}   왼쪽 절반 {l:6d}  |  오른쪽 절반 {r:6d}          ", "",
               "            ←  왼쪽                                   오른쪽  →"]
        for name, idx in ROWS:
            half = len(idx)//2
            a, b = idx[:half], idx[half:]
            if BACK: a, b = b, a      # 등받이는 화면 왼쪽에 '왼쪽' 칸이 오도록
            out.append(f"{name:10s} " + " ".join(cell(v[i]) for i in a) + "  ║  " + " ".join(cell(v[i]) for i in b))
        out += ["", f"지금까지 한 번이라도 반응한 칸: {sum(m>50 for m in mx)}/32   "
                f"(왼쪽 {sum(mx[i]>50 for i in LEFT)}/16, 오른쪽 {sum(mx[i]>50 for i in range(32) if i not in LEFT)}/16)     ",
                "칸 표시: ·없음 ░약 ▒ ▓ █강      Ctrl+C 로 종료"]
        print("\n".join(out), end="", flush=True)
except KeyboardInterrupt:
    print("\n\n끝.")
