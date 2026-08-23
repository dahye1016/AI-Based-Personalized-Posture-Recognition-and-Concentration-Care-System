"""
extract_64ch_dataset.py

p1~p8_pressure.json (80행 x 28열 고해상도 압력 매트릭스, 실측 시계열 데이터)를
우리 프로젝트의 64채널(방석 32 + 등받이 32) 포맷으로 변환합니다.

변환 방식:
- 80행을 절반으로 나눔: row 0~39 = 방석(seat) 영역, row 40~79 = 등받이(back) 영역
  (실제 측정에서 방석 쪽은 항상 압력이 잡히고 등받이 쪽은 거의 0에 가까워서,
   이 방향으로 나누는 게 맞다고 확인된 상태입니다.)
- 각 40행 x 28열 영역을 8행 x 4열 블록(총 32블록)으로 쪼개서, 블록 안 셀들의
  평균 압력을 그 블록의 대표값으로 사용합니다. (40/8=5, 28/4=7 -> 딱 나누어떨어짐)
- 결과: 프레임 하나당 seat_1~32, back_1~32 총 64개 값

원본 파일의 알려진 문제 (자동으로 처리함):
- 끝에 trailing comma가 붙어있는 JSON 문법 오류 -> 제거 후 파싱
- p2 파일은 정상 종료 지점 뒤에 다른 세션 데이터가 잘못 이어붙어 있음 -> 첫 정상
  종료 지점까지만 사용

프레임이 너무 많아서(파일당 13,000~13,800개, 0.06초 간격) 그대로 다 쓰면 거의
중복인 데이터가 쌓이므로, SAMPLE_STRIDE 간격으로 솎아냅니다 (기본 15 -> 약 0.9초
간격, 파일당 약 900개 샘플).
"""

import json
import numpy as np
import pandas as pd

SAMPLE_STRIDE = 15  # 몇 프레임마다 하나씩 뽑을지 (13799 / 15 ≈ 920개)
SEAT_ROWS = slice(0, 40)   # 방석 영역: row 0~39
BACK_ROWS = slice(40, 80)  # 등받이 영역: row 40~79
BLOCK_ROWS, BLOCK_COLS = 8, 4  # 각 영역을 8x4 = 32블록으로 분할


def load_pressure_json(path):
    """trailing comma 오류, 세션 이어붙음 오류를 자동으로 복구해서 로드."""
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    marker = "]]},]}"
    idx = content.find(marker)
    tail_ok_len = idx + len(marker) if idx != -1 else -1
    leftover = len(content.rstrip()) - tail_ok_len if idx != -1 else 0

    if idx != -1 and leftover > 5:
        # 정상 종료 지점 뒤에 다른 세션이 이어붙은 경우 -> 거기까지만 사용
        truncated = content[:idx] + "]]}]}"
        return json.loads(truncated)

    c = content.rstrip()
    if c.endswith(",]}"):
        c = c[:-3] + "]}"
    elif c.endswith(","):
        c = c[:-1] + "]}"
    elif not c.endswith("]}"):
        c = c + "]}"
    return json.loads(c)


def matrix_to_32(matrix_region: np.ndarray) -> np.ndarray:
    """40x28 영역을 8x4 블록으로 나눠 블록별 평균 32개 값으로 축약."""
    h, w = matrix_region.shape  # 40, 28
    bh, bw = h // BLOCK_ROWS, w // BLOCK_COLS  # 5, 7
    reshaped = matrix_region.reshape(BLOCK_ROWS, bh, BLOCK_COLS, bw)
    block_means = reshaped.mean(axis=(1, 3))  # (8, 4)
    return block_means.flatten()  # 32개


def extract_posture(file_index: int) -> pd.DataFrame:
    path = f"p{file_index}_pressure.json"
    print(f"[{path}] 로드 중...")
    data = load_pressure_json(path)
    frames = data["pressureData"]
    print(f"  총 프레임 수: {len(frames)}, {SAMPLE_STRIDE}프레임마다 샘플링")

    rows = []
    for i in range(0, len(frames), SAMPLE_STRIDE):
        mat = np.array(frames[i]["pressureMatrix"], dtype=np.float32)  # (80, 28)
        seat_32 = matrix_to_32(mat[SEAT_ROWS])
        back_32 = matrix_to_32(mat[BACK_ROWS])
        combined = np.concatenate([seat_32, back_32])  # 64개
        rows.append(combined)

    cols = [f"seat_{i+1}" for i in range(32)] + [f"back_{i+1}" for i in range(32)]
    df = pd.DataFrame(rows, columns=cols)
    df["Label"] = f"p{file_index}"
    print(f"  -> {len(df)}개 샘플 추출 완료 (label=p{file_index})")
    return df


def main():
    all_dfs = []
    for i in range(1, 9):
        try:
            df = extract_posture(i)
            all_dfs.append(df)
        except Exception as e:
            print(f"  ⚠️ p{i} 처리 실패: {e}")

    final_df = pd.concat(all_dfs, ignore_index=True)
    out_path = "chair_64ch_posture_data.csv"
    final_df.to_csv(out_path, index=False, encoding="utf-8-sig")

    print("\n" + "=" * 60)
    print(f"✅ 완료: {out_path}")
    print(f"총 샘플 수: {len(final_df)}")
    print("자세별 샘플 수:")
    print(final_df["Label"].value_counts().sort_index())
    print("=" * 60)


if __name__ == "__main__":
    main()
