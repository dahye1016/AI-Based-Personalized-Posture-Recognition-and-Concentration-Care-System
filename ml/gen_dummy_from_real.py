"""실측 27개 녹화 + 판정 기준으로 7자세 더미 생성.

가상 인물 1명 = 실측 인물 패턴의 가중 혼합(Dirichlet) × 체중 배율.
  - 같은 가상 인물은 7자세 모두 같은 혼합 가중치·체중 배율을 쓴다 (사람 단위 일관성).
  - 자세 강도: 정자세 패턴 + k × (자세 패턴 − 정자세 패턴), k ~ U(0.85, 1.15).
시간 변화 = 같은 자세 실측 녹화 하나의 상대 잔차(흔들림)를 입힌다 (무작위 녹화, 무작위 뒤집기).
센서 특성 = 0~4095 정수, 20 미만은 0 (실측 양수 최솟값이 20).
검증 = 녹화마다 판정 기준 통과율 ≥ 95% 아니면 다시 생성.
"""
import sys, numpy as np, pandas as pd
src, out, n_people, seed = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
rng = np.random.default_rng(seed)
df = pd.read_csv(src)
if len(sys.argv) > 5: df = df[df.person != sys.argv[5]]   # 검증용: 한 사람 빼고 생성
CH = [f"ch{i}" for i in range(64)]
P = ["sitting_straight","lean_forward","lean_left","lean_right","cross_leg_left","cross_leg_right","not_sitting"]
people = sorted(df.person.unique())
rec = {}   # (posture, person) -> X (frames x 64), timestamps
for (p, q), d in df.groupby(["posture", "person"]):
    rec[(p, q)] = (d[CH].to_numpy(float), d.timestamp.to_numpy(float))
mean = {k: v[0].mean(0) for k, v in rec.items()}
contact = {k: (v[0] > 0).mean(0) for k, v in rec.items()}  # 채널별 접촉률
intervals = [np.diff(v[1]) for v in rec.values() if len(v[1]) >= 1245]
MAXV = 4095; DEAD = 20; N = 1245

def feats(X):
    tot = X.sum(1)
    bl = X[:, list(range(37,42))+list(range(49,56))+list(range(60,64))].sum(1)
    br = X[:, list(range(32,37))+list(range(42,49))+list(range(56,60))].sum(1)
    back = bl + br
    kl = X[:, 24:28].sum(1); kr = X[:, 28:32].sum(1)
    with np.errstate(invalid="ignore", divide="ignore"):
        bL = np.where(back >= 100, bl / back * 100, np.nan)
        kR = np.where(kl + kr >= 100, kr / (kl + kr) * 100, np.nan)
    return tot, back, bL, kR

def classify(X):
    tot, back, bL, kR = feats(X)
    out = np.full(len(X), "sitting_straight", dtype=object)
    done = np.zeros(len(X), bool)
    for name, cond in [("not_sitting", tot < 100), ("lean_forward", back < 100),
                       ("cross_leg_left", kR >= 90), ("lean_left", bL >= 85),
                       ("cross_leg_right", kR <= 20), ("lean_right", bL <= 5)]:
        c = np.nan_to_num(cond, nan=False).astype(bool) & ~done
        out[c] = name; done |= c
    return out

def mix(p, w):
    have = [q for q in people if (p, q) in mean]
    ww = np.array([w[people.index(q)] for q in have]); ww /= ww.sum()
    m = sum(a * mean[(p, q)] for a, q in zip(ww, have))
    c = sum(a * contact[(p, q)] for a, q in zip(ww, have))
    return m, c, have, ww

def make(p, w, scale):
    if p == "not_sitting":
        X = np.zeros((N, 64))
        k = rng.poisson(2)                          # 실측: 8만 칸 중 0~4칸 20 안팎
        X[rng.integers(0, N, k), rng.integers(0, 64, k)] = rng.integers(20, 26, k)
        return X, "zeros+blips"
    m, c, have, ww = mix(p, w)
    # 접촉 마스크: 혼합 접촉률이 문턱(가상 인물·자세마다 0.35~0.65) 이상인 채널만 닿음.
    # 섞기만 하면 한 사람만 닿은 채널이 어중간한 값으로 채워져 접촉률이 실측보다 높아진다.
    on = c >= rng.uniform(0.35, 0.65)
    kept = m[on].sum(); m = np.where(on, m, 0) * (m.sum() / max(kept, 1))   # 전체 압력은 유지
    if p != "sitting_straight":
        base, _, _, _ = mix("sitting_straight", w)
        base = np.where(on, base, 0)
        k = rng.uniform(0.85, 1.15)
        m = np.clip(base + k * (m - base), 0, None)
    m = m * scale
    q = rng.choice(have, p=ww)                      # 흔들림 원본 녹화
    R, _ = rec[(p, q)]
    rel = (R - R.mean(0)) / (R.mean(0) + 30)
    if rng.random() < 0.5: rel = rel[::-1]
    start = rng.integers(0, max(1, len(rel) - N + 1)); rel = rel[start:start + N]
    if len(rel) < N: rel = np.vstack([rel, rel[::-1]])[:N]
    rel *= rng.uniform(0.8, 1.2)
    t = np.linspace(0, 1, N)[:, None]               # 천천히 변하는 자세 흐름 (채널별 ±3%)
    drift = 1 + 0.03 * np.sin(2*np.pi*(rng.uniform(0.3,1.5,64)*t + rng.uniform(0,1,64)))
    X = m * (1 + rel) * drift + rng.normal(0, 1, (N, 64)) * (0.01 * m + 2)
    return X, f"mix:{'+'.join(f'{a:.2f}{h}' for a, h in zip(ww, have))}|rel:{q}"

def finish(X):
    X = np.clip(np.rint(X), 0, MAXV); X[X < DEAD] = 0
    return X.astype(int)

rows, log = [], []
for i in range(n_people):
    pid = f"dummy{i+1:02d}"
    w = rng.dirichlet(np.full(len(people), 0.7)); scale = rng.uniform(0.8, 1.25)
    for p in P:
        for tries in range(1, 31):
            X, src_tag = make(p, w, scale); X = finish(X)
            acc = (classify(X) == p).mean()
            if acc >= 0.95: break
        log.append((pid, p, tries, round(acc * 100, 1), round(scale, 3)))
        iv = intervals[rng.integers(len(intervals))][:N-1]
        ts = 1793000000 + i * 1000 + P.index(p) * 60 + np.concatenate([[0], np.cumsum(iv)])[:N]
        f = pd.DataFrame(X, columns=CH)
        f.insert(0, "timestamp", np.round(ts, 6)); f.insert(0, "frame", np.arange(N))
        f["person"] = pid; f["posture"] = p; f["trial"] = 1; f["source"] = f"gen|{src_tag}|scale:{scale:.3f}"
        rows.append(f)
D = pd.concat(rows, ignore_index=True)
D.to_csv(out, index=False)
L = pd.DataFrame(log, columns=["person", "posture", "tries", "rule_acc", "scale"])
L.to_csv(out.replace(".csv", "_genlog.csv"), index=False)
print(len(D), "rows;", "max tries", L.tries.max(), "; min acc", L.rule_acc.min())
print(L.groupby("posture").rule_acc.agg(["mean", "min"]).round(1).to_string())
