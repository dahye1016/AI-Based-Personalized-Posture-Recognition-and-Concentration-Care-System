import 'posture_layout.dart';

/// 판정 상태 (좋음 / 경고)
enum PostureStatus { good, warning }

/// 판정 결과 한 건
class PostureResult {
  final String posture; // 바른자세 / 거북목 / 기대기 / 다리꼬기 / 앉지않음
  final PostureStatus status;
  final String message;
  const PostureResult(this.posture, this.status, this.message);
}

/// 규칙 기반 자세 판정기.
/// 팀 서버의 `classify_posture`(6채널) 로직을 방석센서용으로 이식했다.
/// 32채널 raw 압력값을 앞/뒤/좌/우 구역 평균으로 묶어
/// 조건 판정한다. 구역 정의는 [PostureLayout] 이 단일 소스다.
///
/// 구역이 가리키는 부위 (실측 검증된 10/14/8 배치):
///   · front = 무릎(ch24~31)   — 앞으로 숙이면 커진다
///   · back  = 엉덩이(ch0~9)   — 등받이에 기대면 커진다
///   · 가운데 허벅지 행(ch10~23)은 앞뒤 판정에 쓰지 않는다.
///     어느 자세에서도 하중이 실려 앞뒤를 가르지 못하기 때문이다.
///     좌우 비교에는 들어간다.
///
/// ⚠️ 임계값(threshold)은 6채널 기준을 옮겨온 초기값이라,
///    실제 센서 raw 값 범위(예: 0~4095)에 맞춰 실물 연결 때
///    보정이 필요하다. (아래 상수만 조정하면 됨)
///    front(8칸)와 back(10칸)은 구역 크기가 다르므로 _frontStrong 과
///    _backStrong 을 같은 값으로 두는 근거가 없다.
class PostureClassifier {
  static const double _sitThreshold = 80; // 이 미만이면 '앉지않음'
  static const double _lrDiff = 200; // 좌우 차 → 다리꼬기
  static const double _frontStrong = 500; // 앞이 셀 때 기준
  static const double _backStrong = 500; // 뒤가 셀 때 기준
  static const double _gap = 250; // 앞뒤 차 기준

  static double _avg(List<int> v, List<int> idx) {
    if (idx.isEmpty) return 0;
    double s = 0;
    for (final i in idx) {
      if (i < v.length) s += v[i];
    }
    return s / idx.length;
  }

  static PostureResult classify(List<int> ch) {
    if (ch.length < PostureLayout.channels) {
      return const PostureResult(
          '데이터 없음', PostureStatus.good, '센서 데이터를 기다리는 중...');
    }

    final front = _avg(ch, PostureLayout.front);
    final back = _avg(ch, PostureLayout.back);
    final left = _avg(ch, PostureLayout.left);
    final right = _avg(ch, PostureLayout.right);
    final total = _avg(ch, PostureLayout.all);

    if (total < _sitThreshold) {
      return const PostureResult(
          '앉지 않음', PostureStatus.good, '의자에 앉으면 자세를 측정할게요.');
    }
    if ((left - right).abs() > _lrDiff) {
      return const PostureResult(
          '다리꼬기', PostureStatus.warning, '다리를 꼬고 있어요! 골반이 틀어질 수 있어요.');
    }
    if (front > _frontStrong && front - back > _gap) {
      return const PostureResult(
          '거북목', PostureStatus.warning, '목이 앞으로 나와있어요. 어깨를 펴고 턱을 당기세요.');
    }
    if (back > _backStrong && back - front > _gap) {
      return const PostureResult(
          '기대기', PostureStatus.warning, '등받이에 너무 기대고 있어요. 앞으로 조금 당겨주세요.');
    }
    return const PostureResult(
        '바른자세', PostureStatus.good, '좋아요! 바른 자세를 유지하고 있어요.');
  }
}
