"""
gen_dummy_64ch.py — 센서 도착 전까지 쓰는 64ch 더미 데이터 생성기 (방석 32 + 등받이 32, 8자세)

[목적] 파이프라인(변환 → 학습 → 서버 → 앱) 개발용. 실측이 아니므로 이 데이터로 나온
       정확도는 성과로 쓰지 말 것. 센서가 오면 data\\raw_64ch 의 진짜 CSV 로 다시 학습한다.

[방식] 실측 파일을 '재료'로 쓴다. 자세마다 실측 파일 하나를 골라 그 채널 모양과 프레임
       잡음을 가져오고, 가상 참가자마다 다음을 바꿔 변형한다.
         - 방석/등받이 전체 크기(체격), 채널별 작은 흔들림, 좌우 습관(방석 좌우 쏠림)
         - 길이(1244~1344프레임), 시간에 따른 느린 변동
       그런 다음 엑셀 '합격 기준 수치표'와 같은 기준으로 검사해서, 통과한 것만 저장한다.
       (실측 재료는 거북목 = dahye/yewon 만 쓴다. aro/junseo 거북목은 등이 안 닿아 불량.)

[거북목 vs 앞으로 숙이기 — 섞지 않는다]
   lean_forward : 등받이 전체가 0 (재료도 등받이를 0 으로 만든다)
   turtle_neck  : 등(허리·중간 줄)은 닿고 어깨 줄(ch56~63)은 거의 0
   두 자세의 재료·변형·검사 기준이 서로 다르고, 생성 뒤에도 서로 침범하지 않았는지 다시 확인한다.

[출력] data\\dummy_64ch\\<자세>\\dummy_<id>_<자세>_<회차>.csv
       컬럼: frame,timestamp,ch0..ch63,person,posture,trial  (실측과 동일)
       person 은 항상 'dummy_...' 로 시작한다. 실측 폴더(data\\raw_64ch)와 섞지 말 것.
       <out>_manifest.csv (예: data\\dummy_64ch_manifest.csv) : 파일별 가상 참가자, 케이스 ID, 체격 배율

사용 예 (PowerShell, C:\\Users\\jungd\\posture-64ch)
    python gen_dummy_64ch.py                               # 40명 x 8자세 x 5회 = 1,600파일
    python gen_dummy_64ch.py --persons 60 --trials 8       # 더 많이
    python gen_dummy_64ch.py --templates data\\raw_64ch --out data\\dummy_64ch --seed 7
"""
import argparse
import glob
import os
import sys

import numpy as np
import pandas as pd

POSTURES = ["not_sitting", "sitting_straight", "lean_forward", "cross_leg_right",
            "cross_leg_left", "lean_right", "lean_left", "turtle_neck"]
CH = [f"ch{i}" for i in range(64)]
SEAT_R = list(range(5, 10)) + list(range(17, 24)) + list(range(28, 32))
SEAT_L = [i for i in range(32) if i not in SEAT_R]
HIP = list(range(0, 10))
B_R = list(range(32, 37)) + list(range(42, 49)) + list(range(56, 60))
SHOULDER = list(range(56, 64))
ACTIVE = 20
BACK_MIN_FOR_SHARE = 50
SAT_VALUE = 1064 * 0.98
MAXV = 1064

# ---- 합격 기준 (엑셀 '합격 기준 수치표'와 같은 값) -------------------------------------------
# 지표 순서: 0 방석총 1 등받이총 2 엉덩이줄% 3 방석오른쪽% 4 등받이오른쪽% 5 어깨줄% 6 반응채널수
CRIT = {
    "not_sitting":      {0: (None, 300), 1: (None, 100)},
    "sitting_straight": {0: (6000, None), 1: (1000, None), 3: (40, 60), 6: (4, None)},
    "lean_forward":     {0: (6000, None), 1: (None, 100), 2: (None, 32), 3: (40, 60)},
    "cross_leg_right":  {0: (6000, None), 1: (500, None), 3: (None, 46), 6: (4, None)},
    "cross_leg_left":   {0: (6000, None), 1: (500, None), 3: (60, None), 6: (4, None)},
    "lean_right":       {0: (6000, None), 1: (1000, None), 3: (52, None), 4: (80, None), 6: (4, None)},
    "lean_left":        {0: (6000, None), 1: (1000, None), 4: (None, 20), 6: (4, None)},
    "turtle_neck":      {0: (6000, None), 1: (400, None), 3: (40, 60), 5: (None, 3), 6: (3, None)},
}
Q = dict(frames_min=1100, dur=(19, 22), fps=(55, 70), cv_max=10.0, sat_max=0.5, empty_seat=300)


def load_xlsx_criteria(path):
    """엑셀 '합격 기준 수치표'를 읽어서 CRIT/Q 를 덮어쓴다 (없으면 위 기본값 사용)."""
    from openpyxl import load_workbook
    ws = load_workbook(path, data_only=True)["합격 기준 수치표"]
    keys = {ws.cell(r, 2).value: r for r in range(6, 14)}
    for key, r in keys.items():
        if key not in CRIT:
            continue
        CRIT[key] = {}
        for k in range(7):
            lo, hi = ws.cell(r, 4 + 2 * k).value, ws.cell(r, 5 + 2 * k).value
            if lo is not None or hi is not None:
                CRIT[key][k] = (lo, hi)
    q = [ws.cell(17 + i, 4).value for i in range(8)]
    Q.update(frames_min=q[0], dur=(q[1], q[2]), fps=(q[3], q[4]), cv_max=q[5], sat_max=q[6], empty_seat=q[7])


def metrics(X, dur, n):
    m = X.mean(0)
    st, bt = m[:32].sum(), m[32:].sum()
    sst = X[:, :32].sum(1)
    pct = lambda a, b: float(a / b * 100)
    return dict(
        seat_total=st, back_total=bt,
        hip=pct(m[HIP].sum(), st) if st > 0 else None,
        seat_r=pct(m[SEAT_R].sum(), st) if st > 0 else None,
        back_r=pct(m[B_R].sum(), bt) if bt > BACK_MIN_FOR_SHARE else None,
        shoulder=pct(m[SHOULDER].sum(), bt) if bt > BACK_MIN_FOR_SHARE else None,
        active=int((m[32:] > ACTIVE).sum()),
        cv=float(sst.std() / sst.mean() * 100) if st > 0 else None,
        sat=float((X >= SAT_VALUE).mean() * 100), fps=n / dur, dur=dur, n=n)


def passes(posture, M):
    vals = [M["seat_total"], M["back_total"], M["hip"], M["seat_r"], M["back_r"], M["shoulder"], M["active"]]
    if not (M["n"] >= Q["frames_min"] and Q["dur"][0] <= M["dur"] <= Q["dur"][1]
            and Q["fps"][0] <= M["fps"] <= Q["fps"][1] and M["sat"] <= Q["sat_max"]):
        return False
    if M["seat_total"] > Q["empty_seat"] and M["cv"] is not None and M["cv"] > Q["cv_max"]:
        return False
    for k, (lo, hi) in CRIT[posture].items():
        v = vals[k]
        if v is None:
            return False
        if lo is not None and v < lo:
            return False
        if hi is not None and v > hi:
            return False
    return True


def load_templates(tdir):
    """자세별 재료 목록. 거북목은 '등은 닿고 어깨 줄 거의 0'인 파일만 쓴다."""
    T = {p: [] for p in POSTURES}
    files = sorted(f for f in glob.glob(os.path.join(tdir, "**", "*.csv"), recursive=True)
                   if "_reject" not in os.path.basename(f) and "dummy" not in os.path.basename(f))
    for f in files:
        d = pd.read_csv(f)
        if any(c not in d.columns for c in CH + ["posture", "timestamp"]):
            continue
        p = str(d["posture"].iloc[0])
        if p not in T:
            continue
        X = d[CH].values.astype(float)
        m = X.mean(0)
        bt = m[32:].sum()
        if p == "turtle_neck":
            sh = m[SHOULDER].sum() / bt * 100 if bt > BACK_MIN_FOR_SHARE else 100
            if bt < 400 or sh > 3:
                continue
        if p == "lean_forward" and bt > 100:   # 등받이가 0 이 아니면 재료로 쓰지 않음
            continue
        if p == "not_sitting" and m[:32].sum() > 300:
            continue
        T[p].append(X)
    return T


def make_person(i, rng):
    """가상 참가자: 성별·키 구간·체형 구간(F1~F9/M1~M9)과 체격 배율."""
    sex = "F" if i % 2 == 0 else "M"
    h, b = rng.integers(1, 4), rng.integers(1, 4)
    case = f"{sex}{(h - 1) * 3 + b}"
    body = {1: 0.80, 2: 1.00, 3: 1.25}[b] * (0.92 + 0.08 * h) * (1.08 if sex == "M" else 1.0)
    return dict(id=f"dummy_{case.lower()}_{i:02d}", case=case, body=body * rng.lognormal(0, 0.06),
                back_gain=rng.lognormal(0, 0.22), lr=float(np.clip(rng.normal(0, 0.025), -0.05, 0.05)),
                ch_jit=rng.lognormal(0, 0.08, 64))


def synth(posture, tpl, P, rng):
    n = int(rng.integers(1244, 1345))
    src = tpl[rng.integers(len(tpl))]
    # 길이 맞춰 다시 뽑기(시간 순서 유지)
    idx = np.clip(np.round(np.linspace(0, len(src) - 1, n)).astype(int), 0, len(src) - 1)
    Xs = src[idx]
    mean, dev = Xs.mean(0), Xs - Xs.mean(0)
    g = np.ones(64)
    g[:32] = P["body"]
    g[32:] = P["body"] * P["back_gain"]
    g = g * P["ch_jit"] * rng.lognormal(0, 0.05, 64)          # 이 회차의 채널별 흔들림
    g[SEAT_R] *= 1 + P["lr"] + rng.normal(0, 0.02)             # 좌우 습관
    g[SEAT_L] *= 1 - P["lr"] - rng.normal(0, 0.02)
    # 앉았다 일어나는 앞뒤 변화는 넣지 않고, 20초 안의 느린 변동만 넣는다
    drift = 1 + 0.015 * np.cumsum(rng.normal(0, 0.04, n))
    drift = np.clip(drift, 0.95, 1.05)[:, None]
    X = (mean * g + dev * np.sqrt(P["body"]) * rng.uniform(0.8, 1.2)) * drift
    X += rng.normal(0, 1.0, X.shape) * (X > 5)                  # 센서 잡음(0 은 0 으로 둠)
    if posture == "lean_forward":
        X[:, 32:] = 0                                           # 등이 안 닿는 자세: 등받이 완전 0
    if posture == "turtle_neck":
        X[:, SHOULDER] = np.minimum(X[:, SHOULDER], 5)          # 어깨는 뜬 채: 거의 0
    if posture == "not_sitting":
        X[:] = 0
    X = np.clip(np.round(X), 0, MAXV)
    X[X < 3] = 0
    return X


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--templates", default=os.path.join("data", "raw_64ch"), help="실측 CSV 폴더(재료)")
    ap.add_argument("--out", default=os.path.join("data", "dummy_64ch"))
    ap.add_argument("--persons", type=int, default=40)
    ap.add_argument("--trials", type=int, default=5)
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--xlsx", default=None, help="'실측_참가자섭외_합격기준_64ch.xlsx' (있으면 수치표를 읽어 기준으로 씀)")
    ap.add_argument("--fps", type=float, default=62.3)
    a = ap.parse_args()
    if a.xlsx:
        load_xlsx_criteria(a.xlsx)
    rng = np.random.default_rng(a.seed)
    T = load_templates(a.templates)
    need = [p for p in POSTURES if p != "not_sitting" and not T[p]]
    for p in POSTURES:
        print(f"재료 {p:17s} {len(T[p])}개")
    if need:
        sys.exit(f"재료가 없는 자세: {need}  (--templates 폴더에 해당 실측 CSV 가 필요)")
    if not T["not_sitting"]:
        T["not_sitting"] = [np.zeros((1300, 64))]

    rows, made, fail = [], 0, 0
    t0 = 1.79e9
    persons = [make_person(i + 1, rng) for i in range(a.persons)]
    for P in persons:
        for post in POSTURES:
            os.makedirs(os.path.join(a.out, post), exist_ok=True)
            for tr in range(1, a.trials + 1):
                ok = False
                for att in range(120):                           # 기준 불통과면 다시 만든다
                    Pq = P if att < 60 else dict(P, lr=0.0, ch_jit=np.ones(64),  # 계속 실패하면 습관을 줄여서
                                                 body=max(P["body"], 1.0), back_gain=1.0)
                    X = synth(post, T[post], Pq, rng)
                    n = len(X)
                    M = metrics(X, n / a.fps, n)
                    if passes(post, M):
                        ok = True
                        break
                if not ok:
                    fail += 1
                    continue
                ts = t0 + np.arange(n) / a.fps + rng.normal(0, 0.0004, n).cumsum() * 0
                df = pd.DataFrame(X.astype(int), columns=CH)
                df.insert(0, "timestamp", ts)
                df.insert(0, "frame", np.arange(n))
                df["person"], df["posture"], df["trial"] = P["id"], post, tr
                name = f"{P['id']}_{post}_{tr}.csv"
                df.to_csv(os.path.join(a.out, post, name), index=False)
                rows.append(dict(file=name, person=P["id"], case=P["case"], posture=post, trial=tr,
                                 body=round(P["body"], 3), frames=n,
                                 seat_total=round(M["seat_total"]), back_total=round(M["back_total"])))
                made += 1
                t0 += 30
    man = pd.DataFrame(rows)
    man_path = os.path.normpath(a.out) + "_manifest.csv"      # 데이터 폴더 밖에 둔다(변환기가 CSV 를 전부 읽기 때문)
    man.to_csv(man_path, index=False, encoding="utf-8-sig")

    # ---- 자체 점검: 거북목 / 앞으로 숙이기가 섞이지 않았는지 ------------------------------------
    lf = man[man.posture == "lean_forward"].back_total
    tn = man[man.posture == "turtle_neck"].back_total
    print(f"\n생성 {made}파일 (기준 불통과로 포기 {fail}), 가상 참가자 {len(persons)}명 -> {a.out}")
    print(man.groupby("posture").size().to_string())
    print(f"앞으로 숙이기 등받이 총압력: 최대 {lf.max():.0f} (기준 100 이하)")
    print(f"거북목 등받이 총압력: 최소 {tn.min():.0f} (기준 400 이상)")
    assert lf.max() <= 100 and tn.min() >= 400, "거북목/앞으로 숙이기 분리가 깨졌습니다"
    print("확인 완료: 거북목은 등이 닿고, 앞으로 숙이기는 등받이 0 — 겹치지 않음")
    print("\n다음: python -m ml.prepare_chair_data --source csvdir --csv-dir data\\dummy_64ch "
          "--out chair_64ch_posture_data_dummy.csv")
    ids = [P["id"] for P in persons]
    print("      python train_posture_cnn_64ch_dummy.py --data chair_64ch_posture_data_dummy.csv "
          f"--out-suffix dummy --holdout-persons {ids[-2]},{ids[-1]}")


if __name__ == "__main__":
    main()
