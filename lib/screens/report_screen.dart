import 'package:flutter/material.dart';

import '../services/profile_store.dart';
import '../services/sitting_stats.dart';
import '../theme/app_theme.dart';
import '../widgets/bm.dart';

/// 리포트 — 피그마 「07 리포트 · 일간」 / 「08 리포트 · 주간」.
///
/// 방석에 실제로 앉아 있던 시간([SittingStats])만으로 만든다.
/// 기록이 없으면 가짜 숫자 대신 '아직 기록이 없어요'를 보여준다.
class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key, this.onBack});

  /// 하단 탭으로 열렸을 때 '뒤로' = 실시간 탭으로. 없고 push 로 열렸으면 이전 화면으로.
  final VoidCallback? onBack;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  int _tab = 0; // 0=일간, 1=주간

  static const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  static String _date(DateTime d) =>
      '${d.month}월 ${d.day}일 ${_weekdays[d.weekday - 1]}요일';

  static String _short(DateTime d) => '${d.month}월 ${d.day}일';

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final weekStart = now.subtract(const Duration(days: 6));
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: BmScreen(
        bottom: false,
        child: ListenableBuilder(
          listenable: SittingStats.instance,
          // BmScreen 이 이미 스크롤을 감싸므로 여기서는 Column 만 둔다.
          builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BmHeader(
                  leading: widget.onBack != null || Navigator.of(context).canPop() ? BmBackButton(onTap: widget.onBack) : null,
                  eyebrow: '${ProfileStore.instance.displayName}님 · '
                      '${_tab == 0 ? _date(now) : '${_short(weekStart)} – ${_short(now)}'}',
                  title: _tab == 0 ? '오늘의 리포트' : '이번 주 리포트',
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screen, 0, AppSpacing.screen, 16),
                  child: BmSegmented(
                    labels: const ['일간', '주간'],
                    index: _tab,
                    onChanged: (i) => setState(() => _tab = i),
                  ),
                ),
                if (_tab == 0)
                  _DailyBody(day: SittingStats.instance.today)
                else
                  _WeeklyBody(days: SittingStats.instance.lastWeek),
                const SizedBox(height: 16),
              ],
            ),
        ),
      ),
    );
  }
}

String _fmt(Duration d) => SittingStats.format(d);

/// 기록이 없을 때 카드.
class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.screen, 0, AppSpacing.screen, 16),
      child: BmSoftCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.event_seat_outlined,
                size: 32, color: AppColors.textTertiary),
            const SizedBox(height: 10),
            Text(title, style: AppText.display.copyWith(fontSize: 17)),
            const SizedBox(height: 6),
            Text(body,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: AppColors.textSecondary,
                )),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 일간
// ─────────────────────────────────────────────────────────────
class _DailyBody extends StatelessWidget {
  const _DailyBody({required this.day});

  final DayStats day;

  @override
  Widget build(BuildContext context) {
    final pct = (day.straightRatio * 100).round();
    final stats = Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.screen, 0, AppSpacing.screen, 16),
      child: Row(
        children: [
          Expanded(
            child: BmStatTile(label: '오늘 착석', value: _fmt(day.sitting)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: BmStatTile(
                label: '바른 자세 $pct%', value: _fmt(day.straight)),
          ),
        ],
      ),
    );

    // postures 는 지금 자세 목록에 있는 것만 남긴다. 예전 기록(거북목)만 있는 날은
    // hasData 여도 비어 있어서 아래 postures.first 가 터지므로 빈 카드로 보낸다.
    if (!day.hasData || day.postures.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          stats,
          const _EmptyCard(
            title: '아직 오늘 착석 기록이 없어요',
            body: '방석 센서를 연결하고 앉으면\n자세별 시간이 자동으로 쌓여요.',
          ),
        ],
      );
    }

    final postures = day.postures;
    final total = day.sitting.inMilliseconds;
    final top = postures.first;
    final topPct = (top.value.inMilliseconds / total * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        stats,

        // 자세 분포 — 실제 앉은 시간 비율
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.screen, 0, AppSpacing.screen, 16),
          child: BmCard(
            child: Column(
              children: [
                const BmCardCaption(title: '자세 분포', trailing: '앉아 있던 시간 기준'),
                const SizedBox(height: 14),
                BmDonut(
                  slices: [
                    for (final e in postures)
                      BmDonutSlice(e.key.label,
                          e.value.inMilliseconds.toDouble(), e.key.color),
                  ],
                  center: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('$topPct%',
                          style: AppText.display.copyWith(fontSize: 34)),
                      const SizedBox(height: 2),
                      Text(top.key.label, style: AppText.caption),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                for (var i = 0; i < postures.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  BmLegendRow(
                    color: postures[i].key.color,
                    label: postures[i].key.label,
                    value: _fmt(postures[i].value),
                  ),
                ],
              ],
            ),
          ),
        ),

        // 시간대별 착석
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.screen, 0, AppSpacing.screen, 16),
          child: _HourlyCard(day: day),
        ),

        // 알림 / 스트레칭
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
          child: Row(
            children: [
              Expanded(
                  child: _MetricTile(
                      value: '${day.alerts}회', label: '나쁜 자세 알림')),
              const SizedBox(width: 10),
              Expanded(
                  child: _MetricTile(
                      value: '${day.stretches}회', label: '스트레칭')),
            ],
          ),
        ),
      ],
    );
  }
}

/// 처음 앉은 시각 ~ 마지막으로 앉은 시각을 1시간 칸으로 나눠 그린다.
/// 칸 색: 앉지 않음 = 회색, 바른 자세 70% 이상 = 민트, 40% 이상 = 옅은 민트, 그 아래 = 주황.
class _HourlyCard extends StatelessWidget {
  const _HourlyCard({required this.day});

  final DayStats day;

  @override
  Widget build(BuildContext context) {
    var first = -1, last = -1;
    for (var h = 0; h < 24; h++) {
      if (day.hourSitting[h] > 0) {
        if (first < 0) first = h;
        last = h;
      }
    }
    final longest = Duration(milliseconds: day.longestStraightMs);

    Color colorOf(int h) {
      final s = day.hourSitting[h];
      if (s <= 0) return AppColors.border;
      final r = day.hourStraight[h] / s;
      if (r >= 0.7) return AppColors.primary;
      if (r >= 0.4) return AppColors.primaryMid;
      return AppColors.warnIcon;
    }

    return BmSoftCard(
      child: Column(
        children: [
          BmCardCaption(
            title: '시간대별 착석',
            trailing: longest.inMinutes > 0
                ? '바른 자세 최장 ${_fmt(longest)}'
                : null,
          ),
          const SizedBox(height: 10),
          BmBand(
            height: 16,
            segments: [
              for (var h = first; h <= last; h++) MapEntry(1, colorOf(h)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$first시', style: AppText.caption),
              if (last - first >= 2)
                Text('${(first + last + 1) ~/ 2}시', style: AppText.caption),
              Text('${last + 1}시', style: AppText.caption),
            ],
          ),
          const SizedBox(height: 10),
          const Row(
            children: [
              _Dot(color: AppColors.primary, label: '바른 자세 70%↑'),
              SizedBox(width: 10),
              _Dot(color: AppColors.primaryMid, label: '40%↑'),
              SizedBox(width: 10),
              _Dot(color: AppColors.warnIcon, label: '40% 미만'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: AppText.caption.copyWith(fontSize: 10)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 주간
// ─────────────────────────────────────────────────────────────
class _WeeklyBody extends StatelessWidget {
  const _WeeklyBody({required this.days});

  /// 최근 7일 (오래된 날 → 오늘).
  final List<DayStats> days;

  static const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  @override
  Widget build(BuildContext context) {
    final withData = days.where((d) => d.hasData).toList();
    final totalSit =
        days.fold<Duration>(Duration.zero, (a, d) => a + d.sitting);
    final totalStraight =
        days.fold<Duration>(Duration.zero, (a, d) => a + d.straight);
    final alerts = days.fold<int>(0, (a, d) => a + d.alerts);
    final stretches = days.fold<int>(0, (a, d) => a + d.stretches);
    final avg = totalSit.inMilliseconds == 0
        ? 0
        : (totalStraight.inMilliseconds / totalSit.inMilliseconds * 100)
            .round();

    if (withData.isEmpty) {
      return const _EmptyCard(
        title: '이번 주 착석 기록이 없어요',
        body: '방석에 앉은 날이 쌓이면\n요일별 바른 자세 비율을 보여드려요.',
      );
    }

    String summary;
    if (withData.length >= 2) {
      final best =
          withData.reduce((a, b) => a.straightRatio >= b.straightRatio ? a : b);
      summary = '${_weekdays[best.day.weekday - 1]}요일이 제일 반듯했어요 '
          '(바른 자세 ${(best.straightRatio * 100).round()}%).';
    } else {
      summary = '기록이 이틀 이상 쌓이면 요일별로 비교해 드려요.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 한 줄 요약
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.screen, 0, AppSpacing.screen, 16),
          child: BmSoftCard(
            color: AppColors.primarySoft,
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('이번 주 바른 자세 $avg%',
                    style: AppText.display.copyWith(fontSize: 20)),
                const SizedBox(height: 6),
                Text(summary,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.55,
                      color: AppColors.textSecondary,
                    )),
              ],
            ),
          ),
        ),

        // 요일별 막대 (기록 없는 날은 빈 칸)
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.screen, 0, AppSpacing.screen, 16),
          child: BmCard(
            child: Column(
              children: [
                BmCardCaption(title: '요일별 바른자세 비율', trailing: '평균 $avg%'),
                const SizedBox(height: 16),
                SizedBox(
                  height: 150,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < days.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(child: _DayBar(day: days[i])),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // 주간 지표
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
          child: Row(
            children: [
              Expanded(child: _MetricTile(value: _fmt(totalSit), label: '총 착석')),
              const SizedBox(width: 10),
              Expanded(child: _MetricTile(value: '$alerts회', label: '나쁜 자세 알림')),
              const SizedBox(width: 10),
              Expanded(child: _MetricTile(value: '$stretches회', label: '스트레칭')),
            ],
          ),
        ),
      ],
    );
  }
}

class _DayBar extends StatelessWidget {
  const _DayBar({required this.day});

  final DayStats day;

  static const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  @override
  Widget build(BuildContext context) {
    final r = day.straightRatio;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(day.hasData ? '${(r * 100).round()}' : '–',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.textTertiary,
            )),
        const SizedBox(height: 8),
        Container(
          height: day.hasData ? (r * 100).clamp(4.0, 100.0).toDouble() : 4.0,
          decoration: BoxDecoration(
            color: !day.hasData
                ? AppColors.border
                : r >= 0.7
                    ? AppColors.primary
                    : AppColors.primaryMid,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(height: 8),
        Text(_weekdays[day.day.weekday - 1], style: AppText.caption),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return BmSoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      child: Column(
        children: [
          FittedBox(
            child: Text(value, style: AppText.statNumber.copyWith(fontSize: 18)),
          ),
          const SizedBox(height: 5),
          Text(label,
              textAlign: TextAlign.center,
              style: AppText.caption.copyWith(fontSize: 10)),
        ],
      ),
    );
  }
}
