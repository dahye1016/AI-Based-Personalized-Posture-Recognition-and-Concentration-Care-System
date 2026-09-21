import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// 좌석/등받이 압력 히트맵.
/// 값 리스트(0~1)를 받아 columns 열 그리드로 색 칠한 셀을 보여준다.
class PressureHeatmap extends StatelessWidget {
  const PressureHeatmap({
    super.key,
    required this.title,
    required this.values,
    this.columns = 3,
  });

  final String title;
  final List<double> values;
  final int columns;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppText.caption),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, c) {
              const gap = 6.0;
              final cell = (c.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final v in values)
                    Container(
                      width: cell,
                      height: cell * 0.62,
                      decoration: BoxDecoration(
                        color: AppColors.heat(v),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 초기설정 화면 하단의 가로 압력 바 (한 줄 셀 그라데이션)
class PressureStrip extends StatelessWidget {
  const PressureStrip({super.key, required this.values});
  final List<double> values;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppSpacing.radiusChip),
      ),
      child: Row(
        children: [
          for (int i = 0; i < values.length; i++) ...[
            Expanded(
              child: Container(
                height: 26,
                decoration: BoxDecoration(
                  color: AppColors.heat(values[i]),
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
            if (i != values.length - 1) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}
