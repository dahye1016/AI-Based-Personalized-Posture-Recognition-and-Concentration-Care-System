import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/posture_classifier.dart';
import '../services/posture_layout.dart';
import '../services/sensor_source.dart';
import '../theme/app_theme.dart';
import '../widgets/bm.dart';
import 'settings_screen.dart';
import 'stretch_screen.dart';

/// 홈 — 실시간 자세. 피그마 「06 실시간 모니터링」.
///
/// SensorSource(입구) → PostureClassifier(판정) → 화면.
/// 데이터 배선은 그대로 두고 화면만 배민 스타일로 교체했다.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.source});

  /// 데이터 입구. 안 넘기면 가짜 소스로 자동 동작.
  final SensorSource? source;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final SensorSource _source;

  /// 위젯이 소스를 직접 만들었을 때만 dispose 한다.
  /// (주입받은 소스의 수명은 넘겨준 쪽이 관리한다.)
  bool _ownsSource = false;

  StreamSubscription<List<int>>? _sub;

  PostureResult _result =
      const PostureResult('연결 중', PostureStatus.good, '센서 데이터를 기다리는 중...');
  String? _lastWarned;

  /// 가장 최근 프레임의 채널 값 (히트맵용). 없으면 빈 리스트.
  List<int> _frame = const [];

  /// 나쁜 자세가 이어지기 시작한 시각.
  DateTime? _badSince;

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

      if (r.status == PostureStatus.warning) {
        _badSince ??= DateTime.now();
      } else {
        _badSince = null;
      }
    });

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

  Color _postureColor(String posture) => switch (posture) {
        '거북목' => AppColors.postureLean,
        '다리꼬기' => AppColors.postureCross,
        '기대기' => AppColors.postureTilt,
        '바른자세' => AppColors.postureGood,
        _ => AppColors.textTertiary,
      };

  /// 좌석을 4×4 로 요약한 압력값(0~1). 프레임이 없으면 전부 0.
  List<List<double>> get _heatGrid {
    const rows = 4, cols = 4;
    final grid = List.generate(rows, (_) => List<double>.filled(cols, 0));
    if (_frame.length < PostureLayout.channels) return grid;

    final maxV = _frame.reduce((a, b) => a > b ? a : b);
    if (maxV <= 0) return grid;

    // 32채널을 순서대로 16칸에 2개씩 나눠 담는다(표시용 근사).
    for (var i = 0; i < PostureLayout.channels; i++) {
      final cell = (i * rows * cols) ~/ PostureLayout.channels;
      final r = cell ~/ cols, c = cell % cols;
      grid[r][c] += _frame[i] / maxV / 2;
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
                          builder: (_) => const SettingsScreen()),
                    ),
                    icon: const Icon(Icons.tune_rounded,
                        size: 22, color: AppColors.textTertiary),
                    tooltip: '알림 설정',
                  ),
                ],
              ),
            ),

            // ── 경고 배너 ─────────────────────────
            if (_isBad)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screen, 0, AppSpacing.screen, 14),
                child: _WarnBanner(
                  title: '${_result.posture} 자세가 감지됐어요!',
                  body: '$_heldLabel${_result.message}',
                ),
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
                              Text(_result.posture,
                                  style:
                                      AppText.display.copyWith(fontSize: 26)),
                              const SizedBox(height: 4),
                              Text(_result.message,
                                  style: AppText.caption.copyWith(height: 1.4)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: HapticFeedback.mediumImpact,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text('진동으로 알려주기',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            )),
                      ),
                    ),
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
                      trailing:
                          _frame.isEmpty ? '신호 대기 중' : '${_frame.length} ch',
                    ),
                    const SizedBox(height: 12),
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
                    const BmCardCaption(
                      title: '최근 자세',
                      trailing: '바른 · 거북목 · 다리꼬기',
                    ),
                    const SizedBox(height: 10),
                    BmBand(segments: _timelineSegments()),
                  ],
                ),
              ),
            ),

            const Spacer(),

            // ── 스트레칭 유도 ─────────────────────
            if (_isBad)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screen, 14, AppSpacing.screen, 0),
                child: BmPrimaryButton(
                  label: '스트레칭 하러 가기',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const StretchScreen()),
                  ),
                ),
              ),
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

/// 4×4 압력 히트맵.
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
            if (r > 0) const SizedBox(height: 10),
            Row(
              children: [
                for (var c = 0; c < grid[r].length; c++) ...[
                  if (c > 0) const SizedBox(width: 10),
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 26,
                      decoration: BoxDecoration(
                        color: AppColors.heat(grid[r][c].clamp(0.0, 1.0)),
                        borderRadius: BorderRadius.circular(8),
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
