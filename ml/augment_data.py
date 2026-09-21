"""
augment_data.py — 32채널 방석 매트 실측 데이터 증강기 (Mixup 중심)

압력 매트 고장으로 추가 수집이 불가능한 상황에서, 3명(예원·아로·다혜)의
7자세 실측만으로 학습 가능한 규모의 데이터셋을 만든다.

입력 : data/raw/{person}_{posture}_{trial}.csv
        컬럼 = frame, timestamp, ch0..ch31, person, posture, trial
출력 : data/augmented/augmented_dataset.csv  (원본 컬럼 + source)
        data/augmented/summary.json

증강 계열(source 컬럼)
    original      원본 프레임 그대로
    flip          좌우 반전 + 라벨 스왑
    mixup2/3      같은 자세 안에서 2~3개 녹화를 alpha 가중평균
    mixup2+jitter 위 결과에 스케일/노이즈/채널드롭 적용

채널 배치 (ch0 이 몸 바깥)
    0~4   오른엉덩이   5~9   왼엉덩이
    10~16 오른허벅지   17~23 왼허벅지
    24~27 오른무릎     28~31 왼무릎

좌우 반전 규칙 — 부위 '안'에서도 순서를 뒤집는다.
    실측 채널별 zero-rate 가 부위마다 좌우 대칭으로 단조 변화한다.
        오른엉덩이 [52.5 29.3 23.8 16.5 14.7] %  ← ch0 이 가장 자주 0
        왼엉덩이   [16.7 19.9 22.2 27.4 54.2] %  ← ch9 가 가장 자주 0
        오른허벅지 [43.3 28.2 12.2 10.0 10.0 10.0 27.5] %
        왼허벅지   [16.2 13.3 13.3 13.4 13.5 22.4 43.8] %  ← ch23 이 가장 자주 0
        오른무릎   [61.6 34.3 22.5 45.9] %
        왼무릎     [55.8 43.4 43.8 79.1] %  ← ch31 이 가장 자주 0
    즉 "몸 바깥"에 해당하는 채널은 오른쪽 부위에서는 첫 인덱스(ch0/ch10/ch24),
    왼쪽 부위에서는 마지막 인덱스(ch9/ch23/ch31)다. 따라서 부위를 교환할 때
    부위 안 순서도 뒤집어야 바깥↔바깥, 안쪽↔안쪽이 맞물린다.

    결과적으로 반전은 "가로 줄 세 개를 각각 뒤집기"와 정확히 같다.
        엉덩이 줄 ch0..ch9 뒤집기 / 허벅지 줄 ch10..ch23 뒤집기 / 무릎 줄 ch24..ch31 뒤집기
    매트가 좌→우로 이어지는 3열 배선이라는 물리 구조와 일치한다.

사용 예:
    python ml/augment_data.py
    python ml/augment_data.py --target-multiplier 30 --seed 7
    python ml/augment_data.py --no-balance --dry-run

필요 패키지: numpy, pandas
"""

import argparse
import glob
import itertools
import json
import os
import sys
from collections import Counter, defaultdict

try:
    import numpy as np
    import pandas as pd
except ImportError:
    sys.exit("numpy / pandas 가 없습니다.  pip install numpy pandas")


# =====================================================================
# 0. 상수
# =====================================================================
N_CH = 32
CH_COLS = [f"ch{i}" for i in range(N_CH)]
OUT_COLS = ["frame", "timestamp"] + CH_COLS + ["person", "posture", "trial", "source"]

ADC_MAX = 4095          # 12bit ADC 상한
NOISE_CUT = 20          # 펌웨어 노이즈컷: raw < 20 -> 0

# 좌우 반전으로 서로 교환되는 부위 쌍 (오른쪽 슬라이스, 왼쪽 슬라이스)
REGION_PAIRS = [
    ("hip",   (0, 5),   (5, 10)),
    ("thigh", (10, 17), (17, 24)),
    ("knee",  (24, 28), (28, 32)),
]

# 좌우 반전 시 라벨 스왑 (없으면 유지)
LABEL_SWAP = {
    "cross_leg_right": "cross_leg_left",
    "cross_leg_left":  "cross_leg_right",
    "lean_right":      "lean_left",
    "lean_left":       "lean_right",
}

# 전 채널 0 이라 증강해도 정보가 늘지 않는 자세 — 원본만 사용
ZERO_POSTURES = {"not_sitting"}

# 자세가 아닌 하드웨어 점검용 녹화 — 데이터셋에서 제외
EXCLUDE_POSTURES = {"press_check"}


def build_flip_index():
    """좌우 반전 채널 순열. 부위 교환 + 부위 안 순서 뒤집기."""
    idx = np.empty(N_CH, dtype=np.int64)
    for _, (ra, rb), (la, lb) in REGION_PAIRS:
        idx[ra:rb] = np.arange(la, lb)[::-1]   # 오른쪽 자리 <- 뒤집은 왼쪽
        idx[la:lb] = np.arange(ra, rb)[::-1]   # 왼쪽 자리 <- 뒤집은 오른쪽
    assert np.array_equal(idx[idx], np.arange(N_CH)), "반전은 두 번 적용하면 원래대로여야 한다"
    return idx


FLIP_INDEX = build_flip_index()


# =====================================================================
# 1. 로드
# =====================================================================
class Recording:
    """녹화 한 건 = (person, posture, trial) 하나의 CSV."""

    __slots__ = ("person", "posture", "trial", "values", "timestamps", "flipped")

    def __init__(self, person, posture, trial, values, timestamps, flipped=False):
        self.person = person
        self.posture = posture
        self.trial = trial
        self.values = values            # (n_frames, 32) float32
        self.timestamps = timestamps    # (n_frames,) float64
        self.flipped = flipped

    @property
    def key(self):
        tag = "F" if self.flipped else ""
        return f"{self.person}{tag}_{self.posture}_{self.trial}"

    @property
    def n(self):
        return self.values.shape[0]

    def flip(self):
        """좌우 반전본. 라벨도 스왑된 새 Recording 을 돌려준다."""
        return Recording(
            person=self.person,
            posture=LABEL_SWAP.get(self.posture, self.posture),
            trial=self.trial,
            values=self.values[:, FLIP_INDEX].copy(),
            timestamps=self.timestamps,
            flipped=True,
        )


def load_recordings(raw_dir):
    """data/raw/*.csv 전체 스캔. discarded/ 는 건드리지 않는다."""
    paths = sorted(glob.glob(os.path.join(raw_dir, "*.csv")))
    if not paths:
        sys.exit(f"{raw_dir} 에 CSV 가 없습니다.")

    recs, skipped = [], []
    for path in paths:
        df = pd.read_csv(path)
        missing = [c for c in CH_COLS + ["person", "posture", "trial"] if c not in df.columns]
        if missing:
            skipped.append((os.path.basename(path), f"컬럼 누락 {missing[:3]}"))
            continue

        posture = str(df["posture"].iloc[0])
        if posture in EXCLUDE_POSTURES:
            skipped.append((os.path.basename(path), f"자세 아님({posture})"))
            continue

        recs.append(Recording(
            person=str(df["person"].iloc[0]),
            posture=posture,
            trial=int(df["trial"].iloc[0]),
            values=df[CH_COLS].to_numpy(dtype=np.float32),
            timestamps=(df["timestamp"].to_numpy(dtype=np.float64)
                        if "timestamp" in df.columns else np.zeros(len(df))),
        ))
    return recs, skipped


# =====================================================================
# 2. 조합 열거 — 같은 posture 안에서만
# =====================================================================
def alpha_grid(way, step):
    """합이 1, 각 항이 step 이상인 alpha 조합. 외삽 없음(0 <= a <= 1)."""
    n = int(round(1.0 / step))
    if way == 2:
        return [(k / n, (n - k) / n) for k in range(1, n)]
    combos = []
    for a in range(1, n - 1):
        for b in range(1, n - a):
            combos.append((a / n, b / n, (n - a - b) / n))
    return combos


def enumerate_entries(pool, step, max_way):
    """
    한 자세의 녹화 pool 에서 (녹화 조합, alpha) 항목을 way 별로 모두 만든다.
    - 서로 다른 사람 조합, 같은 사람의 다른 trial 조합, 반전본 조합 모두 포함
    - 2-way(2개 섞기)와 3-way(3개 섞기)를 나눠서 돌려준다. 3-way 조합 수가
      2-way 보다 훨씬 많아서, 한 통에 넣으면 목표 수를 3-way 가 다 먹는다.
    """
    by_way = {}
    for way in range(2, min(max_way, len(pool)) + 1):
        grid = alpha_grid(way, step)
        entries = [(combo, alphas)
                   for combo in itertools.combinations(range(len(pool)), way)
                   for alphas in grid]
        if entries:
            by_way[way] = entries
    return by_way


def allocate(total, probs):
    """total 개를 probs 비율로 정수 분배 (최대잉여법). 합은 정확히 total."""
    raw = probs * total
    base = np.floor(raw).astype(np.int64)
    rest = int(total - base.sum())
    if rest > 0:
        base[np.argsort(-(raw - base))[:rest]] += 1
    return base


def person_tag(pool, combo, alphas):
    """실제 사람 단위로 가중치를 합쳐 person 컬럼 문자열을 만든다.

    예) mix_yewon0.5_aro0.3_dahye0.2
    반전본 기여분은 원래 사람에게 합산된다. train/test 를 사람 단위로 나눌 때
    이 문자열에서 사람 이름만 뽑아 쓰면 된다.
    """
    weight = defaultdict(float)
    for i, a in zip(combo, alphas):
        weight[pool[i].person] += a
    parts = sorted(weight.items(), key=lambda kv: (-kv[1], kv[0]))
    return "mix_" + "_".join(f"{p}{w:.1f}" for p, w in parts)


# =====================================================================
# 3. 변형
# =====================================================================
def apply_jitter(x, rng, scale_lo, scale_hi, noise_sigma, drop_max):
    """전체 스케일 x0.7~1.4 -> 값의 3% 가우시안 노이즈 -> 채널 0~3개 드롭."""
    n = x.shape[0]
    x = x * rng.uniform(scale_lo, scale_hi, size=(n, 1)).astype(np.float32)
    x = x + x * rng.normal(0.0, noise_sigma, size=x.shape).astype(np.float32)

    n_drop = rng.integers(0, drop_max + 1, size=n)
    for k in range(1, drop_max + 1):
        rows = np.flatnonzero(n_drop == k)
        if rows.size:
            cols = np.argsort(rng.random((rows.size, N_CH)), axis=1)[:, :k]
            x[rows[:, None], cols] = 0.0
    return x


def finalize(x):
    """0~4095 클리핑 후 20 미만은 0 (펌웨어 노이즈컷과 동일). 정수화."""
    x = np.clip(x, 0.0, ADC_MAX)
    x[x < NOISE_CUT] = 0.0
    return np.rint(x).astype(np.int16)


# =====================================================================
# 4. 생성
# =====================================================================
def make_rows(values, timestamps, person, posture, trial, source, frame0=0):
    df = pd.DataFrame(values, columns=CH_COLS)
    df.insert(0, "timestamp", timestamps)
    df.insert(0, "frame", np.arange(frame0, frame0 + len(df)))
    df["person"] = person
    df["posture"] = posture
    df["trial"] = trial
    df["source"] = source
    return df[OUT_COLS]


def generate_mixup(pool, posture, target, args, rng, stats):
    """한 자세에 대해 target 개가 찰 때까지 (조합, alpha) 항목을 순환하며 생성.

    목표 수는 way(2-way / 3-way) 별로 균등 분배한다.
    """
    if len(pool) < 2 or target <= 0:
        return []

    by_way = enumerate_entries(pool, args.alpha_step, args.max_way)
    if not by_way:
        return []

    all_entries = [e for entries in by_way.values() for e in entries]
    stats["entries"][posture] = len(all_entries)
    stats["donor_combos"][posture] = len({e[0] for e in all_entries})
    stats["three_person_combos"][posture] = len({
        e[0] for e in all_entries
        if len({pool[i].person for i in e[0]}) == 3
    })

    ways = sorted(by_way)
    per_way, way_extra = divmod(target, len(ways))

    frames, trial_no, used_entries = [], 0, 0
    for w_i, way in enumerate(ways):
        entries = by_way[way]
        way_target = per_way + (1 if w_i < way_extra else 0)

        # 조합마다 몇 개를 뽑을지 — 서로 다른 사람이 많이 섞인 조합에 가중치를 준다.
        # (같은 사람 trial 끼리 섞은 것도 쓰지만, 사람 간 일반화에는 교차 조합이 더 값지다)
        n_persons = np.array([len({pool[i].person for i in c}) for c, _ in entries],
                             dtype=np.float64)
        w = n_persons ** args.person_diversity
        quota = allocate(way_target, w / w.sum())

        order = rng.permutation(len(entries))
        for e_idx in order:
            n_take = int(quota[e_idx])
            if n_take == 0:
                continue
            combo, alphas = entries[e_idx]

            acc = np.zeros((n_take, N_CH), dtype=np.float32)
            ts = np.zeros(n_take, dtype=np.float64)
            for i, a in zip(combo, alphas):
                rec = pool[i]
                pick = rng.integers(0, rec.n, size=n_take)
                acc += a * rec.values[pick]
                ts += a * rec.timestamps[pick]

            if rng.random() < args.jitter_prob:
                acc = apply_jitter(acc, rng, args.scale_lo, args.scale_hi,
                                   args.noise_sigma, args.drop_max)
                source = f"mixup{way}+jitter"
            else:
                source = f"mixup{way}"

            trial_no += 1
            used_entries += 1
            frames.append(make_rows(
                finalize(acc), ts,
                person=person_tag(pool, combo, alphas),
                posture=posture,
                trial=trial_no,          # 조합마다 다른 합성 trial 번호
                source=source,
            ))

    stats["used_entries"][posture] = used_entries
    return frames


# =====================================================================
# 5. 요약
# =====================================================================
def print_summary(recs, skipped, before, after, stats, args, out_path):
    line = "=" * 72
    print(line)
    print("증강 요약")
    print(line)

    if skipped:
        print("\n[제외한 파일]")
        for name, why in skipped:
            print(f"  - {name:<34} {why}")

    print(f"\n[원본 녹화] {len(recs)}건")
    for posture in sorted({r.posture for r in recs}):
        trials = [r for r in recs if r.posture == posture]
        who = ", ".join(f"{r.person}#{r.trial}({r.n})" for r in sorted(
            trials, key=lambda r: (r.person, r.trial)))
        print(f"  {posture:<18} {len(trials)}녹화 {sum(r.n for r in trials):>7}프레임  {who}")

    print(f"\n[Mixup 조합]")
    print(f"  {'자세':<18} {'기증 녹화':>9} {'고유 조합':>9} {'3인 조합':>9} "
          f"{'(조합,alpha)':>13} {'실사용':>9}")
    for posture in sorted(stats["entries"]):
        print(f"  {posture:<18} {stats['pool'][posture]:>9} "
              f"{stats['donor_combos'][posture]:>9} "
              f"{stats['three_person_combos'][posture]:>9} "
              f"{stats['entries'][posture]:>13} "
              f"{stats['used_entries'][posture]:>9}")
    print(f"  {'합계':<18} {'':>9} {sum(stats['donor_combos'].values()):>9} "
          f"{sum(stats['three_person_combos'].values()):>9} "
          f"{sum(stats['entries'].values()):>13} "
          f"{sum(stats['used_entries'].values()):>9}")

    print(f"\n[증강 전후 샘플 수]  배수 x{args.target_multiplier}"
          f"  ({'자세별 균형' if args.balance else '자세별 원본 비례'})")
    print(f"  {'자세':<18} {'증강 전':>10} {'증강 후':>10} {'배수':>7}")
    total_b = total_a = 0
    for posture in sorted(after):
        b, a = before.get(posture, 0), after[posture]
        total_b += b
        total_a += a
        print(f"  {posture:<18} {b:>10,} {a:>10,} {a / max(b, 1):>6.1f}x")
    print(f"  {'합계':<18} {total_b:>10,} {total_a:>10,} {total_a / max(total_b, 1):>6.1f}x")

    print(f"\n[증강 계열별]")
    for src, cnt in sorted(stats["source"].items(), key=lambda kv: -kv[1]):
        print(f"  {src:<18} {cnt:>10,}")

    print(f"\n[사람 조합 태그] 고유 {stats['n_person_tags']}종")
    for tag, cnt in stats["person_tags"].most_common(8):
        print(f"  {tag:<38} {cnt:>10,}")
    if stats["n_person_tags"] > 8:
        print(f"  ... 외 {stats['n_person_tags'] - 8}종")

    lo, hi = min(after.values()), max(after.values())
    ratio = hi / max(lo, 1)
    print(f"\n[자세별 불균형] 최대/최소 = {ratio:.2f}x  (최소 {lo:,} / 최대 {hi:,})")
    if ratio > args.imbalance_warn:
        worst = [p for p, c in after.items() if c == lo]
        print(f"  !! 경고: 자세별 불균형이 {args.imbalance_warn}x 를 넘습니다. "
              f"부족한 자세 = {', '.join(worst)}")
        print(f"  !! 학습 시 class weight 나 오버샘플링을 쓰거나 --no-balance 설정을 재검토하세요.")
    else:
        print("  OK: 허용 범위 안입니다.")

    print(f"\n[출력] {out_path}")
    print(line)


# =====================================================================
# 6. main
# =====================================================================
def parse_args(argv=None):
    p = argparse.ArgumentParser(description="32채널 방석 매트 실측 데이터 Mixup 증강")
    p.add_argument("--raw-dir", default="data/raw")
    p.add_argument("--out-dir", default="data/augmented")
    p.add_argument("--target-multiplier", type=float, default=20.0,
                   help="자세별 목표 샘플 수 배수 (기본 20)")
    p.add_argument("--balance", dest="balance", action="store_true", default=True,
                   help="모든 자세를 같은 목표 수로 맞춘다 (기본)")
    p.add_argument("--no-balance", dest="balance", action="store_false",
                   help="자세별 원본 프레임 수에 비례해 목표를 잡는다")
    p.add_argument("--alpha-step", type=float, default=0.1,
                   help="alpha 간격 (기본 0.1)")
    p.add_argument("--max-way", type=int, default=3, choices=[2, 3],
                   help="한 번에 섞을 녹화 수 상한 (기본 3)")
    p.add_argument("--no-flip-donors", dest="flip_donors", action="store_false", default=True,
                   help="좌우 반전본을 mixup 기증 풀에 넣지 않는다")
    p.add_argument("--person-diversity", type=float, default=1.5,
                   help="조합의 서로 다른 사람 수에 주는 가중 지수 (0 이면 균등, 기본 1.5)")
    p.add_argument("--jitter-prob", type=float, default=0.8,
                   help="mixup 결과에 스케일/노이즈/드롭을 적용할 확률 (기본 0.8)")
    p.add_argument("--scale-lo", type=float, default=0.7)
    p.add_argument("--scale-hi", type=float, default=1.4)
    p.add_argument("--noise-sigma", type=float, default=0.03, help="값 대비 노이즈 표준편차")
    p.add_argument("--drop-max", type=int, default=3, help="랜덤 0 으로 만들 채널 수 상한")
    p.add_argument("--imbalance-warn", type=float, default=1.5,
                   help="자세별 최대/최소 비가 이 값을 넘으면 경고")
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--dry-run", action="store_true", help="파일을 쓰지 않고 계획만 출력")
    args = p.parse_args(argv)

    if not 0.0 < args.alpha_step <= 0.5:
        p.error("--alpha-step 은 0 초과 0.5 이하여야 합니다.")
    if abs(round(1 / args.alpha_step) - 1 / args.alpha_step) > 1e-9:
        p.error("--alpha-step 은 1 을 정수로 나눠야 합니다 (예: 0.1, 0.05).")
    return args


def main(argv=None):
    args = parse_args(argv)
    rng = np.random.default_rng(args.seed)

    recs, skipped = load_recordings(args.raw_dir)
    postures = sorted({r.posture for r in recs})
    augmentable = [p for p in postures if p not in ZERO_POSTURES]

    before = Counter()
    for r in recs:
        before[r.posture] += r.n

    # --- 자세별 목표 샘플 수 -------------------------------------------------
    aug_frames = [before[p] for p in augmentable]
    base = float(np.median(aug_frames)) if aug_frames else 0.0
    targets = {
        p: int(round(args.target_multiplier * (base if args.balance else before[p])))
        for p in augmentable
    }

    # --- 기증 풀: 원본 + 좌우 반전본 (반전본은 라벨이 바뀌어 반대쪽 자세로 들어간다) ---
    pool = defaultdict(list)
    for r in recs:
        pool[r.posture].append(r)
    flips = []
    for r in recs:
        if r.posture in ZERO_POSTURES:
            continue                     # 전 채널 0 -> 반전해도 동일
        f = r.flip()
        flips.append(f)
        if args.flip_donors:
            pool[f.posture].append(f)

    stats = {
        "entries": {}, "donor_combos": {}, "three_person_combos": {}, "used_entries": {},
        "pool": {p: len(pool[p]) for p in augmentable},
        "source": Counter(), "person_tags": Counter(), "n_person_tags": 0,
    }

    # --- 1) 원본 -------------------------------------------------------------
    blocks = [make_rows(finalize(r.values.copy()), r.timestamps,
                        r.person, r.posture, r.trial, "original") for r in recs]

    # --- 2) 좌우 반전 + 라벨 스왑 ---------------------------------------------
    blocks += [make_rows(finalize(f.values.copy()), f.timestamps,
                         f"flip_{f.person}", f.posture, f.trial, "flip") for f in flips]

    # --- 3) Mixup ------------------------------------------------------------
    for posture in augmentable:
        blocks += generate_mixup(pool[posture], posture, targets[posture], args, rng, stats)

    out = pd.concat(blocks, ignore_index=True)
    after = Counter(out["posture"])
    stats["source"] = Counter(out["source"])
    stats["person_tags"] = Counter(out["person"])
    stats["n_person_tags"] = len(stats["person_tags"])

    out_path = os.path.join(args.out_dir, "augmented_dataset.csv")
    if not args.dry_run:
        os.makedirs(args.out_dir, exist_ok=True)
        out.to_csv(out_path, index=False)
        with open(os.path.join(args.out_dir, "summary.json"), "w", encoding="utf-8") as fp:
            json.dump({
                "seed": args.seed,
                "target_multiplier": args.target_multiplier,
                "balance": args.balance,
                "alpha_step": args.alpha_step,
                "max_way": args.max_way,
                "flip_donors": args.flip_donors,
                "flip_index": FLIP_INDEX.tolist(),
                "before": dict(before),
                "after": dict(after),
                "targets": targets,
                "donor_pool": stats["pool"],
                "donor_combos": stats["donor_combos"],
                "three_person_combos": stats["three_person_combos"],
                "alpha_entries": stats["entries"],
                "alpha_entries_used": stats["used_entries"],
                "person_diversity": args.person_diversity,
                "by_source": dict(stats["source"]),
                "n_person_tags": stats["n_person_tags"],
                "excluded_files": [{"file": f, "reason": w} for f, w in skipped],
            }, fp, ensure_ascii=False, indent=2)
    else:
        out_path += "  (dry-run: 저장하지 않음)"

    print_summary(recs, skipped, before, after, stats, args, out_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
