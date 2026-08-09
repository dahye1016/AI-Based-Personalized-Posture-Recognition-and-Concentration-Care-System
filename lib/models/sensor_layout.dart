import 'dart:ui' show Offset;

/// PoseLab Seat 방석센서 32채널 물리 배치 정의.
///
/// ../poselab-review/bridge/layout.py 를 Dart 상수로 포팅한 것.
/// 이 파일 하나만 바꾸면 히트맵/특징추출/자세판정 좌표가 전부 따라온다.
///
/// ┌─────────────────────────────────────────────────────────┐
/// │  ROW 2 (뒤/등쪽)   24 25 26 27 | 28 29 30 31   (4+4)     │
/// │  ROW 1 (중간)   10 11 ... 16 | 17 ... 23        (7+7)    │
/// │  ROW 0 (앞/무릎쪽)  0 1 2 3 4 | 5 6 7 8 9        (5+5)   │
/// └─────────────────────────────────────────────────────────┘
///
/// ⚠️ 실물 방향은 아직 미검증. ROW0 이 앞인지, En1 커넥터가 왼쪽인지
///    확인되면 [orientationFlip] / [mirrorLR] 두 값만 바꿔서 뒤집는다.
class SensorLayout {
  SensorLayout._();

  static const int nChannels = 32;

  // 방석 전체 크기 (mm)
  static const double widthMm = 386.0;
  static const double heightMm = 382.0;

  // 실물 방향 미검증 — 확인 후 여기 두 값만 바꾸면 된다.
  static const bool orientationFlip = false; // true 면 앞뒤(y) 반전
  static const bool mirrorLR = false; // true 면 좌우(x) 반전

  /// 행별 (좌측 그룹, 우측 그룹) 채널 번호.
  static const Map<int, (List<int>, List<int>)> rows = {
    0: ([0, 1, 2, 3, 4], [5, 6, 7, 8, 9]), // 5 + 5
    1: ([10, 11, 12, 13, 14, 15, 16], [17, 18, 19, 20, 21, 22, 23]), // 7 + 7
    2: ([24, 25, 26, 27], [28, 29, 30, 31]), // 4 + 4
  };

  /// 행의 세로 위치 (0 = 앞쪽 가장자리, heightMm = 뒤쪽 가장자리).
  static const Map<int, double> rowYMm = {0: 40.0, 1: 191.0, 2: 342.0};

  /// 노드 1개가 대표하는 면적 (cm²) — 접촉 면적 계산용 근사값.
  static const double nodeAreaCm2 =
      (widthMm / 10.0) * (heightMm / 10.0) / nChannels;

  /// 채널 번호 -> (x_mm, y_mm) 좌표. index 가 채널 번호.
  static final List<Offset> positions = _buildPositions();

  static List<Offset> _buildPositions() {
    final pos = List<Offset>.filled(nChannels, Offset.zero);
    const half = widthMm / 2.0;
    const gap = 18.0; // 중앙 FPC 배선이 지나가는 빈 공간
    const margin = 12.0;

    rows.forEach((row, groups) {
      final y = rowYMm[row]!;
      // 좌측 그룹은 x 12 ~ (중앙-gap), 우측 그룹은 (중앙+gap) ~ (width-12)
      final specs = <(List<int>, double, double)>[
        (groups.$1, margin, half - gap),
        (groups.$2, half + gap, widthMm - margin),
      ];
      for (final (group, x0, x1) in specs) {
        final n = group.length;
        for (var i = 0; i < n; i++) {
          final x = n == 1 ? x0 : x0 + (x1 - x0) * i / (n - 1);
          pos[group[i]] = Offset(x, y);
        }
      }
    });

    var result = pos;
    if (orientationFlip) {
      result = [for (final p in result) Offset(p.dx, heightMm - p.dy)];
    }
    if (mirrorLR) {
      result = [for (final p in result) Offset(widthMm - p.dx, p.dy)];
    }

    // 플래그/배치를 나중에 손볼 때 실수를 잡아준다.
    assert(result.length == nChannels,
        '채널 배치 정의가 $nChannels개가 아닙니다: ${result.length}');
    return result;
  }

  // ── 자주 쓰는 그룹 인덱스 (특징 추출용) ────────────────────────────
  static final List<int> frontCh = orientationFlip ? _rowAll(2) : _rowAll(0);
  static final List<int> midCh = _rowAll(1);
  static final List<int> backCh = orientationFlip ? _rowAll(0) : _rowAll(2);
  static final List<int> leftCh = mirrorLR ? _rightGroups() : _leftGroups();
  static final List<int> rightCh = mirrorLR ? _leftGroups() : _rightGroups();

  static List<int> _rowAll(int r) => [...rows[r]!.$1, ...rows[r]!.$2];
  static List<int> _leftGroups() =>
      [for (final e in rows.entries) ...e.value.$1];
  static List<int> _rightGroups() =>
      [for (final e in rows.entries) ...e.value.$2];
}
