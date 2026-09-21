import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/posture_alert.dart';
import '../models/posture_class.dart';
import '../services/alert_store.dart';
import '../services/posture_classifier.dart';
import '../services/posture_layout.dart';
import '../services/sensor_source.dart';
import '../theme/app_theme.dart';
import '../widgets/bm.dart';
import 'alert_history_screen.dart';
import 'posture_alert_screen.dart';
import 'settings_screen.dart';
import 'stretch_screen.dart';

/// 홈 — 실시간 자세. 피그마 「06 실시간 모니터링」.
///
/// SensorSource(입구) → PostureClassifier(판정) → 화면.
/// 데이터 배선은 그대로 두고 화면만 배민 스타일로 교체했다.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.source, this.onOpenReport});

  /// 데이터 입구. 안 넘기면 가짜 소스로 자동 동작.
  final SensorSource? source;

  /// 하단 탭을 리포트로 넘기는 콜백. RootNav 가 넘겨준다.
  /// 없으면 정자세 카드의 '오늘 리포트 보기' 버튼을 숨긴다.
  final VoidCallback? onOpenReport;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final SensorSource _source;

  /// 위젯이 소스를 직접 만들었을 때만 dispose 한다.
  /// (주입받은 소스의 수명은 넘겨준 쪽이 관리한다.)
  bool _ownsSource = false;

  StreamSubscription<List<int>>? _sub;

  PostureResult _result = const PostureResult(PostureClass.waiting);
  PostureClass? _lastWarned;

  /// 가장 최근 프레임의 채널 값 (히트맵용). 없으면 빈 리스트.
  List<int> _frame = const [];

  /// 나쁜 자세가 이어지기 시작한 시각.
  DateTime? _badSince;

  /// 지금 이어지고 있는 나쁜 자세의 종류. 자세가 바뀌면 시간을 다시 잰다.
  PostureClass? _badPosture;

  /// 지금 상태가 시작된 시각. 정자세·자리 비움의 지속 시간 표시에 쓴다.
  /// 알림 발화 기준인 [_badSince] 와 달리 모든 상태를 대상으로 잰다.
  DateTime? _stateSince;

  /// [_stateSince] 를 재고 있는 자세. 바뀌면 시간을 다시 잰다.
  PostureClass? _stateOf;

  /// 이 에피소드에 대해 이미 알림을 띄웠는지 (자세 이름으로 구분).
  PostureClass? _alertedFor;

  /// 알림 화면이 떠 있는 동안 중복으로 띄우지 않기 위한 잠금.
  bool _alertOpen = false;

  /// 오늘 몇 번째 알림인지. 보관 한도(4건)와 무관하게 계속 센다.
  int _todayAlerts = 0;

  /// 최근 자세 이력 (타임라인 띠). 최대 24칸.
  final List<PostureResult> _history = [];

  @override
  void initState() {
    super.initState();
    _ownsSource = widget.source == null;
    _source = widget.source ?? MockSensorSource();
    _sub = _source.frames().listen(_onFrame);
  }

  void _onFrame(List<int> frame) {
    final r = PostureClassifier.classify(frame);
    if (!mounted) return;

    setState(() {
      _result = r;
      _frame = frame;
      _history.add(r);
      if (_history.length > 24) _history.removeAt(0);

      // 정자세·자리 비움 배너의 지속 시간용 (경고와 무관하게 항상 잰다).
      if (_stateOf != r.posture) {
        _stateOf = r.posture;
        _stateSince = DateTime.now();
      }

      if (r.status == PostureStatus.warning) {
        // 자세가 바뀌면 지속 시간을 처음부터 다시 잰다.
        if (_badPosture != r.posture) {
          _badPosture = r.posture;
          _badSince = DateTime.now();
        }
      } else {
        _badPosture = null;
        _badSince = null;
      }
    });

    _maybeAlert(r);

    // 나쁜 자세가 새로 감지된 순간에만 진동 (REQ-F-05)
    if (r.status == PostureStatus.warning) {
      if (_lastWarned != r.posture) {
        _lastWarned = r.posture;
        HapticFeedback.mediumImpact();
      }
    } else {
      _lastWarned = null;
    }
  }

  /// 같은 나쁜 자세가 기준 시간([PostureAlertScreen.threshold]) 넘게
  /// 이어지면 알림 화면을 띄우고
  /// 기록으로 남긴다. 기록은 최근 4건만 보관된다(AlertStore).
  void _maybeAlert(PostureResult r) {
    if (r.status != PostureStatus.warning) {
      _alertedFor = null;
      return;
    }
    final since = _badSince;
    if (since == null) return;
    if (_alertedFor == r.posture) return; // 이 에피소드는 이미 알렸다

    final held = DateTime.now().difference(since);
    if (held < PostureAlertScreen.threshold) return;

    _alertedFor = r.posture;
    _todayAlerts++;

    final alert = PostureAlert(
      posture: r.posture,
      heldFor: held,
      at: DateTime.now(),
    );
    AlertStore.instance.add(alert);

    if (!mounted || _alertOpen) return;
    _alertOpen = true;
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => PostureAlertScreen(
            alert: alert,
            todayCount: _todayAlerts,
          ),
        ))
        .then((_) {
      if (mounted) _alertOpen = false;
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    if (_ownsSource) _source.dispose();
    super.dispose();
  }

  // ── 표시용 계산 ────────────────────────────────────────────

  bool get _isBad => _result.status == PostureStatus.warning;

  String get _heldLabel {
    final since = _badSince;
    if (since == null) return '';
    final d = DateTime.now().difference(since);
    if (d.inMinutes >= 1) return '${d.inMinutes}분 ${d.inSeconds % 60}초째 · ';
    return '${d.inSeconds}초째 · ';
  }

  Color _postureColor(PostureClass posture) => posture.color;

  /// 지금 상태가 이어진 시간을 'N분' / 'N초' 로. 1분 미만이면 초로 보여준다.
  String get _stateHeld {
    final since = _stateSince;
    if (since == null) return '0초';
    final d = DateTime.now().difference(since);
    if (d.inMinutes >= 1) return '${d.inMinutes}분';
    return '${d.inSeconds}초';
  }

  /// 상태별 상단 배너. 연결 중(waiting)에는 배너를 띄우지 않는다.
  Widget? get _banner {
    if (_isBad) {
      return _WarnBanner(
        title: '${_result.posture.label} 자세가 감지됐어요!',
        body: '$_heldLabel${_result.message}',
      );
    }
    switch (_result.posture) {
      case PostureClass.straight:
        return _GoodBanner(
          title: '자세가 아주 좋아요!',
          body: '$_stateHeld째 바른 자세를 유지하고 있어요',
        );
      case PostureClass.notSitting:
        // 자리 비움은 경고 배너 모양만 빌려 쓴다. 알림·진동은 띄우지 않는다
        // (notSitting 은 isBad 가 아니라 status 가 warning 이 되지 않는다).
        return const _WarnBanner(
          title: '자리를 비웠어요',
          body: '돌아와서 앉으면 다시 측정을 시작해요',
        );
      default:
        return null;
    }
  }

  /// 자세 카드 부제.
  String get _cardMessage => _result.posture == PostureClass.notSitting
      ? '$_stateHeld째 착석이 감지되지 않아요'
      : _result.message;

  /// 자세 카드 안의 행동 버튼. 연결 중에는 버튼을 두지 않는다.
  Widget? get _cardButton {
    if (_isBad || _result.posture == PostureClass.notSitting) {
      return _CardButton(
        label: '스트레칭 하러 가기',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const StretchScreen()),
        ),
      );
    }
    if (_result.posture == PostureClass.straight) {
      final open = widget.onOpenReport;
      if (open == null) return null;
      return _CardButton(label: '오늘 리포트 보기', onTap: open);
    }
    return null;
  }

  /// 현재 프레임에서 주어진 채널들의 합.
  double _sum(List<int> idx) {
    var s = 0.0;
    for (final i in idx) {
      if (i < _frame.length) s += _frame[i];
    }
    return s;
  }

  /// 압력 분포 카드의 오른쪽 상태 요약. 구역 구분은 [PostureLayout] 을 쓴다.
  String get _pressureSummary {
    if (_result.posture == PostureClass.waiting ||
        _frame.length < PostureLayout.channels) {
      return '신호 대기 중';
    }
    if (_result.posture == PostureClass.notSitting) {
      return '압력이 감지되지 않아요';
    }

    final total = _sum(PostureLayout.all);
    if (total <= 0) return '압력이 감지되지 않아요';

    final l = _sum(PostureLayout.left);
    final r = _sum(PostureLayout.right);
    final lr = l + r;

    switch (_result.posture) {
      case PostureClass.straight:
        if (lr <= 0) return '압력이 감지되지 않아요';
        final balance = 100 - ((l - r).abs() / lr * 100);
        return '좌우 균형 ${balance.round()}%';
      case PostureClass.leanForward:
        return '무릎 쪽 하중 ${(_sum(PostureLayout.knee) / total * 100).round()}%';
      case PostureClass.leanBack:
        return '엉덩이 쪽 하중 ${(_sum(PostureLayout.hip) / total * 100).round()}%';
      default:
        // 다리 꼬기(잠정값)와 좌우 기울임 — 좌우 비중으로 보여준다.
        if (lr <= 0) return '압력이 감지되지 않아요';
        return '좌 ${(l / lr * 100).round()}% · 우 ${(r / lr * 100).round()}%';
    }
  }

  /// 방석 32채널을 물리 배치 그대로 0~1 로 정규화한 값.
  /// 프레임이 없으면 전부 0.
  ///
  /// 이전에는 32채널을 4×4=16칸으로 2개씩 뭉쳐 그렸는데, 그리드 경계가
  /// 실제 행 경계와 어긋나 한 행에 서로 다른 부위가 섞이고 좌우 경계도
  /// 밀려 있었다. 이제 [PostureLayout.rows] 를 그대로 그리므로 화면의
  /// 위아래·좌우가 몸의 위아래·좌우와 일치한다.
  /// 행 구성은 실측으로 검증된 10 / 14 / 8 이다.
  List<List<double>> get _heatGrid {
    final grid = [
      for (final row in PostureLayout.rows) List<double>.filled(row.length, 0),
    ];
    if (_frame.length < PostureLayout.channels) return grid;

    var maxV = 0;
    for (final i in PostureLayout.all) {
      if (_frame[i] > maxV) maxV = _frame[i];
    }
    if (maxV <= 0) return grid;

    for (var r = 0; r < PostureLayout.rows.length; r++) {
      final row = PostureLayout.rows[r];
      for (var c = 0; c < row.length; c++) {
        grid[r][c] = _frame[row[c]] / maxV;
      }
    }
    return grid;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: BmScreen(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BmHeader(
              eyebrow: '자세케어',
              title: '실시간 자세',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BmPill(label: 'LIVE', dot: true),
                  IconButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const AlertHistoryScreen()),
                    ),
                    icon: const Icon(Icons.notifications_none_rounded,
                        size: 22, color: AppColors.textTertiary),
                    tooltip: '알림 기록',
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const SettingsScreen()),
                    ),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text('설정',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          )),
                    ),
                  ),
                ],
              ),
            ),

            // ── 상태 배너 ─────────────────────────
            if (_banner != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screen, 0, AppSpacing.screen, 14),
                child: _banner,
              ),

            // ── 현재 자세 카드 ────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen, 0, AppSpacing.screen, 14),
              child: BmCard(
                child: Column(
                  children: [
                    Row(
                      children: [
                        _PostureIcon(
                          color: _postureColor(_result.posture),
                          bad: _isBad,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_result.posture.label,
                                  style:
                                      AppText.display.copyWith(fontSize: 26)),
                              const SizedBox(height: 4),
                              Text(_cardMessage,
                                  style: AppText.caption.copyWith(height: 1.4)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_cardButton != null) ...[
                      const SizedBox(height: 14),
                      _cardButton!,
                    ],
                  ],
                ),
              ),
            ),

            // ── 압력 분포 ────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen, 0, AppSpacing.screen, 14),
              child: BmSoftCard(
                child: Column(
                  children: [
                    BmCardCaption(
                      title: '압력 분포',
                      trailing: _pressureSummary,
                    ),
                    const SizedBox(height: 12),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('좌석 · 위 엉덩이 → 아래 무릎',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textTertiary,
                          )),
                    ),
                    const SizedBox(height: 8),
                    _HeatGrid(grid: _heatGrid),
                  ],
                ),
              ),
            ),

            // ── 오늘 요약 ────────────────────────
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.screen),
              child: Row(
                children: [
                  Expanded(child: BmStatTile(label: '바른 자세', value: '62%')),
                  SizedBox(width: 10),
                  Expanded(
                      child: BmStatTile(label: '오늘 착석', value: '3시간 40분')),
                ],
              ),
            ),

            // ── 최근 자세 타임라인 ─────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen, 14, AppSpacing.screen, 0),
              child: BmSoftCard(
                child: Column(
                  children: [
                    BmCardCaption(
                      title: '최근 30분',
                      trailing: '${PostureClass.straight.label} · '
                          '${PostureClass.leanForward.label} · '
                          '${PostureClass.crossLegUnknown.label}',
                    ),
                    const SizedBox(height: 10),
                    BmBand(segments: _timelineSegments()),
                  ],
                ),
              ),
            ),

            const Spacer(),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  List<MapEntry<int, Color>> _timelineSegments() {
    if (_history.isEmpty) {
      return const [MapEntry(1, AppColors.border)];
    }
    // 같은 자세가 이어지면 한 칸으로 합친다.
    final out = <MapEntry<int, Color>>[];
    var runColor = _postureColor(_history.first.posture);
    var runLen = 0;
    for (final r in _history) {
      final c = _postureColor(r.posture);
      if (c == runColor) {
        runLen++;
      } else {
        out.add(MapEntry(runLen, runColor));
        runColor = c;
        runLen = 1;
      }
    }
    out.add(MapEntry(runLen, runColor));
    return out;
  }
}

/// 주황 경고 배너.
class _WarnBanner extends StatelessWidget {
  const _WarnBanner({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warnBg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.warnIcon,
              shape: BoxShape.circle,
            ),
            child: const Text('!',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                )),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    )),
                const SizedBox(height: 3),
                Text(body,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: AppColors.textSecondary,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 민트 정자세 배너.
class _GoodBanner extends StatelessWidget {
  const _GoodBanner({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.postureGood,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded,
                size: 20, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    )),
                const SizedBox(height: 3),
                Text(body,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: AppColors.textSecondary,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 자세 카드 안의 행동 버튼. 모양은 기존 버튼 그대로(민트 옅은 배경).
class _CardButton extends StatelessWidget {
  const _CardButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.primarySoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            )),
      ),
    );
  }
}

/// 자세 픽토그램 — 나쁜 자세면 고개가 앞으로 나온 모양.
class _PostureIcon extends StatelessWidget {
  const _PostureIcon({required this.color, required this.bad});

  final Color color;
  final bool bad;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        // ignore: deprecated_member_use
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            left: bad ? 27 : 21,
            top: 11,
            child: Container(
              width: 15,
              height: 15,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
          Positioned(
            left: 13,
            top: 30,
            child: Container(
              width: 13,
              height: 17,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 압력 히트맵. 행 구성은 [PostureLayout.rows] 를 그대로 따른다.
/// 행마다 셀 개수가 달라도(10/14/8) 각 행이 카드 폭을 꽉 채운다.
class _HeatGrid extends StatelessWidget {
  const _HeatGrid({required this.grid});

  final List<List<double>> grid;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (var r = 0; r < grid.length; r++) ...[
            if (r > 0) const SizedBox(height: 8),
            Row(
              children: [
                for (var c = 0; c < grid[r].length; c++) ...[
                  if (c > 0) const SizedBox(width: 3),
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 26,
                      decoration: BoxDecoration(
                        color: AppColors.heat(grid[r][c].clamp(0.0, 1.0)),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
