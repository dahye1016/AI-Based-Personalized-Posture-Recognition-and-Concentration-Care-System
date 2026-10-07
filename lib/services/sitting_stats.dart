import 'package:flutter/foundation.dart';

import '../models/posture_class.dart';

/// 오늘의 착석 통계 — 실제로 앉아 있던 시간과 그중 정자세였던 시간.
///
/// 홈 화면이 프레임을 판정할 때마다 [record] 로 자세를 넘겨주면,
/// 직전 프레임과의 시간 간격을 그 자세에 더한다.
/// 리포트 화면은 [sitting] / [straight] / [straightRatio] 를 읽어 보여준다.
///
/// 앱을 껐다 켜면 초기화된다(메모리 보관). 서버 연동 시 안쪽만 바꾸면 된다.
class SittingStats extends ChangeNotifier {
  SittingStats._();

  /// 앱 전역에서 하나만 쓴다.
  static final SittingStats instance = SittingStats._();

  /// 프레임 사이 간격이 이보다 길면 (연결 끊김 등) 그 구간은 세지 않는다.
  static const Duration maxGap = Duration(seconds: 2);

  Duration _sitting = Duration.zero;
  Duration _straight = Duration.zero;
  DateTime? _last;
  DateTime _day = _today();

  /// 오늘 앉아 있던 총 시간 (자리 비움·신호 대기 제외).
  Duration get sitting => _sitting;

  /// 그중 정자세였던 시간.
  Duration get straight => _straight;

  /// 정자세 비율 (0~1). 앉은 시간이 없으면 0.
  double get straightRatio => _sitting.inMilliseconds == 0
      ? 0
      : _straight.inMilliseconds / _sitting.inMilliseconds;

  /// 판정된 자세 하나를 기록한다.
  void record(PostureClass posture, [DateTime? at]) {
    final now = at ?? DateTime.now();

    // 날짜가 바뀌면 오늘 기록을 새로 시작한다.
    final today = _today(now);
    if (today != _day) {
      _day = today;
      _sitting = Duration.zero;
      _straight = Duration.zero;
      _last = null;
    }

    final last = _last;
    _last = now;
    if (last == null) return;

    final gap = now.difference(last);
    if (gap <= Duration.zero || gap > maxGap) return;
    if (posture == PostureClass.notSitting ||
        posture == PostureClass.waiting) {
      return;
    }

    _sitting += gap;
    if (posture == PostureClass.straight) _straight += gap;
    notifyListeners();
  }

  static DateTime _today([DateTime? t]) {
    final d = t ?? DateTime.now();
    return DateTime(d.year, d.month, d.day);
  }

  /// "3시간 40분" / "12분" / "0분" 형식.
  static String format(Duration d) {
    final m = d.inMinutes;
    if (m >= 60) return '${m ~/ 60}시간 ${m % 60}분';
    return '$m분';
  }
}
