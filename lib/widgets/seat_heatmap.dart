import 'package:flutter/material.dart';
import '../models/posture.dart';

/// 방석 32채널 압력 분포 히트맵.
///
/// 서버 /layout 으로 받은 실제 센서 좌표에 값을 찍습니다.
/// (레이아웃을 하드코딩하지 않았기 때문에, 나중에 등받이 센서처럼
///  배치가 다른 패널이 붙어도 이 위젯을 그대로 씁니다.)
class SeatHeatmap extends StatelessWidget {
  const SeatHeatmap({
    super.key,
    required this.layout,
    required this.channels,
    this.maxValue = 1400,
    this.showValues = false,
    this.cof,
  });

  final SensorLayout layout;
  final List<int> channels;
  final double maxValue;
  final bool showValues;
  final Offset? cof; // 무게중심 (0~1 정규화)

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: layout.widthMm / layout.heightMm,
      child: LayoutBuilder(
        builder: (context, c) => CustomPaint(
          size: Size(c.maxWidth, c.maxHeight),
          painter: _HeatmapPainter(
            layout: layout,
            channels: channels,
            maxValue: maxValue,
            showValues: showValues,
            cof: cof,
          ),
        ),
      ),
    );
  }
}

class _HeatmapPainter extends CustomPainter {
  _HeatmapPainter({
    required this.layout,
    required this.channels,
    required this.maxValue,
    required this.showValues,
    this.cof,
  });

  final SensorLayout layout;
  final List<int> channels;
  final double maxValue;
  final bool showValues;
  final Offset? cof;

  /// 압력 -> 색 (낮음: 어두운 회색 → 높음: 초록 → 노랑 → 빨강)
  Color _color(double t) {
    t = t.clamp(0.0, 1.0);
    if (t < 0.02) return const Color(0xFF2A2E33);
    if (t < 0.45) {
      return Color.lerp(const Color(0xFF1E4D3A), const Color(0xFF2E9E6B),
          t / 0.45)!;
    }
    if (t < 0.75) {
      return Color.lerp(const Color(0xFF2E9E6B), const Color(0xFFE5B800),
          (t - 0.45) / 0.30)!;
    }
    return Color.lerp(
        const Color(0xFFE5B800), const Color(0xFFD64545), (t - 0.75) / 0.25)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFF16191D);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14)),
      bg,
    );

    final sx = size.width / layout.widthMm;
    final sy = size.height / layout.heightMm;
    // 노드 하나가 차지할 반경 (겹치지 않을 정도)
    final radius = size.shortestSide * 0.075;

    for (var ch = 0; ch < layout.positions.length; ch++) {
      final v = ch < channels.length ? channels[ch].toDouble() : 0.0;
      final t = v / maxValue;
      final p = layout.positions[ch];
      final center = Offset(p.dx * sx, p.dy * sy);

      // 부드럽게 번지는 효과
      canvas.drawCircle(
        center,
        radius * 1.6,
        Paint()
          ..color = _color(t).withOpacity(0.25 * t.clamp(0.0, 1.0))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawCircle(center, radius, Paint()..color = _color(t));

      if (showValues) {
        final tp = TextPainter(
          text: TextSpan(
            text: v.round().toString(),
            style: TextStyle(
              fontSize: radius * 0.8,
              color: t > 0.5 ? Colors.black87 : Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
      }
    }

    // 무게중심 표시
    if (cof != null) {
      final c = Offset(cof!.dx * size.width, cof!.dy * size.height);
      canvas.drawCircle(
          c, radius * 0.55, Paint()..color = Colors.white.withOpacity(0.9));
      canvas.drawCircle(
        c,
        radius * 0.9,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white70,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HeatmapPainter old) =>
      old.channels != channels || old.cof != cof;
}
