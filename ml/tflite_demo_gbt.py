"""
tflite_demo_gbt.py — 새 앱용 모델(posture_model_gbt.tflite)이 자세를 잘 맞히는지 터미널에서 눈으로 확인

data/raw_64ch 의 실측 녹화에서 프레임을 하나씩 무작위로 뽑아, 그 사람의 캘리브레이션 값(정자세 5초 평균)과
함께 TFLite 에 넣고 "실제 자세 vs 예측"을 계속 출력한다. 끝낼 때(Ctrl+C) 자세별 정확도를 보여준다.

주의: 최종 모델은 이 실측 전체로 학습했으므로 여기 숫자는 '학습 데이터에서의' 확인용이다.
      처음 보는 사람 기준 정확도는 ml/norm_stats_gbt.json 의 person_split_eval (LOPO) 을 볼 것.

실행 (저장소 루트에서):
    python ml/tflite_demo_gbt.py                 # 모든 사람·자세에서 무작위
    python ml/tflite_demo_gbt.py --person dahye  # 한 사람만 (이름 뒤 날짜 붙은 회차도 포함)
    python ml/tflite_demo_gbt.py --posture cross_leg_right
    python ml/tflite_demo_gbt.py --fast          # 기다리지 않고 빠르게
    python ml/tflite_demo_gbt.py --fast --count 500   # 500개만 보고 자세별 정확도 출력
"""

import argparse
import glob
import os
import random
import sys
import time
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from posture_names import POSTURE_ORDER, KOREAN  # noqa: E402

MODEL = ROOT / "ml" / "posture_model_gbt.tflite"
CH = [f"ch{i}" for i in range(64)]
CAL_FRAMES = 5 * 62


def calibration():
    """회차별 기준값: 어깨가 닿은 정자세(어깨 줄 합 >= 200) 처음 5초 평균. 없으면 아무 정자세."""
    cal = {}
    files = sorted(glob.glob(str(ROOT / "data" / "raw_64ch" / "*sitting_straight*.csv")))
    for prefer in (True, False):
        for f in files:
            d = pd.read_csv(f)
            s = str(d["person"].iloc[0])
            if s in cal:
                continue
            if prefer and d[CH].values[:, 56:64].mean(0).sum() < 200:
                continue
            cal[s] = d[CH].values[:CAL_FRAMES].astype(np.float32).mean(0)
    return cal


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--person", default="", help="이 사람만 (예: dahye, aro)")
    ap.add_argument("--posture", default="", help="이 자세만 (예: cross_leg_right)")
    ap.add_argument("--fast", action="store_true", help="0.3초 쉬지 않고 바로바로")
    ap.add_argument("--count", type=int, default=0, help="이 개수만 보고 끝내기 (0 = Ctrl+C 까지 계속)")
    a = ap.parse_args()

    try:
        import tensorflow as tf
    except ImportError:
        sys.exit("tensorflow 가 없습니다. pip install tensorflow")
    it = tf.lite.Interpreter(model_path=str(MODEL))
    it.allocate_tensors()
    ind, outd = it.get_input_details()[0], it.get_output_details()[0]

    import json
    labels = json.loads((ROOT / "ml" / "norm_stats_gbt.json").read_text(encoding="utf-8"))["label_order"]
    print(f"모델 자세 {len(labels)}개: {labels}")
    cal = calibration()
    recs = []
    for f in sorted(glob.glob(str(ROOT / "data" / "raw_64ch" / "*.csv"))):
        if "_reject" in os.path.basename(f):
            continue
        d = pd.read_csv(f)
        s, p = str(d["person"].iloc[0]), str(d["posture"].iloc[0])
        who = s.rstrip("0123456789")
        if (a.person and who != a.person) or (a.posture and p != a.posture) or s not in cal:
            continue
        if p not in labels:                      # 모델에 없는 자세는 건너뛴다
            continue
        recs.append((s, p, d[CH].values.astype(np.float32)))
    if not recs:
        sys.exit("조건에 맞는 녹화가 없습니다.")
    print(f"모델 {MODEL.name} / 녹화 {len(recs)}개 / Ctrl+C 로 끝내면 자세별 정확도를 보여줍니다\n")

    hit, tot = {p: 0 for p in POSTURE_ORDER}, {p: 0 for p in POSTURE_ORDER}
    try:
        while True:
            s, p, X = random.choice(recs)
            row = X[random.randrange(len(X))]
            it.set_tensor(ind["index"], np.hstack([row, cal[s]])[None, :].astype(np.float32))
            it.invoke()
            prob = it.get_tensor(outd["index"])[0]
            k = int(np.argmax(prob))
            ok = POSTURE_ORDER[k] == p
            tot[p] += 1
            hit[p] += int(ok)
            print(f"{'✅' if ok else '❌'} [{s:8s}] 실제 {KOREAN[POSTURE_ORDER.index(p)]:8s} -> "
                  f"예측 {KOREAN[k]:8s} ({prob[k] * 100:5.1f}%)")
            if a.count and sum(tot.values()) >= a.count:
                break
            if not a.fast:
                time.sleep(0.3)
    except KeyboardInterrupt:
        pass
    print("\n자세별 정확도 (이번 실행)")
    for i, p in enumerate(POSTURE_ORDER):
        if tot[p]:
            print(f"  {KOREAN[i]:8s} {hit[p] / tot[p] * 100:5.1f}%  ({hit[p]}/{tot[p]})")
    n = sum(tot.values())
    print(f"  전체      {sum(hit.values()) / n * 100:5.1f}%  ({sum(hit.values())}/{n})")


if __name__ == "__main__":
    main()
