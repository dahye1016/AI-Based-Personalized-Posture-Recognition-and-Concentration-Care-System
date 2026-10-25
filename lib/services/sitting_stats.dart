import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/posture_class.dart';

/// 하루치 착석 기록. 리포트(일간·주간)가 이 값만 읽는다.
class DayStats {
  DayStats(this.day)
      : byPosture = {},
        hourSitting = List<int>.filled(24, 0),
        hourStraight = List<int>.filled(24, 0);

  /// 날짜 (연·월·일만).
  final DateTime day;

  /// 자세별 앉아 있던 시간 (ms). 키는 [PostureClass.name]. 자리 비움·대기 제외.
  final Map<String, int> byPosture;

  /// 시간대(0~23시)별 앉아 있던 시간 / 그중 정자세 시간 (ms).
  final List<int> hourSitting;
  final List<int> hourStraight;

  /// 나쁜 자세 알림 횟수.
  int alerts = 0;

  /// 스트레칭 완료 횟수.
  int stretches = 0;

  /// 정자세를 끊김 없이 가장 오래 유지한 시간 (ms).
  int longestStraightMs = 0;

  Duration get sitting =>
      Duration(milliseconds: byPosture.values.fold(0, (a, b) => a + b));

  Duration get straight =>
      Duration(milliseconds: byPosture[PostureClass.straight.name] ?? 0);

  double get straightRatio => sitting.inMilliseconds == 0
      ? 0
      : straight.inMilliseconds / sitting.inMilliseconds;

  bool get hasData => sitting.inMilliseconds > 0;

  /// 앉아 있던 자세를 시간 많은 순으로.
  List<MapEntry<PostureClass, Duration>> get postures {
    final out = <MapEntry<PostureClass, Duration>>[];
    for (final e in byPosture.entries) {
      if (e.value <= 0) continue;
      final p = PostureClass.values.where((c) => c.name == e.key);
      if (p.isEmpty) continue;
      out.add(MapEntry(p.first, Duration(milliseconds: e.value)));
    }
    out.sort((a, b) => b.value.compareTo(a.value));
    return out;
  }

  Map<String, dynamic> toJson() => {
        'day': day.toIso8601String(),
        'byPosture': byPosture,
        'hourSitting': hourSitting,
        'hourStraight': hourStraight,
        'alerts': alerts,
        'stretches': stretches,
        'longestStraightMs': longestStraightMs,
      };

  static DayStats fromJson(Map<String, dynamic> j) {
    final d = DayStats(DateTime.parse(j['day'] as String));
    (j['byPosture'] as Map).forEach((k, v) => d.byPosture['$k'] = v as int);
    final hs = (j['hourSitting'] as List).cast<int>();
    final ht = (j['hourStraight'] as List).cast<int>();
    for (var i = 0; i < 24 && i < hs.length; i++) {
      d.hourSitting[i] = hs[i];
    }
    for (var i = 0; i < 24 && i < ht.length; i++) {
      d.hourStraight[i] = ht[i];
    }
    d.alerts = (j['alerts'] as int?) ?? 0;
    d.stretches = (j['stretches'] as int?) ?? 0;
    d.longestStraightMs = (j['longestStraightMs'] as int?) ?? 0;
    return d;
  }
}

/// 착석 통계 — 방석에 실제로 앉아 있던 시간을 자세별·시간대별로 쌓는다.
///
/// 홈 화면이 프레임을 판정할 때마다 [record] 로 자세를 넘겨주면,
/// 직전 프레임과의 시간 간격을 그 자세에 더한다. 프레임 간격이 [maxGap] 보다
/// 길면(연결 끊김 등) 그 구간은 세지 않는다. 자리 비움·신호 대기도 세지 않는다.
///
/// 기기에 저장(shared_preferences)해서 앱을 껐다 켜도 남는다. 최근 [keepDays]일만 보관.
///
/// **사용자별로 따로 쌓는다.** 로그인하면 [switchUser] 로 그 사람의 기록으로 바뀌고,
/// 로그인하지 않으면(건너뛰기) [guestKey] 기록을 쓴다.
class SittingStats extends ChangeNotifier {
  SittingStats._();

  /// 앱 전역에서 하나만 쓴다.
  static final SittingStats instance = SittingStats._();

  static const Duration maxGap = Duration(seconds: 2);
  static const int keepDays = 14;
  static const String _prefsKey = 'sitting_stats_v1';

  /// 로그인하지 않은 사용자의 기록 키.
  static const String guestKey = 'guest';

  /// 지금 기록을 쌓고 있는 사용자.
  String _userKey = guestKey;
  String get userKey => _userKey;

  String get _storageKey => '$_prefsKey:$_userKey';

  /// 날짜(연·월·일) → 그날 기록.
  final Map<DateTime, DayStats> _days = {};

  DateTime? _last;
  int _straightRunMs = 0;
  Timer? _saveTimer;

  // ── 읽기 ───────────────────────────────────────────────────────
  /// 오늘 기록 (없으면 빈 기록).
  DayStats get today => _dayOf(DateTime.now());

  /// 오늘 앉아 있던 총 시간.
  Duration get sitting => today.sitting;

  /// 오늘 그중 정자세였던 시간.
  Duration get straight => today.straight;

  /// 오늘 정자세 비율 (0~1).
  double get straightRatio => today.straightRatio;

  /// 오늘 포함 최근 7일 (오래된 날 → 오늘). 기록 없는 날도 빈 기록으로 들어간다.
  List<DayStats> get lastWeek {
    final t = _dateOnly(DateTime.now());
    return [
      for (var i = 6; i >= 0; i--)
        _days[t.subtract(Duration(days: i))] ??
            DayStats(t.subtract(Duration(days: i))),
    ];
  }

  // ── 쓰기 ───────────────────────────────────────────────────────
  /// 판정된 자세 하나를 기록한다.
  void record(PostureClass posture, [DateTime? at]) {
    final now = at ?? DateTime.now();
    final last = _last;
    _last = now;
    if (last == null) return;

    final gap = now.difference(last);
    if (gap <= Duration.zero || gap > maxGap) {
      _straightRunMs = 0;
      return;
    }
    if (posture == PostureClass.notSitting ||
        posture == PostureClass.waiting) {
      _straightRunMs = 0;
      return;
    }

    final ms = gap.inMilliseconds;
    final d = _dayOf(now, create: true);
    d.byPosture[posture.name] = (d.byPosture[posture.name] ?? 0) + ms;
    d.hourSitting[now.hour] += ms;
    if (posture == PostureClass.straight) {
      d.hourStraight[now.hour] += ms;
      _straightRunMs += ms;
      if (_straightRunMs > d.longestStraightMs) {
        d.longestStraightMs = _straightRunMs;
      }
    } else {
      _straightRunMs = 0;
    }
    notifyListeners();
    _scheduleSave();
  }

  /// 나쁜 자세 알림이 한 번 떴다.
  void recordAlert() {
    _dayOf(DateTime.now(), create: true).alerts++;
    notifyListeners();
    _scheduleSave();
  }

  /// 스트레칭 루틴을 하나 끝냈다.
  void recordStretch() {
    _dayOf(DateTime.now(), create: true).stretches++;
    notifyListeners();
    _scheduleSave();
  }

  // ── 사용자 전환 ─────────────────────────────────────────────────
  /// 다른 사용자로 바꾼다. 지금 사용자의 기록을 먼저 저장하고, 새 사용자의 기록을 불러온다.
  Future<void> switchUser(String userKey) async {
    final key = userKey.trim().isEmpty ? guestKey : userKey.trim();
    if (key == _userKey) return;
    _saveTimer?.cancel();
    await _save();
    _userKey = key;
    _days.clear();
    _last = null;
    _straightRunMs = 0;
    notifyListeners();
    await load();
  }

  // ── 저장 ───────────────────────────────────────────────────────
  /// 지금 사용자의 기록을 불러온다. 실패해도 빈 기록으로 계속 간다.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null) return;
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      for (final j in list) {
        final d = DayStats.fromJson(j);
        _days[_dateOnly(d.day)] = d;
      }
      _prune();
      notifyListeners();
    } catch (e) {
      debugPrint('[SittingStats] 불러오기 실패: $e');
    }
  }

  /// 기록이 계속 들어오므로 5초에 한 번만 저장한다.
  void _scheduleSave() {
    if (_saveTimer?.isActive ?? false) return;
    _saveTimer = Timer(const Duration(seconds: 5), _save);
  }

  Future<void> _save() async {
    try {
      _prune();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _storageKey, jsonEncode([for (final d in _days.values) d.toJson()]));
    } catch (e) {
      debugPrint('[SittingStats] 저장 실패: $e');
    }
  }

  void _prune() {
    final cutoff =
        _dateOnly(DateTime.now()).subtract(const Duration(days: keepDays));
    _days.removeWhere((k, _) => k.isBefore(cutoff));
  }

  DayStats _dayOf(DateTime t, {bool create = false}) {
    final k = _dateOnly(t);
    final d = _days[k];
    if (d != null) return d;
    final fresh = DayStats(k);
    if (create) _days[k] = fresh;
    return fresh;
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// "3시간 40분" / "12분" / "0분" 형식.
  static String format(Duration d) {
    final m = d.inMinutes;
    if (m >= 60) return '${m ~/ 60}시간 ${m % 60}분';
    return '$m분';
  }
}
