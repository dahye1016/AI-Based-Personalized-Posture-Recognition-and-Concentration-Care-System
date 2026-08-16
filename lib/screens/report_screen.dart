import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/mock_data.dart';
import '../widgets/common.dart';
import '../widgets/charts.dart';

/// 리포트 — 자세 분포 / 시간대별 추이
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
      appBar: AppBar(title: const Text('리포트')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.screen, 4, AppSpacing.screen, 28),
        children: [
          _Segmented(
            index: _tab,
            labels: const ['일간', '주간'],
            onChanged: (i) => setState(() => _tab = i),
          ),
          const SizedBox(height: 22),

          const SectionHeader('자세 분포'),
          const AppCard(
            child: DistributionBar(slices: MockData.distribution),
          ),
          const SizedBox(height: 22),

          const SectionHeader('시간대별'),
          const AppCard(
            child: HourlyBarChart(bars: MockData.hourly),
          ),
          const SizedBox(height: 16),

          const InfoBanner(
            title: '오후 3시경 주의',
            text: '다리 꼬기 빈도가 높아요',
            bg: AppColors.infoBg,
            fg: AppColors.infoText,
            icon: Icons.info_outline,
          ),
        ],
      ),
    );
  }
}

/// 일간 / 주간 세그먼트 토글
class _Segmented extends StatelessWidget {
  const _Segmented({
    required this.index,
    required this.labels,
    required this.onChanged,
  });

  final int index;
  final List<String> labels;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (int i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: i == index ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: i == index
                        ? [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            )
                          ]
                        : null,
                  ),
                  child: Text(
                    labels[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: i == index
                          ? AppColors.textPrimary
                          : AppColors.textTertiary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
