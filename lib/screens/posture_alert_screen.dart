import 'package:flutter/material.dart';

import '../models/posture_alert.dart';
import '../services/alert_store.dart';
import '../theme/app_theme.dart';
import '../widgets/bm.dart';
import 'stretch_screen.dart';

/// 자세 알림 — 피그마 「13 자세 알림」.
///
/// 같은 나쁜 자세가 [PostureAlertScreen.threshold] 이상 이어졌을 때 띄운다.
/// 사용자가 스트레칭을 고르면 [AlertStore.markLatestStretched] 로 기록에 남는다.
class PostureAlertScreen extends StatelessWidget {
  const PostureAlertScreen({
    super.key,
    required this.alert,
    this.todayCount = 1,
  });

  /// 알림 기준 시간. 나쁜 자세가 이만큼 이어지면 알린다.
  static const Duration threshold = Duration(minutes: 5);

  final PostureAlert alert;

  /// 오늘 몇 번째 알림인지 (보관 한도와 무관하게 세는 값).
  final int todayCount;

  Color get _color => alert.posture.color;

  String get _advice => alert.posture.advice;

  String get _routine =>
      StretchScreen.routineFor(alert.posture)?.title ?? '가벼운 스트레칭';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: BmScreen(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 헤더
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen, 12, AppSpacing.screen, 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    behavior: HitTestBehavior.opaque,
                    child: const Icon(Icons.close_rounded,
                        color: AppColors.textTertiary),
                  ),
                  BmPill(
                    label: '오늘 $todayCount번째',
                    color: _color,
                    // ignore: deprecated_member_use
                    bg: _color.withOpacity(0.12),
                  ),
                ],
              ),
            ),

            // 큰 아이콘
            Center(
              child: Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  // ignore: deprecated_member_use
                  color: _color.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.airline_seat_recline_normal_rounded,
                    size: 56, color: _color),
              ),
            ),
            const SizedBox(height: 24),

            // 헤드라인
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen, 0, AppSpacing.screen, 24),
              child: Column(
                children: [
                  Text('${alert.heldFor.inMinutes}분째 ${alert.posture.label}이에요',
                      textAlign: TextAlign.center, style: AppText.display),
                  const SizedBox(height: 10),
                  Text(_advice,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        color: AppColors.textSecondary,
                      )),
                ],
              ),
            ),

            // 지속 시간
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen, 0, AppSpacing.screen, 14),
              child: BmSoftCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('이 자세를 유지한 시간',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textTertiary,
                            )),
                        Text(alert.heldLabel.replaceAll(' 유지', ''),
                            style: AppText.display
                                .copyWith(fontSize: 20, color: _color)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    BmBand(
                      height: 12,
                      segments: [
                        const MapEntry(3, AppColors.primary),
                        MapEntry(9, _color),
                        const MapEntry(3, AppColors.border),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '알림 기준: ${threshold.inMinutes}분 이상 같은 나쁜 자세',
                        style: AppText.caption.copyWith(fontSize: 10),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 추천 루틴
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screen),
              child: BmSoftCard(
                color: AppColors.primarySoft,
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.bg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.self_improvement_rounded,
                          size: 22, color: AppColors.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_routine,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              )),
                          const SizedBox(height: 3),
                          Text('3동작 · 약 2분',
                              style: AppText.caption.copyWith(fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const Spacer(),

            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen, 12, AppSpacing.screen, 12),
              child: Column(
                children: [
                  BmPrimaryButton(
                    label: '스트레칭 하러 가기',
                    onPressed: () {
                      AlertStore.instance.markLatestStretched();
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                            builder: (_) => const StretchScreen()),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  BmGhostButton(
                    label: '10분 뒤에 다시 알려주세요',
                    onPressed: () => Navigator.of(context).maybePop(),
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
