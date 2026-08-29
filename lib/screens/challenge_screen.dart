import 'package:flutter/material.dart';

import '../models/mock_data.dart';
import '../theme/app_theme.dart';
import '../widgets/bm.dart';

/// 집중 챌린지 — 피그마 「09 집중 챌린지」.
///
/// 값은 MockData 기반. 서버가 붙으면 `GET /challenges/{user_id}` 로 갈아끼운다.
/// (서버는 현재 목표 30분이 하드코딩돼 있어, 코스 선택을 반영하려면
///  서버 쪽도 목표 시간을 파라미터로 받도록 고쳐야 한다.)
class ChallengeScreen extends StatefulWidget {
  const ChallengeScreen({super.key});

  @override
  State<ChallengeScreen> createState() => _ChallengeScreenState();
}

class _ChallengeScreenState extends State<ChallengeScreen> {
  static const _courses = [25, 30, 50, 90];
  int _goal = MockData.challengeGoal;

  int get _done => MockData.challengeDone.clamp(0, _goal);
  double get _ratio => _goal == 0 ? 0 : _done / _goal;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: BmScreen(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BmHeader(eyebrow: '오늘의 목표 $_goal분', title: '집중 챌린지'),

            // ── 진행 링 ──────────────────────────
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(
                children: [
                  BmRing(
                    ratio: _ratio,
                    size: 184,
                    stroke: 15,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('$_done',
                            style: AppText.display.copyWith(fontSize: 56)),
                        const SizedBox(height: 2),
                        Text('$_goal분 중 $_done분 지났어요',
                            style: AppText.caption),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const BmPill(label: '바른 자세 유지율 84%'),
                ],
              ),
            ),

            // ── 코스 선택 ────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen, 18, AppSpacing.screen, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('코스 바꾸기',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      )),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      for (var i = 0; i < _courses.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          child: BmChip(
                            label: '${_courses[i]}분',
                            selected: _courses[i] == _goal,
                            onTap: () => setState(() => _goal = _courses[i]),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // ── 연속 달성 ────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen, 0, AppSpacing.screen, 16),
              child: BmCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    BmCardCaption(
                      title: '연속 달성',
                      trailing: '${_streak()}일째 🔥',
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        for (var i = 0; i < MockData.week.length; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          Expanded(
                            child: _DayDot(
                              label: const ['월', '화', '수', '목', '금', '토', '일'][i],
                              done: MockData.week[i] >= 1.0,
                              partial: MockData.week[i] > 0 &&
                                  MockData.week[i] < 1.0,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // ── 배지 ─────────────────────────────
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
              child: Row(
                children: [
                  for (var i = 0; i < MockData.badges.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(child: _Badge(item: MockData.badges[i])),
                  ],
                ],
              ),
            ),

            const Spacer(),

            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen, 16, AppSpacing.screen, 12),
              child: BmGhostButton(label: '오늘은 여기까지', onPressed: () {}),
            ),
          ],
        ),
      ),
    );
  }

  int _streak() {
    var n = 0;
    for (final v in MockData.week) {
      if (v >= 1.0) {
        n++;
      } else {
        break;
      }
    }
    return n;
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({
    required this.label,
    required this.done,
    required this.partial,
  });

  final String label;
  final bool done;
  final bool partial;

  @override
  Widget build(BuildContext context) {
    final bg = done
        ? AppColors.primary
        : partial
            ? AppColors.primaryMid
            : AppColors.surface;
    return Column(
      children: [
        Container(
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: done
              ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
              : null,
        ),
        const SizedBox(height: 6),
        Text(label, style: AppText.caption.copyWith(fontSize: 10)),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.item});

  final BadgeItem item;

  @override
  Widget build(BuildContext context) {
    return BmSoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      child: Column(
        children: [
          Icon(
            item.icon,
            size: 24,
            color: item.unlocked ? item.color : AppColors.textTertiary,
          ),
          const SizedBox(height: 8),
          Text(
            item.label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: item.unlocked
                  ? AppColors.textPrimary
                  : AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
