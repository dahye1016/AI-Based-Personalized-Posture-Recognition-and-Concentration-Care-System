import 'package:flutter/material.dart';

import '../services/sitting_stats.dart';
import '../theme/app_theme.dart';
import '../widgets/bm.dart';

/// 집중 챌린지 — 피그마 「09 집중 챌린지」.
///
/// 하루 목표만큼 **정자세로 앉아 있기**. 값은 모두 실제 착석 기록([SittingStats],
/// 로그인 사용자별)에서 계산한다. 서버 `/challenges` 와 같은 규칙:
/// 그날 정자세 누적 시간이 목표 이상이면 성공.
class ChallengeScreen extends StatefulWidget {
  const ChallengeScreen({super.key, this.onBack});

  /// 하단 탭으로 열렸을 때 '뒤로' = 실시간 탭으로. 없고 push 로 열렸으면 이전 화면으로.
  final VoidCallback? onBack;

  @override
  State<ChallengeScreen> createState() => _ChallengeScreenState();
}

class _ChallengeScreenState extends State<ChallengeScreen> {
  static const _courses = [25, 30, 50, 90];
  static const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  SittingStats get _s => SittingStats.instance;
  int get _goal => _s.challengeGoalMin;
  int get _done => _s.today.straight.inMinutes;
  double get _ratio => _goal == 0 ? 0 : (_done / _goal).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SittingStats.instance,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final today = _s.today;
    final week = _s.lastWeek;
    final streak = _s.streak;
    final pct = (today.straightRatio * 100).round();
    final left = (_goal - _done).clamp(0, _goal);
    final badges = [
      _BadgeData('첫 완주', Icons.emoji_events, _s.everAchieved, AppColors.infoText),
      _BadgeData('3일 연속', Icons.local_fire_department, streak >= 3, AppColors.warnIcon),
      _BadgeData('5일 연속', Icons.workspace_premium, streak >= 5, AppColors.primary),
    ];
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: BmScreen(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BmHeader(
                leading: widget.onBack != null || Navigator.of(context).canPop() ? BmBackButton(onTap: widget.onBack) : null,
                eyebrow: '오늘의 목표 $_goal분',
                title: '집중 챌린지'),

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
                        Text(
                            _done >= _goal
                                ? '오늘 목표 달성! 🎉'
                                : '바른 자세 $_goal분 중 $_done분 · $left분 남았어요',
                            style: AppText.caption),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  BmPill(
                      label: today.hasData
                          ? '바른 자세 유지율 $pct%'
                          : '아직 오늘 착석 기록이 없어요'),
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
                            onTap: () => _s.setChallengeGoal(_courses[i]),
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
                      trailing: streak > 0 ? '$streak일째 🔥' : '오늘부터 시작해요',
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        for (var i = 0; i < week.length; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          Expanded(
                            child: _DayDot(
                              label: _weekdays[week[i].day.weekday - 1],
                              done: _s.achieved(week[i]),
                              partial: !_s.achieved(week[i]) &&
                                  week[i].straight.inMinutes > 0,
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
                  for (var i = 0; i < badges.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(child: _Badge(item: badges[i])),
                  ],
                ],
              ),
            ),

            const Spacer(),
            const Padding(
              padding: EdgeInsets.fromLTRB(
                  AppSpacing.screen, 16, AppSpacing.screen, 16),
              child: Text('방석에 정자세로 앉아 있던 시간만 쌓여요',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
            ),
          ],
        ),
      ),
    );
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

class _BadgeData {
  const _BadgeData(this.label, this.icon, this.unlocked, this.color);

  final String label;
  final IconData icon;
  final bool unlocked;
  final Color color;
}

class _Badge extends StatelessWidget {
  const _Badge({required this.item});

  final _BadgeData item;

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
