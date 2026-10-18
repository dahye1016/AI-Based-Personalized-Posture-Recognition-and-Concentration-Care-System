"""
qc_64ch.py — 64ch 실측 CSV 의 품질·자세 지표를 계산해서 한 줄씩 CSV 로 내보낸다.

결과 CSV 의 컬럼 순서는 엑셀 '실측_참가자섭외_합격기준_64ch.xlsx' 의 '수집 현황' 시트
A~P 열과 같다. 결과를 그대로 복사해서 그 시트 A6 부터 붙여 넣으면 합격/불합격이
자동으로 계산된다.

입력 CSV 형식: 팀 저장소 ml/collect_data.py --port-back 이 만드는 형식
    frame,timestamp,ch0..ch63,person,posture,trial     (ch0~31 방석, ch32~63 등받이)

좌우·줄 정의는 2026-10-18 뒤집은 매트 기준 sensor_layout.dart 와 같다.
    방석 : 번호가 작을수록 사용자의 왼쪽  (오른쪽 = ch5~9, 17~23, 28~31)
    등받이: 번호가 작을수록 사용자의 오른쪽 (오른쪽 = ch32~36, 42~48, 56~59)
뒤집기 전에 모은 파일에는 쓰지 말 것 (좌우가 반대로 계산된다).

사용 예
    python qc_64ch.py --dir data\\raw_64ch --out qc_metrics.csv
    python qc_64ch.py --dir data\\raw_64ch --out qc_metrics.csv --only-new qc_metrics_prev.csv
"""
import argparse
import glob
import os
import sys

import numpy as np
import pandas as pd

SEAT_R = list(range(5, 10)) + list(range(17, 24)) + list(range(28, 32))
HIP = list(range(0, 10))
B_R = list(range(32, 37)) + list(range(42, 49)) + list(range(56, 60))
SHOULDER = list(range(56, 64))
ACTIVE = 20          # 채널 평균이 이 값을 넘으면 "반응 있음"
BACK_MIN_FOR_SHARE = 50   # 등받이 총압력이 이보다 작으면 비중·좌우 비율은 계산하지 않음(빈칸)
SAT_VALUE = 1064 * 0.98   # 포화 후보: 2026-10-18 데이터 전체 최댓값(1064)의 98% 이상

HEADER = ["파일명", "person", "자세", "회차", "프레임 수", "길이(초)", "fps",
          "방석 총압력", "등받이 총압력", "엉덩이 줄 비중(%)", "방석 오른쪽(%)",
          "등받이 오른쪽(%)", "등받이 어깨 줄(%)", "등받이 반응 채널 수",
          "방석 흔들림(CV%)", "포화 비율(%)"]


def metrics_for(path):
    d = pd.read_csv(path)
    need = [f"ch{i}" for i in range(64)]
    miss = [c for c in need if c not in d.columns]
    if miss:
        raise ValueError(f"{os.path.basename(path)}: ch0~ch63 컬럼이 없음 (예: {miss[:3]})")
    X = d[need].values.astype(float)
    ts = d["timestamp"].values.astype(float)
    n = len(X)
    dur = ts[-1] - ts[0] if n > 1 else 0.0
    m = X.mean(0)
    seat_total, back_total = m[:32].sum(), m[32:].sum()
    seat_sum_t = X[:, :32].sum(1)
    back_sum_t = X[:, 32:].sum(1)

    def pct(part, whole):
        return round(float(part / whole * 100), 1)

    return [
        os.path.basename(path), str(d["person"].iloc[0]), str(d["posture"].iloc[0]),
        int(d["trial"].iloc[0]), n, round(dur, 1), round(n / dur, 1) if dur > 0 else None,
        round(seat_total), round(back_total),
        pct(m[HIP].sum(), seat_total) if seat_total > 0 else None,
        pct(m[SEAT_R].sum(), seat_total) if seat_total > 0 else None,
        pct(m[B_R].sum(), back_total) if back_total > BACK_MIN_FOR_SHARE else None,
        pct(m[SHOULDER].sum(), back_total) if back_total > BACK_MIN_FOR_SHARE else None,
        int((m[32:] > ACTIVE).sum()),
        round(float(seat_sum_t.std() / seat_sum_t.mean() * 100), 1) if seat_total > 0 else None,
        round(float((X >= SAT_VALUE).mean() * 100), 3),
    ]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=os.path.join("data", "raw_64ch"))
    ap.add_argument("--out", default="qc_metrics.csv")
    ap.add_argument("--only-new", default=None,
                    help="이전에 만든 결과 CSV. 여기에 이미 있는 파일명은 건너뛴다.")
    a = ap.parse_args()

    files = sorted(glob.glob(os.path.join(a.dir, "**", "*.csv"), recursive=True))
    files = [f for f in files if "_reject" not in os.path.basename(f)]
    if a.only_new and os.path.exists(a.only_new):
        done = set(pd.read_csv(a.only_new)["파일명"])
        files = [f for f in files if os.path.basename(f) not in done]
    if not files:
        sys.exit(f"처리할 CSV 가 없습니다: {a.dir}")

    rows, bad = [], []
    for f in files:
        try:
            rows.append(metrics_for(f))
        except Exception as e:  # 형식이 다른 파일은 건너뛰고 알려준다
            bad.append(f"{os.path.basename(f)}: {e}")
    out = pd.DataFrame(rows, columns=HEADER)
    out.to_csv(a.out, index=False, encoding="utf-8-sig")
    print(f"{len(out)}개 파일 -> {a.out}")
    for b in bad:
        print("  건너뜀:", b)
    print("엑셀 '수집 현황' 시트 A6 부터 붙여 넣으세요 (헤더 줄 제외).")


if __name__ == "__main__":
    main()
