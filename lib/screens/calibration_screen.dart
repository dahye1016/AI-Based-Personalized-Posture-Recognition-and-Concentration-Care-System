import 'dart:async';

import 'package:flutter/material.dart';

import '../services/posture_layout.dart';
import '../services/sensor_source.dart';
import '../theme/app_theme.dart';
import '../widgets/bm.dart';

/// 정자세 측정(캘리브레이션) — 피그마 「01 측정 안내 / 02 측정 중 / 03 측정 완료」.
///
/// 한 화면 안에서 3단계로 진행한다.
/// 측정 중에는 [SensorSource] 프레임을 모아 채널별 최대·평균을 계산하고,
/// 총압력이 크게 출렁이면 '흔들림'으로 센다.
///
/// 결과는 아직 서버로 보내지 않는다. 이 브랜치에는 캘리브레이션 API
/// 클라이언트가 없어서, 지금은 [onDone] 으로 호출한 쪽에 넘겨준다.
class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({
    super.key,
    required this.source,
    this.duration = const Duration(seconds: 10),
    this.onDone,
  });

  final SensorSource source;

  /// 측정 시간. 기획상 5~10초.
  final Duration duration;

  final ValueChanged<CalibrationResult>? onDone;

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

enum _Step { intro, measuring, done }

class _CalibrationScreenState extends State<CalibrationScreen> {
  _Step _step = _Step.intro;

  StreamSubscription<List<int>>? _sub;
  Timer? _ticker;
  Stopwatch? _watch;

  late List<int> _max;
  late List<double> _sum;
  int _frames = 0;
  int _unstable = 0;
  double? _baseTotal;
  final List<double> _warmup = [];

  List<double> _levels = const [];
  bool _stable = true;
  CalibrationResult? _result;

  static const _minFrames = 10;
  static const _tolerance = 0.15;
  static const _maxUnstableRatio = 0.3;

  Duration get _remaining {
    final w = _watch;
    if (w == null) return widget.duration;
    final left = widget.duration - w.elapsed;
    return left.isNegative ? Duration.zero : left;
  }

  double get _ratio {
    final total = widget.duration.inMilliseconds;
    if (total <= 0) return 1;
    return ((total - _remaining.inMilliseconds) / total).clamp(0.0, 1.0);
  }

  void _start() {
    _max = List<int>.filled(PostureLayout.channels, 0);
    _sum = List<double>.filled(PostureLayout.channels, 0);
    _levels = List<double>.filled(PostureLayout.channels, 0);
    _frames = 0;
    _unstable = 0;
    _baseTotal = null;
    _warmup.clear();
    _stable = true;
    _result = null;

    setState(() => _step = _Step.measuring);

    _watch = Stopwatch()..start();
    _sub = widget.source.frames().listen(_onFrame);
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      if (_watch!.elapsed >= widget.duration) {
        _finish();
      } else {
        setState(() {});
      }
    });
  }

  void _onFrame(List<int> ch) {
    if (_step != _Step.measuring) return;

    var total = 0.0;
    final levels = List<double>.filled(PostureLayout.channels, 0);

    // ch31 은 센서값이 아니라 더미다. 총압·최대값·개인 기준값 어디에도
    // 넣지 않는다. (넣으면 더미값이 정규화를 지배해 실채널이 전부
    // 차갑게 보이고, 흔들림 판정의 기준 총압도 함께 어긋난다.)
    var maxV = 1;
    for (final i in PostureLayout.all) {
      if (i < ch.length && ch[i] > maxV) maxV = ch[i];
    }
    for (final i in PostureLayout.all) {
      if (i >= ch.length) continue;
      final v = ch[i];
      if (v > _max[i]) _max[i] = v;
      _sum[i] += v;
      total += v;
      levels[i] = (v / maxV).clamp(0.0, 1.0);
    }
    _frames++;

    // 흔들림 판정 — 앞 5프레임 총압력의 중앙값을 기준으로 편차를 본다.
    if (_baseTotal == null) {
      _warmup.add(total);
      if (_warmup.length >= 5) {
        final sorted = [..._warmup]..sort();
        _baseTotal = sorted[sorted.length ~/ 2];
      }
      _stable = true;
    } else {
      final base = _baseTotal! < 1 ? 1.0 : _baseTotal!;
      _stable = (total - base).abs() / base <= _tolerance;
      if (!_stable) _unstable++;
    }

    if (mounted) setState(() => _levels = levels);
  }

  void _finish() {
    _stop();

    final unstableRatio = _frames == 0 ? 1.0 : _unstable / _frames;
    if (_frames < _minFrames) {
      _fail('센서 신호를 거의 못 받았어요.\n방석 전원과 블루투스를 확인해 주세요.');
      return;
    }
    if (unstableRatio > _maxUnstableRatio) {
      _fail('자세가 많이 흔들렸어요.\n편하게 앉은 채로 다시 한 번 재볼까요?');
      return;
    }

    final r = CalibrationResult(
      channelMax: List.unmodifiable(_max),
      channelMean:
          List.unmodifiable([for (final s in _sum) s / _frames]),
      frames: _frames,
      elapsed: widget.duration,
    );
    setState(() {
      _result = r;
      _step = _Step.done;
    });
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() => _step = _Step.intro);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bg,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('다시 측정할까요?',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            )),
        content: Text(message, style: AppText.caption.copyWith(height: 1.6)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('나중에',
                style: TextStyle(color: AppColors.textTertiary)),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () {
              Navigator.of(ctx).pop();
              _start();
            },
            child: const Text('다시 측정'),
          ),
        ],
      ),
    );
  }

  void _stop() {
    _ticker?.cancel();
    _ticker = null;
    _sub?.cancel();
    _sub = null;
    _watch?.stop();
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: switch (_step) {
        _Step.intro => _IntroView(
            seconds: widget.duration.inSeconds,
            onStart: _start,
            onClose: () => Navigator.of(context).maybePop(),
          ),
        _Step.measuring => _MeasuringView(
            remaining: _remaining,
            ratio: _ratio,
            stable: _stable,
            levels: _levels,
            onCancel: () {
              _stop();
              setState(() => _step = _Step.intro);
            },
          ),
        _Step.done => _DoneView(
            result: _result!,
            onConfirm: () {
              widget.onDone?.call(_result!);
              Navigator.of(context).maybePop();
            },
            onRetry: _start,
          ),
      },
    );
  }
}

/// 측정 결과.
class CalibrationResult {
  const CalibrationResult({
    required this.channelMax,
    required this.channelMean,
    required this.frames,
    required this.elapsed,
  });

  /// 채널별 최대 압력. 서버 보정값(factor = FULL_SCALE / max)에 쓴다.
  final List<int> channelMax;

  /// 채널별 평균 압력. 온디바이스 판정의 기준 벡터.
  final List<double> channelMean;

  final int frames;
  final Duration elapsed;
}

// ─────────────────────────────────────────────────────────────
// 01 측정 안내
// ─────────────────────────────────────────────────────────────
class _IntroView extends StatelessWidget {
  const _IntroView({
    required this.seconds,
    required this.onStart,
    required this.onClose,
  });

  final int seconds;
  final VoidCallback onStart;
  final VoidCallback onClose;

  static const _checks = [
    '등을 등받이에 완전히 붙이세요',
    '두 발은 바닥에 나란히',
    '어깨는 힘 빼고 편하게',
  ];

  @override
  Widget build(BuildContext context) {
    return BmScreen(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.screen, 12, AppSpacing.screen, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: onClose,
                  behavior: HitTestBehavior.opaque,
                  child: const Icon(Icons.arrow_back_rounded,
                      color: AppColors.textPrimary),
                ),
                const BmPill(label: 'STEP 1 / 3'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.screen, 12, AppSpacing.screen, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('바른 자세를 측정할게요,\n$seconds초간 정자세를 유지해주세요',
                    style: AppText.display),
                const SizedBox(height: 10),
                const Text('지금 이 자세가 앞으로 정자세를 판단하는 기준이 돼요.',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: AppColors.textSecondary,
                    )),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(
                AppSpacing.screen, 0, AppSpacing.screen, 24),
            child: _SensorPadDiagram(),
          ),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
            child: Column(
              children: [
                for (var i = 0; i < _checks.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Text('${i + 1}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            )),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(_checks[i],
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            )),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.screen, 24, AppSpacing.screen, 12),
            child: BmPrimaryButton(label: '측정 시작하기', onPressed: onStart),
          ),
        ],
      ),
    );
  }
}

/// 등받이·좌석 압력 패드 배치도.
///
/// ⚠ 피그마와 맞춰 등받이 6 + 좌석 6 으로 그린다.
/// 실제 하드웨어(dev 기준)는 좌석 32채널이라 숫자가 다르다.
/// 하드웨어가 확정되면 이 그림과 채널 수를 함께 고쳐야 한다.
class _SensorPadDiagram extends StatelessWidget {
  const _SensorPadDiagram();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 272,
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          const SizedBox(height: 18),
          const _PadRow(label: '등받이 6ch', width: 140, height: 106),
          const SizedBox(height: 12),
          const _PadRow(label: '좌석 6ch', width: 160, height: 110),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _PadRow extends StatelessWidget {
  const _PadRow({
    required this.label,
    required this.width,
    required this.height,
  });

  final String label;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 16),
        SizedBox(
          width: 66,
          child: Text(label,
              style: AppText.caption.copyWith(fontSize: 10)),
        ),
        Expanded(
          child: Center(
            child: Container(
              width: width,
              height: height,
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var r = 0; r < 2; r++)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (var c = 0; c < 3; c++)
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: (r + c).isEven
                                  ? AppColors.primary
                                  : AppColors.primaryMid,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 02 측정 중
// ─────────────────────────────────────────────────────────────
class _MeasuringView extends StatelessWidget {
  const _MeasuringView({
    required this.remaining,
    required this.ratio,
    required this.stable,
    required this.levels,
    required this.onCancel,
  });

  final Duration remaining;
  final double ratio;
  final bool stable;
  final List<double> levels;
  final VoidCallback onCancel;

  static const _shown = 12;

  @override
  Widget build(BuildContext context) {
    final seconds = (remaining.inMilliseconds / 1000).ceil();

    return BmScreen(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(
                AppSpacing.screen, 12, AppSpacing.screen, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('자세 측정 중',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    )),
                BmPill(label: 'STEP 2 / 3'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.screen, 8, AppSpacing.screen, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('그대로,\n딱 그 자세로 멈춰요',
                    style: AppText.display.copyWith(fontSize: 28)),
                const SizedBox(height: 8),
                const Text('방석 압력 센서를 읽고 있어요.',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: AppColors.textSecondary,
                    )),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: BmRing(
              ratio: ratio,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$seconds',
                      style: AppText.display.copyWith(fontSize: 72)),
                  const SizedBox(height: 2),
                  Text('초 남았어요',
                      style: AppText.caption.copyWith(fontSize: 12)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: BmPill(
              label: stable ? '✓  자세가 안정적이에요' : '!  조금 흔들리고 있어요',
              color: stable ? AppColors.primary : AppColors.warnIcon,
              bg: stable ? AppColors.primarySoft : AppColors.warnBg,
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
            child: BmSoftCard(
              child: Column(
                children: [
                  BmCardCaption(
                    title: '실시간 압력',
                    trailing: levels.isEmpty
                        ? '신호 대기 중'
                        : '${levels.length} ch · 앞 $_shown채널',
                  ),
                  const SizedBox(height: 12),
                  for (var r = 0; r < 2; r++) ...[
                    if (r > 0) const SizedBox(height: 12),
                    Row(
                      children: [
                        for (var c = 0; c < 6; c++) ...[
                          if (c > 0) const SizedBox(width: 6),
                          Expanded(
                            child: _ChannelCell(
                              index: r * 6 + c,
                              level: (r * 6 + c) < levels.length
                                  ? levels[r * 6 + c]
                                  : 0,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.screen, 20, AppSpacing.screen, 12),
            child: BmGhostButton(label: '측정 취소', onPressed: onCancel),
          ),
        ],
      ),
    );
  }
}

class _ChannelCell extends StatelessWidget {
  const _ChannelCell({required this.index, required this.level});

  final int index;
  final double level;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.heat(level),
            borderRadius: BorderRadius.circular(7),
          ),
        ),
        const SizedBox(height: 5),
        Text('CH$index',
            style: AppText.caption.copyWith(fontSize: 9)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 03 측정 완료
// ─────────────────────────────────────────────────────────────
class _DoneView extends StatelessWidget {
  const _DoneView({
    required this.result,
    required this.onConfirm,
    required this.onRetry,
  });

  final CalibrationResult result;
  final VoidCallback onConfirm;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final seconds =
        (result.elapsed.inMilliseconds / 1000).toStringAsFixed(1);

    return BmScreen(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(
                AppSpacing.screen, 12, AppSpacing.screen, 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('자세 측정 완료',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    )),
                BmPill(label: 'STEP 3 / 3'),
              ],
            ),
          ),
          Center(
            child: Container(
              width: 88,
              height: 88,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded,
                  size: 48, color: Colors.white),
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
            child: Column(
              children: [
                Text('기준 자세,\n저장 완료!',
                    textAlign: TextAlign.center, style: AppText.display),
                const SizedBox(height: 10),
                const Text('이제 삐딱해지면 바로 알려드릴게요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: AppColors.textSecondary,
                    )),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
            child: BmSoftCard(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                children: [
                  _SummaryRow(label: '측정 시간', value: '$seconds초'),
                  const BmDivider(),
                  _SummaryRow(
                      label: '수집 프레임', value: '${result.frames} frames'),
                  const BmDivider(),
                  _SummaryRow(
                      label: '기준 채널',
                      value: '${result.channelMax.length} ch'),
                ],
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(
                AppSpacing.screen, 12, AppSpacing.screen, 0),
            child: Text(
              '기준값은 아직 서버에 저장되지 않습니다. (캘리브레이션 API 연동 예정)',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.screen, 24, AppSpacing.screen, 12),
            child: Column(
              children: [
                BmPrimaryButton(label: '자세 모니터링 시작', onPressed: onConfirm),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: onRetry,
                  child: const Text('다시 측정할래요',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textTertiary,
                      )),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textTertiary,
              )),
          Text(value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              )),
        ],
      ),
    );
  }
}
