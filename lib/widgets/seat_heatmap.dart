import 'package:flutter/material.dart';
import '../models/sensor_layout.dart';

/// 방석 32채널 압력 분포 히트맵.
///
/// 원본(../poselab-review)은 서버 /layout 응답을 생성자로 주입받았지만,
/// 우리는 로컬 상수 [SensorLayout] 을 직접 참조한다. (렌더 로직은 원본 유지)
class SeatHeatmap extends StatelessWidget {
  const SeatHeatmap({
    super.key,
    required this.channels,
    this.maxValue = 1400,
    this.showValues = false,
    this.showIndex = false,
    this.cof,
  });

  final List<int> channels;
  final double maxValue;
  final bool showValues;
  final bool showIndex; // 채널 인덱스 번호 표시 (매트 방향 검증용)
  final Offset? cof; // 무게중심 (0~1 정규화)

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: SensorLayout.widthMm / SensorLayout.heightMm,
      child: LayoutBuilder(
        builder: (context, c) => CustomPaint(
          size: Size(c.maxWidth, c.maxHeight),
          painter: _HeatmapPainter(
            channels: channels,
            maxValue: maxValue,
            showValues: showValues,
            showIndex: showIndex,
            cof: cof,
          ),
        ),
      ),
    );
  }
}

class _HeatmapPainter extends CustomPainter {
  _HeatmapPainter({
    required this.channels,
    required this.maxValue,
    required this.showValues,
    required this.showIndex,
    this.cof,
  });

  final List<int> channels;
  final double maxValue;
  final bool showValues;
  final bool showIndex;
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

    final sx = size.width / SensorLayout.widthMm;
    final sy = size.height / SensorLayout.heightMm;
    // 노드 하나가 차지할 반경 (겹치지 않을 정도)
    final radius = size.shortestSide * 0.075;

    for (var ch = 0; ch < SensorLayout.positions.length; ch++) {
      final v = ch < channels.length ? channels[ch].toDouble() : 0.0;
      final t = v / maxValue;
      final p = SensorLayout.positions[ch];
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

      // 채널 번호 (방향 검증용) — 배경 밝기와 무관하게 읽히도록
      // 검은 테두리 + 흰 글씨 2-pass 렌더.
      if (showIndex) {
        _drawIndex(canvas, center, ch, radius * 0.8);
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

  /// 채널 번호를 검은 테두리 + 흰 글씨로 그린다(어떤 셀 색 위에서도 읽히게).
  void _drawIndex(Canvas canvas, Offset center, int ch, double fontSize) {
    final str = ch.toString();
    TextPainter make(Paint fg) => TextPainter(
          text: TextSpan(
            text: str,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              foreground: fg,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

    final outline = make(Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = fontSize * 0.22
      ..color = Colors.black);
    outline.paint(
        canvas, center - Offset(outline.width / 2, outline.height / 2));

    final fill = make(Paint()..color = Colors.white);
    fill.paint(canvas, center - Offset(fill.width / 2, fill.height / 2));
  }

  @override
  bool shouldRepaint(covariant _HeatmapPainter old) =>
      old.channels != channels ||
      old.cof != cof ||
      old.showIndex != showIndex ||
      old.showValues != showValues;
}
