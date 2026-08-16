import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/mock_data.dart';
import '../widgets/common.dart';
import '../widgets/tiles.dart';
import '../widgets/pressure_heatmap.dart';

/// 초기 설정 — 자세 등록 온보딩 (별도 흐름)
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  static const _steps = 4;
  static const _stepDone = 2;
  static const _stripValues = <double>[0.1, 0.4, 0.5, 0.7, 0.9, 0.5, 0.2];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('초기 설정')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.screen, 8, AppSpacing.screen, 28),
        children: [
          // 진행 스텝 바
          Row(
            children: [
              for (int i = 0; i < _steps; i++) ...[
                Expanded(
                  child: Container(
                    height: 5,
                    decoration: BoxDecoration(
                      color: i < _stepDone
                          ? AppColors.primary
                          : AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                if (i != _steps - 1) const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 24),

          const Text('자세 등록', style: AppText.screenTitle),
          const SizedBox(height: 6),
          const Text('각 자세로 앉은 뒤 버튼을 눌러주세요', style: AppText.body),
          const SizedBox(height: 20),

          ...MockData.registerPoses.map((p) => RegisterPoseItem(pose: p)),
          const SizedBox(height: 10),

          const PressureStrip(values: _stripValues),
          const SizedBox(height: 20),

          PrimaryButton(
            label: '이 자세로 등록',
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}
