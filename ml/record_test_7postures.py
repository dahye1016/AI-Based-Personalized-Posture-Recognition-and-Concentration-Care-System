"""
record_test_7postures.py — 지금 기기로 7자세 시험용 녹화 (각 20초, 총 약 3분)

ml/collect_data.py(64채널, --port-back)를 자세마다 한 번씩 불러서 찍고,
학습 폴더(data/raw_64ch/)에 섞이지 않게 data/test_64ch/ 로 옮긴다.

실행 위치: 저장소 맨 위 폴더 (feat/yewon 브랜치)
필요 패키지: pyserial  (pip install pyserial)

사용 예:
    Windows: python ml/record_test_7postures.py --person dahye --chair labchair --port COM3 --port-back COM5
    macOS  : python ml/record_test_7postures.py --person dahye --chair labchair \
        --port /dev/cu.usbmodem5C843561931 --port-back /dev/cu.usbmodem5C843561121

    --chair 는 의자 이름 (다른 의자에서 또 찍으면 이름만 바꿔서 다시 실행)
    포트 확인: python -m serial.tools.list_ports -v  (Windows 는 COM3 같은 이름) 좌석 보드가 --port, 등받이 보드가 --port-back.
"""
import argparse
import os
import shutil
import subprocess
import sys

POSTURES = [
    ("sitting_straight", "정자세 — 허리를 펴고 등을 등받이에 붙여 바르게 앉기"),
    ("lean_forward",     "앞으로 숙이기 — 등을 등받이에서 떼고 상체를 앞으로"),
    ("lean_left",        "왼쪽 기대기 — 몸을 왼쪽으로 기울여 기대기"),
    ("lean_right",       "오른쪽 기대기 — 몸을 오른쪽으로 기울여 기대기"),
    ("cross_leg_left",   "왼다리 꼬기 — 왼다리를 오른다리 위에 올리기"),
    ("cross_leg_right",  "오른다리 꼬기 — 오른다리를 왼다리 위에 올리기"),
    ("not_sitting",      "미착석 — 일어나서 방석에서 완전히 떨어지기"),
]

SRC_DIR = os.path.join("data", "raw_64ch")
DST_DIR = os.path.join("data", "test_64ch")


def main():
    ap = argparse.ArgumentParser(description="7자세 시험용 녹화 (64채널)")
    ap.add_argument("--person", required=True, help="찍는 사람 (예: dahye)")
    ap.add_argument("--chair", required=True, help="의자 이름 (예: labchair)")
    ap.add_argument("--port", required=True, help="좌석 보드 포트")
    ap.add_argument("--port-back", required=True, help="등받이 보드 포트")
    ap.add_argument("--duration", type=float, default=20.0, help="자세당 초 (기본 20)")
    ap.add_argument("--trial", type=int, default=1, help="시행 번호 (기본 1)")
    args = ap.parse_args()

    collector = os.path.join("ml", "collect_data.py")
    if not os.path.exists(collector):
        sys.exit("ml/collect_data.py 가 없습니다. 저장소 맨 위 폴더에서, feat/yewon 브랜치로 실행해 주세요.")
    os.makedirs(DST_DIR, exist_ok=True)

    # 파일 이름의 사람 칸에 의자 이름을 붙여서, 의자별로 구분되게 한다.
    tag = f"test-{args.chair}-{args.person}"
    print(f"\n의자 '{args.chair}', 사람 '{args.person}' — 7자세 각 {args.duration:.0f}초 녹화를 시작합니다.")
    print("방석 방향(앞·좌우)을 평소와 똑같이 놓았는지 확인하세요.\n")

    done = []
    for i, (posture, how) in enumerate(POSTURES, 1):
        print("=" * 60)
        print(f"[{i}/7] {how}")
        input("  자세를 잡았으면 Enter (카운트다운 후 녹화 시작) ")
        cmd = [sys.executable, collector, "--person", tag, "--posture", posture,
               "--trial", str(args.trial), "--duration", str(args.duration),
               "--port", args.port, "--port-back", args.port_back]
        if subprocess.run(cmd).returncode != 0:
            print(f"  ⚠️ {posture} 녹화 실패. 이 자세만 다시 찍으려면 스크립트를 다시 실행하세요.")
            continue
        name = f"{tag}_{posture}_{args.trial}.csv"
        src, dst = os.path.join(SRC_DIR, name), os.path.join(DST_DIR, name)
        if os.path.exists(src):
            shutil.move(src, dst)       # 학습 폴더에 섞이지 않게 옮김
            done.append(dst)
            print(f"  저장: {dst}")
        else:
            print(f"  ⚠️ 저장 파일을 못 찾았습니다: {src}")

    print("\n" + "=" * 60)
    print(f"끝. {len(done)}/7 개 저장 — {DST_DIR}/")
    for p in done:
        print("  ", p)
    print("\n이 파일들을 보내주면 모델 채점에 씁니다.")


if __name__ == "__main__":
    main()
