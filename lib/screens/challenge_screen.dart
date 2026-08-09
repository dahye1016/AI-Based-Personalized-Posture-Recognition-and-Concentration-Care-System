import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/mock_data.dart';
import '../widgets/common.dart';
import '../widgets/charts.dart';
import '../widgets/tiles.dart';

/// 집중 챌린지 — 목표 진행률 / 주간 기록 / 배지
class ChallengeScreen extends StatelessWidget {
  const ChallengeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final remain = (MockData.challengeGoal - MockData.challengeDone).clamp(0, 999);
    return Scaffold(
      appBar: AppBar(title: const Text('집중 챌린지')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.screen, 4, AppSpacing.screen, 28),
        children: [
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Column(
              children: [
                const DonutProgress(
                  done: MockData.challengeDone,
                  goal: MockData.challengeGoal,
                ),
                const SizedBox(height: 20),
                Text(
                  '${MockData.challengeGoal}분 바른자세 유지',
                  style: AppText.cardTitle,
                ),
                const SizedBox(height: 4),
                Text('$remain분 남았어요', style: AppText.body),
              ],
            ),
          ),
          const SizedBox(height: 22),

          const SectionHeader('이번 주 기록'),
          const WeekStrip(values: MockData.week),
          const SizedBox(height: 24),

          const SectionHeader('획득 배지'),
          Row(
            children: [
              for (int i = 0; i < MockData.badges.length; i++) ...[
                Expanded(child: BadgeCard(badge: MockData.badges[i])),
                if (i != MockData.badges.length - 1) const SizedBox(width: 12),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
