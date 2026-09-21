/// 오늘 스트레칭을 몇 번 끝냈는지 세는 메모리 카운터.
///
/// 완료 화면(피그마 11-D)의 '오늘 스트레칭 N회째' 한 줄을 위해서만 쓴다.
/// 앱을 껐다 켜면 0부터 다시 센다. 저장이 필요해지면 `shared_preferences`
/// 로 [_day] 와 [_count] 두 값만 얹으면 된다.
class StretchLog {
  StretchLog._();

  static final StretchLog instance = StretchLog._();

  /// [_count] 를 세고 있는 날짜 (연·월·일만).
  DateTime? _day;
  int _count = 0;

  /// 오늘 완료 횟수. 날짜가 바뀌면 0부터 다시 센다.
  int get todayCount {
    _rollOver();
    return _count;
  }

  /// 루틴 하나를 끝냈다고 기록하고, 오늘 몇 번째인지 돌려준다.
  int record() {
    _rollOver();
    return ++_count;
  }

  /// 날짜가 바뀌었으면 카운터를 되돌린다.
  void _rollOver() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (_day != today) {
      _day = today;
      _count = 0;
    }
  }
}
