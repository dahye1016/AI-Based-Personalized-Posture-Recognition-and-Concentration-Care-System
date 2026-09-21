import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/bm.dart';
import 'stretch_coach_screen.dart';
import 'stretch_screen.dart';

/// 스트레칭 완료 — 피그마 「11-D 스트레칭 완료」.
///
/// 코칭 화면([StretchCoachScreen])이 마지막 동작에서 pushReplacement 로 띄운다.
/// 구성·스타일은 캘리브레이션 완료 화면(`calibration_screen.dart` 의 _DoneView)과
/// 같게 맞췄다.
class StretchDoneScreen extends StatelessWidget {
  const StretchDoneScreen({
    super.key,
    required this.routine,
    required this.elapsed,
    required this.completed,
    required this.total,
    required this.todayCount,
  });

  final StretchRoutine routine;

  /// 루틴을 시작해서 끝낼 때까지 걸린 시간.
  final Duration elapsed;

  /// 건너뛰지 않고 끝낸 동작 수.
  final int completed;

  /// 루틴의 전체 동작 수.
  final int total;

  /// 오늘 몇 번째 스트레칭인지 ([StretchLog] 가 센 값).
  final int todayCount;

  /// 제목에 쓰는 루틴 이름 — '목·어깨 풀기 루틴' → '목·어깨 풀기'.
  String get _shortTitle => routine.title.replaceFirst(' 루틴', '');

  @override
  Widget build(BuildContext context) {
    final elapsedLabel =
        '${elapsed.inMinutes}분 ${elapsed.inSeconds % 60}초';

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: BmScreen(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen, 12, AppSpacing.screen, 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('스트레칭 완료',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      )),
                  BmPill(label: '$completed / $total 동작'),
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
                  Text('$_shortTitle\n완료!',
                      textAlign: TextAlign.center, style: AppText.display),
                  const SizedBox(height: 10),
                  const Text('잘했어요. 다시 바른 자세로 앉아볼까요?',
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
                    _SummaryRow(label: '소요 시간', value: elapsedLabel),
                    const BmDivider(),
                    _SummaryRow(
                        label: '완료 동작', value: '$completed / $total'),
                    const BmDivider(),
                    _SummaryRow(
                        label: '오늘 스트레칭', value: '$todayCount회째'),
                  ],
                ),
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen, 24, AppSpacing.screen, 12),
              child: Column(
                children: [
                  BmPrimaryButton(
                    label: '실시간 자세로 돌아가기',
                    onPressed: () => Navigator.of(context)
                        .popUntil((route) => route.isFirst),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => StretchCoachScreen(routine: routine),
                      ),
                    ),
                    child: const Text('한 번 더 할래요',
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
