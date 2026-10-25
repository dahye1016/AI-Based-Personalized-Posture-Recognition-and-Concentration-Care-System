"""
gen_dummy_spec.py — 팀 자세 정의(2026-10-25)를 그대로 지키는 8자세 더미 생성기 (64ch)

자세 정의 (사람 기준 좌우. 어깨 = 등받이 맨 윗줄 ch56~63, 엉덩이 = 좌석 맨 윗줄 ch0~9)
  오른다리 꼬기 : 오른 무릎(ch28~31)이 들림 = 왼 무릎(ch24~27)의 25% 이하 (실측 5명 기준으로 수정)
  왼다리 꼬기   : 왼 무릎이 들림 = 오른 무릎의 25% 이하
                  (처음 정의 '같은 쪽 어깨만 닿음 + 엉덩이 그쪽 대부분'은 실측 다리 꼬기 10개 중 맞는 게 없어서 뺐다)
  오른쪽 기대기 : 오른 어깨 닿음, 왼 어깨 안 닿음, 엉덩이는 양쪽 다 닿음
  왼쪽 기대기   : 왼 어깨 닿음, 오른 어깨 안 닿음, 엉덩이는 양쪽 다 닿음
  거북목        : 등받이 윗부분(어깨) 안 닿음, 등(허리·중간)은 닿음
  정자세        : 다 닿음 (양쪽 엉덩이, 등, 양쪽 어깨)
  앉지 않음     : 전부 0
  앞으로 숙이기 : 어깨 전혀 안 닿음(등받이 전체 거의 0), 방석 압력이 큼

숫자 기준 (SPEC)
  어깨 '닿음' = 그쪽 4채널 합 >= 100, '안 닿음' = <= 20
  엉덩이 '한쪽 대부분' = 그쪽 비율 >= 65%, '다 닿음' = 양쪽 각각 >= 25%
  거북목 등(ch32~55) >= 400 / 앞으로 숙이기 등받이 전체 <= 100, 좌석 >= 6000 / 앉은 자세 좌석 >= 6000
  (녹화 평균 기준)

만드는 법
  1. 같은 자세의 실측 녹화를 재료로 골라 체격·채널 흔들림·잡음·느린 변동을 바꾼다 (gen_dummy_64ch.synth).
  2. 정의에 맞게 보정한다.
     - 어깨: '닿음'인데 약하면 어깨가 닿은 실측 녹화의 그쪽 어깨 모양을 넣고, '안 닿음'이면 0.
     - 엉덩이: 비율이 정의 범위 밖이면 좌우 엉덩이 채널 배율을 바꿔 범위 안으로 맞춘다 (엉덩이 합은 유지).
  3. 위 기준을 다시 검사해서 통과한 녹화만 저장한다.
  재료 녹화 주인(+어깨 재료 주인)을 Source 에 남긴다 (학습 때 테스트할 사람 재료를 빼기 위해).

출력: data/dummy/chair_64ch_posture_data_dummy.csv.gz  (seat_1..32, back_1..32, Label, Person, Source)
실행: python gen_dummy_spec.py [--persons 40 --trials 2 --seed 42]
"""
import argparse
import glob
import os

import numpy as np
import pandas as pd

import gen_dummy_64ch as G
from posture_names import POSTURE_ORDER, POSTURE_TO_PCODE

CH = [f"ch{i}" for i in range(64)]
SEAT = [f"seat_{i + 1}" for i in range(32)]
BACK = [f"back_{i + 1}" for i in range(32)]
HIP_L, HIP_R = list(range(0, 5)), list(range(5, 10))
SH_R, SH_L = list(range(56, 60)), list(range(60, 64))
BACK_LOW = list(range(32, 56))

TOUCH, NONE = 100.0, 20.0
HIP_MOST, HIP_BOTH = 0.65, 0.25
SEAT_MIN, TURTLE_BACK_MIN, FWD_BACK_MAX = 6000.0, 400.0, 100.0

# 자세별 정의: (오른 어깨, 왼 어깨, 엉덩이)  어깨: touch/none/any, 엉덩이: R/L/both/any
# 2026-10-25 수정: 다리 꼬기는 실측(5명 모두)에 맞춰 '꼰 쪽 무릎이 반대쪽 무릎의 25% 이하'로 정의한다.
#   실측 다리 꼬기는 어깨가 대부분 안 닿고 엉덩이 비율도 40~63% 로 제각각이라 어깨·엉덩이 조건은 두지 않는다.
#   (어깨 조건을 두면 실측 다리 꼬기가 '어깨가 빈' 거북목과 겹친다. 거북목은 양쪽 무릎이 다 닿아서 무릎으로 갈린다.)
KNEE_L, KNEE_R = list(range(24, 28)), list(range(28, 32))
KNEE_LIFT = 0.25
SPEC = {
    "cross_leg_right": ("any", "any", "any"),
    "cross_leg_left": ("any", "any", "any"),
    "lean_right": ("touch", "none", "both"),
    "lean_left": ("none", "touch", "both"),
    "turtle_neck": ("none", "none", "any"),
    "sitting_straight": ("touch", "touch", "both"),
    "lean_forward": ("none", "none", "any"),
    "not_sitting": ("none", "none", "any"),
}


def measure(X):
    m = X.mean(0)
    hr, hl = m[HIP_R].sum(), m[HIP_L].sum()
    return dict(seat=m[:32].sum(), back=m[32:].sum(), back_low=m[BACK_LOW].sum(),
                sh_r=m[SH_R].sum(), sh_l=m[SH_L].sum(), hip_r_share=hr / (hr + hl) if hr + hl > 1 else 0.5)


def spec_ok(posture, X):
    M = measure(X)
    if posture == "not_sitting":
        return M["seat"] + M["back"] <= 50
    if M["seat"] < SEAT_MIN:
        return False
    r, l, hip = SPEC[posture]
    for side, want in (("sh_r", r), ("sh_l", l)):
        if want == "touch" and M[side] < TOUCH:
            return False
        if want == "none" and M[side] > NONE:
            return False
    s = M["hip_r_share"]
    if hip == "R" and s < HIP_MOST:
        return False
    if hip == "L" and s > 1 - HIP_MOST:
        return False
    if hip == "both" and not (HIP_BOTH <= s <= 1 - HIP_BOTH):
        return False
    if posture == "turtle_neck" and M["back_low"] < TURTLE_BACK_MIN:
        return False
    if posture in ("cross_leg_right", "cross_leg_left"):
        m = X.mean(0)
        kr, kl = m[KNEE_R].sum(), m[KNEE_L].sum()
        up, down = (kr, kl) if posture == "cross_leg_right" else (kl, kr)
        if down < 100 or up > KNEE_LIFT * down:
            return False
    if posture == "lean_forward" and M["back"] > FWD_BACK_MAX:
        return False
    return True


def load(tdir):
    """자세별 재료(실측 녹화)와 어깨 재료(그쪽 어깨가 닿은 녹화의 어깨 4채널 시계열)."""
    tpl = {p: [] for p in POSTURE_ORDER}
    donors = {"R": [], "L": []}
    for f in sorted(glob.glob(os.path.join(tdir, "*.csv"))):
        if "_reject" in os.path.basename(f):
            continue
        d = pd.read_csv(f)
        p, who = str(d["posture"].iloc[0]), str(d["person"].iloc[0])
        X = d[CH].values.astype(float)
        M = measure(X)
        if p != "not_sitting" and M["seat"] < SEAT_MIN:
            continue
        if p == "lean_forward" and M["back"] > FWD_BACK_MAX:
            continue
        if p == "turtle_neck" and (M["back_low"] < TURTLE_BACK_MIN or max(M["sh_r"], M["sh_l"]) > 60):
            continue
        tpl[p].append((X, who))
        if p in ("sitting_straight", "lean_right", "lean_left", "cross_leg_right", "cross_leg_left"):
            if M["sh_r"] >= TOUCH * 1.5:
                donors["R"].append((X[:, SH_R], who))
            if M["sh_l"] >= TOUCH * 1.5:
                donors["L"].append((X[:, SH_L], who))
    return tpl, donors


def resample(a, n):
    idx = np.clip(np.round(np.linspace(0, len(a) - 1, n)).astype(int), 0, len(a) - 1)
    return a[idx]


def enforce(posture, X, donors, rng):
    """정의에 맞게 어깨·엉덩이 보정. 반환: (X, 어깨 재료 주인 목록)."""
    if posture == "not_sitting":
        return np.zeros_like(X), []
    X = X.copy()
    n = len(X)
    used = []
    r, l, hip = SPEC[posture]
    if posture == "lean_forward":
        X[:, 32:] = 0
    for want, chs, side in ((r, SH_R, "R"), (l, SH_L, "L")):
        if want == "none":
            X[:, chs] = 0
        elif want == "touch" and X[:, chs].mean(0).sum() < TOUCH * 1.3:
            src, who = donors[side][rng.integers(len(donors[side]))]
            target = rng.uniform(1.5, 4.0) * TOUCH
            shape = resample(src, n)
            shape = shape / max(shape.mean(0).sum(), 1.0) * target
            X[:, chs] = shape * rng.normal(1.0, 0.05, shape.shape)
            used.append(who)
    hr, hl = X[:, HIP_R].mean(0).sum(), X[:, HIP_L].mean(0).sum()
    if hr + hl > 1 and hip != "any":
        s = hr / (hr + hl)
        lo, hi = {"R": (HIP_MOST, 0.85), "L": (0.15, 1 - HIP_MOST), "both": (0.35, 0.65)}[hip]
        if not (lo <= s <= hi):
            t = rng.uniform(lo + 0.02, hi - 0.02)
            if hl < 1:                                     # 왼쪽이 비어 있으면 오른쪽을 좌우 대칭으로 옮겨 온다
                X[:, HIP_L] = X[:, HIP_R][:, ::-1] * 0.3
                hl = X[:, HIP_L].mean(0).sum()
            if hr < 1:
                X[:, HIP_R] = X[:, HIP_L][:, ::-1] * 0.3
                hr = X[:, HIP_R].mean(0).sum()
            H = hr + hl
            X[:, HIP_R] *= t * H / hr
            X[:, HIP_L] *= (1 - t) * H / hl
    X = np.clip(np.round(X), 0, G.MAXV)
    X[X < 3] = 0
    return X, used


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--templates", default=os.path.join("data", "raw_64ch"))
    ap.add_argument("--out", default=os.path.join("data", "dummy", "chair_64ch_posture_data_dummy.csv.gz"))
    ap.add_argument("--persons", type=int, default=40)
    ap.add_argument("--trials", type=int, default=2)
    ap.add_argument("--seed", type=int, default=42)
    a = ap.parse_args()
    rng = np.random.default_rng(a.seed)
    tpl, donors = load(a.templates)
    # 거북목 재료 = 실측 거북목 등받이 x 모든 정자세 좌석 (거북목은 상체만 앞으로 나와서 좌석은 정자세와 같다).
    # 좌석 모양을 여러 사람 것으로 섞어야 모델이 좌석이 아니라 등받이(어깨만 빔)로 거북목을 가린다.
    seats = list(tpl["sitting_straight"])
    for f in sorted(glob.glob(os.path.join(a.templates, "*sitting_straight*_reject.csv"))):
        d = pd.read_csv(f)
        seats.append((d[CH].values.astype(float), str(d["person"].iloc[0])))
    mixed = []
    for Xt, wt in tpl["turtle_neck"]:
        for Xs, ws in seats:
            n = min(len(Xt), len(Xs))
            X = resample(Xt, n).copy()
            X[:, :32] = resample(Xs, n)[:, :32]
            mixed.append((X, wt if wt == ws else f"{wt}+{ws}"))
    tpl["turtle_neck"] = mixed
    for p in POSTURE_ORDER:
        print(f"재료 {p:17s} {len(tpl[p])}개 ({', '.join(sorted({w for _, w in tpl[p]}))})")
    print(f"어깨 재료 오른쪽 {len(donors['R'])}개, 왼쪽 {len(donors['L'])}개")
    if not tpl["not_sitting"]:
        tpl["not_sitting"] = [(np.zeros((1300, 64)), "none")]

    frames, made, fail = [], 0, 0
    persons = [G.make_person(i + 1, rng) for i in range(a.persons)]
    for P in persons:
        for post in POSTURE_ORDER:
            for tr in range(1, a.trials + 1):
                ok = False
                for att in range(80):
                    Pq = P if att < 40 else dict(P, lr=0.0, ch_jit=np.ones(64), body=max(P["body"], 1.0), back_gain=1.0)
                    X, src = G.synth(post, tpl[post], Pq, rng)
                    X, used = enforce(post, X, donors, rng)
                    if spec_ok(post, X):
                        ok = True
                        break
                if not ok:
                    fail += 1
                    continue
                df = pd.DataFrame(X.astype(np.int32), columns=SEAT + BACK)
                df["Label"] = POSTURE_TO_PCODE[post]
                df["Person"] = P["id"]
                df["Source"] = "gen_" + "+".join([src] + used)
                frames.append(df)
                made += 1
    out = pd.concat(frames, ignore_index=True)
    out.to_csv(a.out, index=False, compression="gzip")
    print(f"\n생성 {made}녹화 (포기 {fail}) -> {a.out} ({len(out):,}행)")

    # 자체 점검: 저장한 녹화가 모두 정의를 지키는지 자세별 평균값으로 보여준다
    lab = {v: k for k, v in POSTURE_TO_PCODE.items()}
    m = out.groupby("Label")[SEAT + BACK].mean()
    print("\n자세             좌석합  등(허리+중간)  오른어깨  왼어깨  엉덩이오른쪽%")
    for code, row in m.iterrows():
        v = row.values
        hr, hl = v[5:10].sum(), v[0:5].sum()
        print(f"  {lab[code]:16s} {v[:32].sum():6.0f}  {v[32:56].sum():8.0f}  {v[56:60].sum():7.0f}  {v[60:64].sum():6.0f}"
              f"  {hr / (hr + hl) * 100 if hr + hl else 0:6.0f}%")


if __name__ == "__main__":
    main()
