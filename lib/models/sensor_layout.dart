import 'dart:ui' show Offset;

/// PoseLab Seat 방석센서 32채널 물리 배치 (실측 확정판).
///
/// 이전 버전은 layout.py 를 포팅해 방향을 "가정"하고 ORIENTATION_FLIP /
/// MIRROR_LR 플래그로 뒤집는 구조였다. 실측이 끝나 가정·플래그를 제거하고
/// 실측값을 직접 정의한다.
///
/// 좌표계 — 의자에 앉은 사람을 "위에서 내려다본" 그림:
///   · y축: 0=화면 위=엉덩이(0~9), y 클수록 화면 아래=무릎(24~31)
///          (표시상의 선택이며 판정 로직과 무관. 그룹 정의는 실측 그대로.)
///   · x축: 0=화면 왼쪽=사람의 오른쪽 (마주 보는 게 아니라 위에서 보므로)
///
/// 실측 확정 2026-08-09 — 실기기 BLE 수신 상태에서
/// 채널 번호를 화면에 표시하고 각 부위를 직접 눌러 확인함
class SensorLayout {
  SensorLayout._();

  static const int nChannels = 32;

  // 방석 전체 크기 (mm)
  static const double widthMm = 386.0;
  static const double heightMm = 382.0;

  // ── 부위별 채널 그룹 ──────────────────────────────────────────────
  // 실측 확정 2026-08-09 — 실기기 BLE 수신 상태에서
  // 채널 번호를 화면에 표시하고 각 부위를 직접 눌러 확인함
  //
  // 각 행에서 번호 증가 = 몸 바깥(오른쪽) → 안쪽 → 반대편 바깥(왼쪽).
  static const List<int> hipRight = [0, 1, 2, 3, 4]; // 오른쪽 엉덩이 (0=몸 바깥쪽)
  static const List<int> hipLeft = [5, 6, 7, 8, 9]; // 왼쪽 엉덩이
  static const List<int> thighRight = [10, 11, 12, 13, 14, 15, 16]; // 오른쪽 허벅지
  static const List<int> thighLeft = [17, 18, 19, 20, 21, 22, 23]; // 왼쪽 허벅지
  static const List<int> kneeRight = [24, 25, 26, 27]; // 오른쪽 무릎
  static const List<int> kneeLeft = [28, 29, 30, 31]; // 왼쪽 무릎

  // 부위별 (좌우 합침)
  static const List<int> hipCh = [...hipRight, ...hipLeft]; // 0~9
  static const List<int> thighCh = [...thighRight, ...thighLeft]; // 10~23
  static const List<int> kneeCh = [...kneeRight, ...kneeLeft]; // 24~31

  // 좌우별 (부위 합침) — 사람 기준
  static const List<int> rightCh = [...hipRight, ...thighRight, ...kneeRight];
  static const List<int> leftCh = [...hipLeft, ...thighLeft, ...kneeLeft];

  // 노드 1개가 대표하는 면적 (cm²) — 접촉 면적 계산용 근사값
  static const double nodeAreaCm2 =
      (widthMm / 10.0) * (heightMm / 10.0) / nChannels;

  // 행의 세로 위치 (mm). 화면 위(엉덩이) → 아래(무릎).
  static const double _hipY = 40.0; // 화면 위
  static const double _thighY = 191.0; // 중간
  static const double _kneeY = 342.0; // 화면 아래

  /// 채널 번호 -> (x_mm, y_mm) 좌표. index 가 채널 번호.
  /// seat_heatmap 이 이 리스트를 그대로 소비한다.
  static final List<Offset> positions = _buildPositions();

  static List<Offset> _buildPositions() {
    final pos = List<Offset>.filled(nChannels, Offset.zero);
    const half = widthMm / 2.0;
    const gap = 18.0; // 중앙 배선이 지나가는 빈 공간
    const margin = 12.0;

    // 사람의 오른쪽 그룹 → 화면 왼쪽 절반(x 작음), 왼쪽 그룹 → 오른쪽 절반.
    // 그룹 내 index 증가 → x 증가 (몸 바깥→안쪽 방향과 일치).
    void place(List<int> group, double x0, double x1, double y) {
      final n = group.length;
      for (var i = 0; i < n; i++) {
        final x = n == 1 ? x0 : x0 + (x1 - x0) * i / (n - 1);
        pos[group[i]] = Offset(x, y);
      }
    }

    place(hipRight, margin, half - gap, _hipY); // 화면 좌상단
    place(hipLeft, half + gap, widthMm - margin, _hipY); // 화면 우상단
    place(thighRight, margin, half - gap, _thighY);
    place(thighLeft, half + gap, widthMm - margin, _thighY);
    place(kneeRight, margin, half - gap, _kneeY); // 화면 좌하단
    place(kneeLeft, half + gap, widthMm - margin, _kneeY); // 화면 우하단

    // 검증: 0~31 이 중복·누락 없이 정확히 한 번씩, 좌표 개수 32.
    assert(_isComplete(), '채널 그룹에 중복/누락이 있습니다');
    assert(pos.length == nChannels, '좌표 개수가 $nChannels 이 아닙니다');
    return pos;
  }

  /// 부위별·좌우별 두 분할 모두 0~31 을 정확히 한 번씩 덮는지 검증.
  static bool _isComplete() {
    final expected = List<int>.generate(nChannels, (i) => i).toSet();
    bool covers(List<int> all) =>
        all.length == nChannels &&
        all.toSet().length == nChannels &&
        all.toSet().containsAll(expected);
    return covers([...hipCh, ...thighCh, ...kneeCh]) &&
        covers([...rightCh, ...leftCh]);
  }
}
