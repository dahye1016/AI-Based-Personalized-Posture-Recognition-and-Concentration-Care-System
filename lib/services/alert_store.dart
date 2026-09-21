import 'package:flutter/foundation.dart';

import '../models/posture_alert.dart';

/// 자세 알림 기록 보관소.
///
/// **최근 [maxRecords]건만 남긴다.** 새 알림이 들어오면 가장 오래된 기록이
/// 밀려 나간다. 앱을 껐다 켜면 초기화된다(메모리 보관).
///
/// 나중에 서버나 `shared_preferences` 로 옮길 때도 이 클래스의
/// 인터페이스는 그대로 두고 안쪽만 바꾸면 된다.
class AlertStore extends ChangeNotifier {
  AlertStore._();

  /// 앱 전역에서 하나만 쓴다.
  static final AlertStore instance = AlertStore._();

  /// 보관 한도. 기획 확정값 = 4건.
  static const int maxRecords = 4;

  final List<PostureAlert> _items = [];

  /// 최신 알림이 앞(index 0)에 오는 목록.
  List<PostureAlert> get items => List.unmodifiable(_items);

  int get length => _items.length;

  /// 알림 기록을 추가한다. 한도를 넘으면 가장 오래된 것을 버린다.
  void add(PostureAlert alert) {
    _items.insert(0, alert);
    while (_items.length > maxRecords) {
      _items.removeLast();
    }
    notifyListeners();
  }

  /// 가장 최근 알림을 "스트레칭 완료"로 표시한다.
  void markLatestStretched() {
    if (_items.isEmpty) return;
    _items[0] = _items[0].copyWith(stretched: true);
    notifyListeners();
  }

  void clear() {
    if (_items.isEmpty) return;
    _items.clear();
    notifyListeners();
  }

  // ── 요약 지표 (알림 기록 화면 상단) ──────────────────────────
  // 보관 한도가 4건이므로 이 숫자들도 "최근 4건 기준"이다.

  int get alertCount => _items.length;
  int get stretchedCount => _items.where((a) => a.stretched).length;
  int get ignoredCount => alertCount - stretchedCount;
}
