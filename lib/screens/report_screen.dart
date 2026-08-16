import 'package:flutter/material.dart';

import '../models/mock_data.dart';
import '../theme/app_theme.dart';
import '../widgets/bm.dart';

/// 리포트 — 피그마 「07 리포트 · 일간」 / 「08 리포트 · 주간」.
///
/// 상단 세그먼트로 두 화면을 전환한다.
/// 지금 값은 MockData 기반이며, 서버가 붙으면
/// `GET /reports/daily`, `GET /reports/weekly` 응답으로 갈아끼운다.
class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  int _tab = 0; // 0=일간, 1=주간

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: BmScreen(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BmHeader(
              eyebrow: _tab == 0 ? '8월 16일 토요일' : '8월 10일 – 8월 16일',
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
            if (_tab == 0) const _DailyBody() else const _WeeklyBody(),
            const SizedBox(height: 16),
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
  const _DailyBody();

  @override
  Widget build(BuildContext context) {
    final slices = [
      for (final s in MockData.distribution)
        BmDonutSlice(s.label, s.percent.toDouble(), s.color),
    ];
    final top = MockData.distribution.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 자세 분포 도넛
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.screen, 0, AppSpacing.screen, 16),
          child: BmCard(
            child: Column(
              children: [
                BmDonut(
                  slices: slices,
                  center: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${top.percent}%',
                          style: AppText.display.copyWith(fontSize: 34)),
                      const SizedBox(height: 2),
                      Text(top.label, style: AppText.caption),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                for (var i = 0; i < MockData.distribution.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  BmLegendRow(
                    color: MockData.distribution[i].color,
                    label: MockData.distribution[i].label,
                    value: _minutesLabel(MockData.distribution[i].percent),
                  ),
                ],
              ],
            ),
          ),
        ),

        // 집중 구간
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
          child: BmSoftCard(
            child: Column(
              children: [
                const BmCardCaption(title: '집중 구간', trailing: '가장 길게 34분'),
                const SizedBox(height: 10),
                BmBand(
                  height: 16,
                  segments: const [
                    MapEntry(4, AppColors.primary),
                    MapEntry(2, AppColors.border),
                    MapEntry(8, AppColors.primary),
                    MapEntry(2, AppColors.border),
                    MapEntry(3, AppColors.primary),
                    MapEntry(1, AppColors.border),
                    MapEntry(6, AppColors.primary),
                    MapEntry(2, AppColors.border),
                    MapEntry(5, AppColors.primary),
                  ],
                ),
                const SizedBox(height: 10),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('09시', style: AppText.caption),
                    Text('12시', style: AppText.caption),
                    Text('15시', style: AppText.caption),
                    Text('18시', style: AppText.caption),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 퍼센트를 하루 착석 시간(약 3시간 40분) 기준 분으로 환산해 보여준다.
  static String _minutesLabel(int percent) {
    const totalMinutes = 220;
    final m = (totalMinutes * percent / 100).round();
    if (m >= 60) return '${m ~/ 60}시간 ${m % 60}분';
    return '$m분';
  }
}

// ─────────────────────────────────────────────────────────────
// 주간
// ─────────────────────────────────────────────────────────────
class _WeeklyBody extends StatelessWidget {
  const _WeeklyBody();

  static const _days = ['월', '화', '수', '목', '금', '토', '일'];
  static const _ratios = [0.58, 0.64, 0.81, 0.55, 0.41, 0.70, 0.66];

  @override
  Widget build(BuildContext context) {
    final avg =
        (_ratios.reduce((a, b) => a + b) / _ratios.length * 100).round();

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
                Text('지난주보다 8%p 좋아졌어요',
                    style: AppText.display.copyWith(fontSize: 20)),
                const SizedBox(height: 6),
                const Text(
                  '수요일이 제일 반듯했고, 금요일 오후에 거북목이 몰렸어요.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.55,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),

        // 요일별 막대
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
                      for (var i = 0; i < _days.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text('${(_ratios[i] * 100).round()}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textTertiary,
                                  )),
                              const SizedBox(height: 8),
                              Container(
                                height: _ratios[i] * 100,
                                decoration: BoxDecoration(
                                  color: _ratios[i] >= 0.7
                                      ? AppColors.primary
                                      : AppColors.primaryMid,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(_days[i], style: AppText.caption),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // 주간 지표
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.screen),
          child: Row(
            children: [
              Expanded(child: _MetricTile(value: '24시간', label: '총 착석')),
              SizedBox(width: 10),
              Expanded(child: _MetricTile(value: '37회', label: '나쁜 자세 알림')),
              SizedBox(width: 10),
              Expanded(child: _MetricTile(value: '12회', label: '스트레칭')),
            ],
          ),
        ),
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
