import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/bm.dart';

/// 온보딩 — 피그마 「04 온보딩」.
///
/// 앱 첫 진입에서 무엇을 해주는 앱인지 3줄로 알린다.
/// [onStart] 를 넘기면 "시작하기"에서 호출된다(보통 기기 연결/측정으로 이동).
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key, this.onStart});

  final VoidCallback? onStart;

  static const _features = [
    (
      icon: Icons.notifications_active_outlined,
      title: '실시간 자세 알림',
      desc: '거북목·다리꼬기가 20초 넘게 이어지면 진동으로 알려요.',
    ),
    (
      icon: Icons.insights_outlined,
      title: '일간·주간 리포트',
      desc: '하루 중 바른 자세 비율과 시간대별 변화를 정리해줘요.',
    ),
    (
      icon: Icons.self_improvement_outlined,
      title: '스트레칭 코칭',
      desc: '카메라가 관절을 보고 제대로 따라 했는지 세어줘요.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: BmScreen(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 60),

            // ── 브랜드 ───────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen, 0, AppSpacing.screen, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('POSTURECARE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.6,
                        color: AppColors.primary,
                      )),
                  const SizedBox(height: 12),
                  Text('의자는 그대로,\n자세만 바꿔요',
                      style: AppText.display.copyWith(fontSize: 34)),
                  const SizedBox(height: 12),
                  const Text(
                    '쓰던 의자에 방석 하나 얹으면 끝.\n앉은 자세를 읽고, 삐딱해지면 바로 알려드려요.',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            // ── 기능 3종 ─────────────────────────
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
              child: Column(
                children: [
                  for (var i = 0; i < _features.length; i++) ...[
                    if (i > 0) const SizedBox(height: 18),
                    _FeatureRow(
                      icon: _features[i].icon,
                      title: _features[i].title,
                      desc: _features[i].desc,
                    ),
                  ],
                ],
              ),
            ),

            const Spacer(),

            // ── CTA ──────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen, 24, AppSpacing.screen, 12),
              child: Column(
                children: [
                  BmPrimaryButton(
                    label: '시작하기',
                    onPressed: onStart ?? () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 10),
                  const Text('방석 센서와 블루투스 연결이 필요해요',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textTertiary,
                      )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.desc,
  });

  final IconData icon;
  final String title;
  final String desc;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: AppColors.primary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  )),
              const SizedBox(height: 3),
              Text(desc,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.55,
                    color: AppColors.textSecondary,
                  )),
            ],
          ),
        ),
      ],
    );
  }
}
