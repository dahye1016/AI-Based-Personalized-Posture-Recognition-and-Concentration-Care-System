"""
센서 없이 자세판정 파이프라인 전체를 검증하는 테스트.

  python bridge/test_pipeline.py

DB/FastAPI 없이 돌아가므로, 서버 안 띄우고도 판정 로직만 빠르게 확인할 수 있습니다.
"""

import os
import random
import sys
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "..", "server"))

import features as F
import mock_source as M
import posture_classifier as P

LABELS = [p for p in M.POSTURE_NAMES if p != "비착석"]

# 브리지는 센서에서 온 프레임을 모아 평균낸 뒤 0.5초에 한 번 보냅니다.
# (--hz 2, 센서 실측 수십 fps → 프레임 십수 개가 평균됨)
# 그래서 테스트도 '평균된 프레임'으로 해야 실제와 같은 조건입니다.
FRAMES_PER_SEND = 12


def avg_frame(label, rng, n=FRAMES_PER_SEND):
    frames = [M.generate(label, rng=rng) for _ in range(n)]
    return [round(sum(f[i] for f in frames) / n) for i in range(len(frames[0]))]


def build_calibrations(rng, samples_per_posture=30):
    """앱 '초기 설정 > 자세 등록'(3초 측정) 을 코드로 재현."""
    calibs = []
    for label in LABELS:
        avg = avg_frame(label, rng, samples_per_posture)
        calibs.append({"label": label, "vector": F.to_vector(F.extract(avg))})
    return calibs


def evaluate(calibs, rng, trials=200):
    hits, confusion = 0, Counter()
    for _ in range(trials):
        truth = rng.choice(LABELS)
        feat = F.extract(avg_frame(truth, rng))
        pred, conf = P.classify(feat, calibs)
        if pred == truth:
            hits += 1
        else:
            confusion[(truth, pred)] += 1
    return hits / trials, confusion


def main():
    rng = random.Random(42)

    print("=" * 62)
    print(" 1. 배치 정의 검증")
    print("=" * 62)
    import layout as L
    print(f"  채널 수        : {L.N_CHANNELS}")
    print(f"  ROW0/1/2 크기  : {[len(a) + len(b) for a, b in L.ROWS.values()]}")
    print(f"  좌/우 채널 수  : {len(L.LEFT_CH)} / {len(L.RIGHT_CH)}")
    assert len(L.LEFT_CH) + len(L.RIGHT_CH) == 32
    print("  ✅ OK")

    print()
    print("=" * 62)
    print(" 2. 프로토콜 파서 검증 (실물 없이)")
    print("=" * 62)
    import protocol
    ascii_line = (",".join(str(i * 7 % 1400) for i in range(32)) + "\n").encode()
    p = protocol.sniff(ascii_line)
    frames = list(p.feed(ascii_line))
    print(f"  자동판별       : {p.name}")
    print(f"  파싱된 프레임  : {len(frames)}개, 길이 {len(frames[0])}")
    assert p.name == "ascii" and len(frames) == 1 and len(frames[0]) == 32

    import struct
    bin_frame = b"\xaa\x55" + struct.pack("<32H", *[i * 40 for i in range(32)])
    pb = protocol.sniff(bin_frame)
    fb = list(pb.feed(bin_frame))
    print(f"  바이너리 폴백  : {pb.name}, {len(fb)}개 프레임")
    assert pb.name == "binary" and len(fb) == 1 and len(fb[0]) == 32
    print("  ✅ OK")

    print()
    print("=" * 62)
    print(" 3. 규칙 기반 폴백 (자세 등록 전)")
    print("=" * 62)
    rule_hits = 0
    for label in LABELS:
        feat = F.extract(avg_frame(label, rng))
        pred, conf = P.classify(feat, [])
        ok = pred == label
        rule_hits += ok
        print(f"  {label:<12} -> {pred:<12} ({conf:.2f}) {'✅' if ok else '⚠️'}")
    print(f"  규칙만으로 {rule_hits}/{len(LABELS)} 일치 "
          f"(폴백이므로 완벽할 필요 없음)")

    print()
    print("=" * 62)
    print(" 4. 개인 캘리브레이션 기반 판정")
    print("=" * 62)
    calibs = build_calibrations(rng)
    print(f"  등록된 기준 자세: {len(calibs)}개")
    acc, confusion = evaluate(calibs, rng, trials=300)
    print(f"  정확도          : {acc * 100:.1f}%  (300회)")
    if confusion:
        print("  주요 오분류:")
        for (t, p_), n in confusion.most_common(4):
            print(f"    {t} -> {p_} : {n}회")
    assert acc > 0.80, f"정확도가 너무 낮습니다: {acc}"
    print("  ✅ OK")

    print()
    print("=" * 62)
    print(" 5. 비착석 감지")
    print("=" * 62)
    feat = F.extract(avg_frame("비착석", rng))
    pred, conf = P.classify(feat, calibs)
    print(f"  sum={feat['sum']:.0f} -> {pred} ({conf:.2f})")
    assert pred == "비착석"
    print("  ✅ OK")

    print()
    print("🎉 전체 통과 — 센서 실물 없이 파이프라인이 정상 동작합니다.")


if __name__ == "__main__":
    main()
