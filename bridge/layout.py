"""
PoseLab Seat 방석센서 32채널 물리 배치 정의.

이 파일 하나만 바꾸면 특징 추출/히트맵/자세판정이 전부 따라옵니다.

┌─────────────────────────────────────────────────────────┐
│  센서 실물 배치 (설치 도면 기준, 전체 386mm x 382mm)      │
│                                                          │
│   ROW 2 (뒤/등쪽)   24 25 26 27 | 28 29 30 31   (4+4)   │
│   ROW 1 (중간)   10 11 12 13 14 15 16 | 17 ... 23 (7+7) │
│   ROW 0 (앞/무릎쪽)  0  1  2  3  4 |  5  6  7  8  9 (5+5)│
│                          ▲ 케이블(커넥터) 출구            │
└─────────────────────────────────────────────────────────┘

⚠️ 확인 필요 (일요일 실물 연결 시 5분이면 검증됨):
   1. ROW0 가 앞(무릎)인지 뒤(엉덩이)인지 → ORIENTATION_FLIP 으로 뒤집기
   2. Left(En1) 커넥터가 화면상 왼쪽인지 → MIRROR_LR 로 뒤집기
   검증 방법: 벤더 그래프 페이지(wiki1.mdex.co.kr)에서 방석 앞쪽 한 곳만
   손으로 누르고, 어느 채널 번호의 raw 값이 튀는지 보면 됩니다.
"""

N_CHANNELS = 32

# 방석 전체 크기 (mm)
WIDTH_MM = 386.0
HEIGHT_MM = 382.0

# 행별 채널 번호 (좌측 그룹, 우측 그룹)
ROWS = {
    0: (list(range(0, 5)),   list(range(5, 10))),    # 5 + 5
    1: (list(range(10, 17)), list(range(17, 24))),   # 7 + 7
    2: (list(range(24, 28)), list(range(28, 32))),   # 4 + 4
}

# 행의 세로 위치 (0 = 앞쪽 가장자리, HEIGHT_MM = 뒤쪽 가장자리)
ROW_Y_MM = {0: 40.0, 1: 191.0, 2: 342.0}

# 배치 보정 플래그 — 실물 확인 후 여기만 바꾸면 됩니다
ORIENTATION_FLIP = False   # True 면 앞뒤(y) 반전
MIRROR_LR = False          # True 면 좌우(x) 반전


def _build_positions():
    """채널 번호 -> (x_mm, y_mm) 좌표 맵을 만든다."""
    pos = {}
    for row, (left, right) in ROWS.items():
        y = ROW_Y_MM[row]
        # 좌측 그룹은 x 0 ~ (중앙-여백), 우측 그룹은 (중앙+여백) ~ WIDTH
        half = WIDTH_MM / 2.0
        gap = 18.0  # 중앙 FPC 배선이 지나가는 빈 공간
        for group, x0, x1 in (
            (left, 12.0, half - gap),
            (right, half + gap, WIDTH_MM - 12.0),
        ):
            n = len(group)
            for i, ch in enumerate(group):
                x = x0 if n == 1 else x0 + (x1 - x0) * i / (n - 1)
                pos[ch] = (x, y)

    if ORIENTATION_FLIP:
        pos = {ch: (x, HEIGHT_MM - y) for ch, (x, y) in pos.items()}
    if MIRROR_LR:
        pos = {ch: (WIDTH_MM - x, y) for ch, (x, y) in pos.items()}
    return pos


POSITIONS = _build_positions()

# 자주 쓰는 그룹 인덱스 (특징 추출용)
FRONT_CH = ROWS[0][0] + ROWS[0][1]
MID_CH = ROWS[1][0] + ROWS[1][1]
BACK_CH = ROWS[2][0] + ROWS[2][1]
LEFT_CH = ROWS[0][0] + ROWS[1][0] + ROWS[2][0]
RIGHT_CH = ROWS[0][1] + ROWS[1][1] + ROWS[2][1]

if ORIENTATION_FLIP:
    FRONT_CH, BACK_CH = BACK_CH, FRONT_CH
if MIRROR_LR:
    LEFT_CH, RIGHT_CH = RIGHT_CH, LEFT_CH

# 노드 1개가 대표하는 면적 (cm²) — Area 계산용 근사값
NODE_AREA_CM2 = (WIDTH_MM / 10.0) * (HEIGHT_MM / 10.0) / N_CHANNELS

assert len(POSITIONS) == N_CHANNELS, "채널 배치 정의가 32개가 아닙니다"
