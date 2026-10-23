"""
merge_dummy_8cls.py — 예전 7자세 더미 + 새 거북목 더미 -> 8자세 더미 CSV 하나로 합친다.

예전 더미(data/dummy/chair_64ch_posture_data_dummy.csv.gz, 2026-09-21)는 지금 기준과 두 군데가 다르다.
  1. 라벨이 옛 7종: p7 = 앉지 않음 (압력 전부 0). 지금은 p0 = 앉지 않음, p7 = 거북목.
     -> p7 을 p0 으로 바꾼다. 나머지 p1~p6 은 의미가 같다.
  2. 좌석 좌우가 방석 뒤집기 전 기준 (ch0~4 = 오른 엉덩이). 지금 매트는 반대 (ch0~4 = 왼 엉덩이).
     -> 좌석을 줄마다 뒤집는다: 엉덩이 ch0..9 / 허벅지 ch10..23 / 무릎 ch24..31.
        (매트를 뒤집으면 같은 자리가 같은 줄의 반대쪽 번호가 된다.)
  등받이는 예전 더미에서 만들어낸 값이고 좌우 차이가 거의 없어서 그대로 둔다.

거북목 더미는 gen_dummy_64ch.py --postures turtle_neck 결과 (실측 거북목 녹화를 재료로 변형).

실행 (저장소 루트에서):
    python gen_dummy_64ch.py --postures turtle_neck --persons 40 --trials 2 --out <폴더>
    python ml/merge_dummy_8cls.py --turtle-dir <폴더>
결과: data/dummy/chair_64ch_posture_data_dummy.csv.gz 를 8자세(p0~p7) 버전으로 덮어쓴다.
      컬럼: seat_1..32, back_1..32, Label, Person, Source(old7 / turtle)
"""

import argparse
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
DUMMY_GZ = ROOT / "data" / "dummy" / "chair_64ch_posture_data_dummy.csv.gz"
SEAT = [f"seat_{i + 1}" for i in range(32)]
BACK = [f"back_{i + 1}" for i in range(32)]
SEAT_ROWS = [(0, 9), (10, 23), (24, 31)]   # 엉덩이 / 허벅지 / 무릎 (ch 번호)


def seat_flip_index() -> list[int]:
    """새 ch k 자리에 들어갈 예전 ch 번호."""
    idx = list(range(32))
    for a, b in SEAT_ROWS:
        for k in range(a, b + 1):
            idx[k] = a + b - k
    return idx


def load_old(path: Path) -> pd.DataFrame:
    df = pd.read_csv(path)
    labels = set(df["Label"].astype(str))
    if "p0" in labels or "Source" in df.columns:
        raise SystemExit(f"{path.name} 은 이미 8자세 버전입니다 (p0 또는 Source 컬럼이 있음). "
                         "git 에서 예전 7자세 버전을 꺼내 --old 로 주세요.")
    p7 = df[df["Label"] == "p7"]
    if p7[SEAT + BACK].values.mean() > 5:   # 잡음 수준만 있어야 한다
        raise SystemExit("예전 더미의 p7 이 압력 0 이 아닙니다. 옛 '앉지 않음' 라벨이 맞는지 확인하세요.")
    df["Label"] = df["Label"].replace({"p7": "p0"})
    flip = seat_flip_index()
    df[SEAT] = df[[SEAT[i] for i in flip]].values
    if "Person" not in df.columns:
        df["Person"] = "dummy_v1"
    df["Source"] = "old7"
    return df[SEAT + BACK + ["Label", "Person", "Source"]]


def load_generated(gdir: Path) -> pd.DataFrame:
    """gen_dummy_64ch.py 로 만든 8자세 전체 (실측 녹화를 재료로, 합격 기준 + 어깨 기준 통과분)."""
    import sys
    sys.path.insert(0, str(ROOT))
    from posture_names import POSTURE_TO_PCODE
    files = sorted(gdir.rglob("*.csv"))
    if not files:
        raise SystemExit(f"{gdir} 에 더미 CSV 가 없습니다.")
    raw = pd.concat([pd.read_csv(f) for f in files], ignore_index=True)
    out = pd.DataFrame(raw[[f"ch{i}" for i in range(64)]].values, columns=SEAT + BACK)
    out["Label"] = raw["posture"].map(POSTURE_TO_PCODE).values
    out["Person"] = raw["person"].values
    out["Source"] = "gen_" + raw["template_person"].astype(str).values
    return out


def load_turtle(tdir: Path) -> pd.DataFrame:
    files = sorted(tdir.rglob("*.csv"))
    if not files:
        raise SystemExit(f"{tdir} 에 거북목 더미 CSV 가 없습니다.")
    raw = pd.concat([pd.read_csv(f) for f in files], ignore_index=True)
    if set(raw["posture"]) != {"turtle_neck"}:
        raise SystemExit(f"거북목이 아닌 자세가 섞여 있습니다: {sorted(set(raw['posture']))}")
    out = pd.DataFrame(raw[[f"ch{i}" for i in range(64)]].values, columns=SEAT + BACK)
    out["Label"] = "p7"
    out["Person"] = raw["person"].values
    out["Source"] = "turtle"
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--gen-dir", default="",
                    help="(권장) gen_dummy_64ch.py 로 만든 8자세 전체 폴더. 주면 예전 더미를 쓰지 않는다")
    ap.add_argument("--replace-turtle-dir", default="",
                    help="--old 더미의 거북목(p7)만 이 폴더(gen_dummy_64ch.py --postures turtle_neck)로 바꾼다")
    ap.add_argument("--turtle-dir", default="", help="gen_dummy_64ch.py --postures turtle_neck 결과 폴더")
    ap.add_argument("--old", default=str(DUMMY_GZ), help="예전 7자세 더미 csv.gz")
    ap.add_argument("--out", default=str(DUMMY_GZ))
    a = ap.parse_args()

    if a.replace_turtle_dir:
        cur = pd.read_csv(a.old)
        new_t = load_generated(Path(a.replace_turtle_dir))
        if set(new_t["Label"]) != {"p7"}:
            raise SystemExit("--replace-turtle-dir 에는 거북목만 있어야 합니다.")
        print(f"기존 거북목 {int((cur['Label'] == 'p7').sum()):,}행 -> 새 거북목 {len(new_t):,}행으로 교체")
        df = pd.concat([cur[cur["Label"] != "p7"], new_t], ignore_index=True)
    elif a.gen_dir:
        df = load_generated(Path(a.gen_dir))
    else:
        if not a.turtle_dir:
            raise SystemExit("--gen-dir 또는 --turtle-dir 가 필요합니다.")
        df = pd.concat([load_old(Path(a.old)), load_turtle(Path(a.turtle_dir))], ignore_index=True)
    missing = sorted({f"p{i}" for i in range(8)} - set(df["Label"]))
    if missing:
        raise SystemExit(f"없는 자세: {missing}")
    df[SEAT + BACK] = df[SEAT + BACK].astype(np.int32)

    # 점검: 좌석 좌우가 지금 매트 기준인지 (오른다리 꼬기 -> 오른 무릎 ch28~31 이 비어야 함)
    kr = df[df["Label"] == "p3"][[SEAT[i] for i in range(28, 32)]].values.mean()
    kl = df[df["Label"] == "p3"][[SEAT[i] for i in range(24, 28)]].values.mean()
    print(f"점검 오른다리 꼬기: 오른 무릎(ch28~31) {kr:.0f} / 왼 무릎(ch24~27) {kl:.0f}  (오른쪽이 0 이어야 함)")
    assert kr < kl, "좌석 좌우 변환이 맞지 않습니다"

    df.to_csv(a.out, index=False, compression="gzip")
    print(f"저장: {a.out}  ({len(df):,}행)")
    print(df.groupby(["Label", "Source"]).size().to_string())
    sh = df[[f"back_{i}" for i in range(25, 33)]].sum(axis=1)   # 어깨 줄 = back_25..32 = ch56..63
    print("\n자세별 평균 어깨 줄 합:", sh.groupby(df["Label"]).mean().round(0).to_dict())


if __name__ == "__main__":
    main()
