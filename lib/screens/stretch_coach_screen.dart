import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../services/sitting_stats.dart';
import '../services/stretch_pose.dart';
import '../services/stretch_log.dart';
import '../theme/app_theme.dart';
import '../widgets/bm.dart';
import '../widgets/pose_camera.dart';
import 'stretch_done_screen.dart';
import 'stretch_screen.dart';

/// 스트레칭 코칭 — 피그마 「11 스트레칭 코칭」.
///
/// 전면 카메라 + ML Kit 관절 인식으로 동작을 확인하고 횟수를 센다.
///   - 동작마다 판정 규칙은 [StretchPoses] (lib/services/stretch_pose.dart)
///   - 그 자세를 잠깐 유지했다가 풀면 1회 ([RepCounter])
///   - 규칙이 없는 동작은 자동으로 세지 않고 '다음 동작'으로 넘긴다
///   - 영상은 기기에서만 분석하고 저장하지 않는다 (온디바이스 처리 원칙)
class StretchCoachScreen extends StatefulWidget {
  const StretchCoachScreen({super.key, required this.routine});

  final StretchRoutine routine;

  @override
  State<StretchCoachScreen> createState() => _StretchCoachScreenState();
}

class _StretchCoachScreenState extends State<StretchCoachScreen> {
  static const _targetCount = 5;

  int _moveIndex = 0;
  int _count = 0;
  bool _holding = false;

  /// 지금 동작의 횟수 판정기. 규칙이 없는 동작이면 null (수동 진행).
  RepCounter? _counter;

  /// 카메라에 사람이 보이는지 (상체 관절이 잡히는지).
  bool _personVisible = false;

  /// 루틴을 시작한 시각. 완료 화면의 '소요 시간'에 쓴다.
  late final DateTime _startedAt;

  /// '건너뛰기'로 넘긴 동작 수. 완료 동작 수 = 전체 - 이 값.
  int _skipped = 0;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _setupCounter();
  }

  void _setupCounter() {
    final check = StretchPoses.checkFor(widget.routine.moves[_moveIndex]);
    _counter = check == null ? null : RepCounter(check);
    _holding = false;
  }

  /// [PoseCamera] 가 프레임마다 부른다.
  void _onPose(Pose? pose, DateTime at) {
    final visible = pose != null && PoseView(pose).upperBodyVisible;
    var holding = false;
    var count = _count;
    final counter = _counter;
    if (pose != null && counter != null && count < _targetCount) {
      if (counter.add(pose, at)) count++;
      holding = counter.holding;
    }
    if (visible != _personVisible || holding != _holding || count != _count) {
      setState(() {
        _personVisible = visible;
        _holding = holding;
        _count = count;
      });
    }
  }

  String get _badgeText {
    if (!_personVisible) return '상체가 화면에 보이게 앉아주세요';
    if (_counter == null) return '천천히 따라 하고 다음 동작으로 넘어가요';
    if (_count >= _targetCount) return '완료! 다음 동작으로 넘어가요';
    return _holding ? '좋아요 · 그대로 유지' : '자세를 잡아주세요';
  }

  void _next({bool skipped = false}) {
    if (skipped) _skipped++;

    if (_moveIndex < widget.routine.moves.length - 1) {
      setState(() {
        _moveIndex++;
        _count = 0;
        _setupCounter();
      });
    } else {
      _finish();
    }
  }

  /// 마지막 동작까지 끝났다. 완료 화면(11-D)으로 교체한다.
  void _finish() {
    SittingStats.instance.recordStretch();
    final total = widget.routine.moves.length;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => StretchDoneScreen(
          routine: widget.routine,
          elapsed: DateTime.now().difference(_startedAt),
          completed: total - _skipped,
          total: total,
          todayCount: StretchLog.instance.record(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final moves = widget.routine.moves;
    final isLast = _moveIndex == moves.length - 1;

    return Scaffold(
      backgroundColor: const Color(0xFF212429),
      body: Column(
        children: [
          // ── 카메라 프리뷰 자리 ──────────────────
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: PoseCamera(onPose: _onPose)),

                // 상단 바
                Positioned(
                  left: 20,
                  right: 20,
                  top: MediaQuery.of(context).padding.top + 8,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _GlassButton(
                        icon: Icons.close_rounded,
                        onTap: () => Navigator.of(context).pop(),
                      ),
                      _GlassLabel(
                          text: '동작 ${_moveIndex + 1} / ${moves.length}'),
                    ],
                  ),
                ),

                // 프라이버시 고지
                Positioned(
                  left: 0,
                  right: 0,
                  top: MediaQuery.of(context).padding.top + 56,
                  child: const Center(
                    child: _GlassLabel(text: '기기에서만 분석 · 영상은 저장되지 않아요'),
                  ),
                ),

                // 판정 배지
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 24,
                  child: Center(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: _holding || _count >= _targetCount ? 1 : 0.6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _badgeText,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── 하단 시트 ──────────────────────────
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
              AppSpacing.screen,
              20,
              AppSpacing.screen,
              MediaQuery.of(context).padding.bottom + 16,
            ),
            decoration: const BoxDecoration(
              color: AppColors.bg,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${widget.routine.posture.label} 루틴',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              )),
                          const SizedBox(height: 4),
                          Text(moves[_moveIndex],
                              style: AppText.display.copyWith(fontSize: 24)),
                        ],
                      ),
                    ),
                    Text(_counter == null ? '자유 동작' : '$_count / $_targetCount회',
                        style: AppText.display.copyWith(
                          fontSize: 22,
                          color: AppColors.primary,
                        )),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    for (var i = 0; i < _targetCount; i++) ...[
                      if (i > 0) const SizedBox(width: 6),
                      Expanded(
                        child: Container(
                          height: 8,
                          decoration: BoxDecoration(
                            color: i < _count
                                ? AppColors.primary
                                : AppColors.border,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                BmSoftCard(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Icon(Icons.lightbulb_outline_rounded,
                          size: 18, color: AppColors.textTertiary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _tipFor(moves[_moveIndex]),
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.55,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: BmGhostButton(
                        label: '건너뛰기',
                        onPressed: () => _next(skipped: true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 52,
                        child: FilledButton(
                          onPressed: () => _next(),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  AppSpacing.radiusButton),
                            ),
                          ),
                          child: Text(isLast ? '루틴 끝내기' : '다음 동작',
                              style: AppText.button.copyWith(fontSize: 17)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _tipFor(String move) => switch (move) {
        '목 옆으로 늘이기' => '반대쪽 어깨는 아래로 눌러주세요. 통증이 느껴지면 바로 멈추세요.',
        '목 뒤로 젖히기' => '턱을 천천히 들어 올려 5초간 멈추세요. 어지러우면 바로 멈추세요.',
        '팔 양 옆으로 늘리기' => '손끝까지 쭉 뻗고 어깨는 아래로 내려주세요. 가슴을 활짝 열어줍니다.',
        _ => '천천히, 반동 없이. 통증이 느껴지면 바로 멈추세요.',
      };
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          // ignore: deprecated_member_use
          color: Colors.white.withOpacity(0.16),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: Colors.white),
      ),
    );
  }
}

class _GlassLabel extends StatelessWidget {
  const _GlassLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      decoration: BoxDecoration(
        // ignore: deprecated_member_use
        color: Colors.white.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          )),
    );
  }
}
