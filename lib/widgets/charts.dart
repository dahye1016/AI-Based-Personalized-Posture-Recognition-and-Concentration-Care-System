import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/mock_data.dart';

/// 자세 분포: 가로 누적 바 + 범례
class DistributionBar extends StatelessWidget {
  const DistributionBar({super.key, required this.slices});
  final List<PostureSlice> slices;

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<int>(0, (a, b) => a + b.percent);
    final rest = (100 - total).clamp(0, 100);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Row(
            children: [
              for (final s in slices)
                Expanded(
                  flex: s.percent,
                  child: Container(height: 12, color: s.color),
                ),
              if (rest > 0)
                Expanded(
                  flex: rest,
                  child: Container(height: 12, color: AppColors.surfaceAlt),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ...slices.map(
          (s) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: s.color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(s.label, style: AppText.body)),
                Text(
                  '${s.percent}%',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 시간대별 막대 차트 (9시 ~ 18시 예시)
class HourlyBarChart extends StatelessWidget {
  const HourlyBarChart({super.key, required this.bars});
  final List<MapEntry<double, Color>> bars;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 120,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final b in bars)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Container(
                      height: 20 + b.key * 100,
                      decoration: BoxDecoration(
                        color: b.value,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Text('9시', style: AppText.caption),
            Text('13시', style: AppText.caption),
            Text('18시', style: AppText.caption),
          ],
        ),
      ],
    );
  }
}

/// 도넛 진행률 (챌린지 70%)
class DonutProgress extends StatelessWidget {
  const DonutProgress({
    super.key,
    required this.done,
    required this.goal,
    this.size = 170,
  });

  final int done;
  final int goal;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ratio = goal == 0 ? 0.0 : (done / goal).clamp(0.0, 1.0);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _DonutPainter(ratio),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${(ratio * 100).round()}%',
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              Text('$done/$goal 분', style: AppText.caption),
            ],
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.ratio);
  final double ratio;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 16.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - stroke) / 2;
    final bg = Paint()
      ..color = AppColors.surfaceAlt
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    final fg = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;

    canvas.drawCircle(center, radius, bg);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * ratio,
      false,
      fg,
    );
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.ratio != ratio;
}

/// 주간 기록 스트립 (월~일 색칠 셀)
class WeekStrip extends StatelessWidget {
  const WeekStrip({super.key, required this.values});
  final List<double> values; // 0~1, 길이 7

  static const _days = ['월', '화', '수', '목', '금', '토', '일'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < values.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        color: values[i] <= 0
                            ? AppColors.surfaceAlt
                            : AppColors.primary
                                .withOpacity(0.25 + values[i] * 0.75),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(_days[i], style: AppText.caption),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
