import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// 스트레칭 화면의 관절 스켈레톤(막대 사람) 일러스트.
/// 실제 ML Kit 관절 좌표가 붙기 전, 자세 인식 느낌을 주는 정적 표현.
class PoseSkeleton extends StatelessWidget {
  const PoseSkeleton({super.key, this.size = 180});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _SkeletonPainter()),
    );
  }
}

class _SkeletonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final joint = Paint()..color = AppColors.primary;

    final w = size.width, h = size.height;
    final head = Offset(w * 0.5, h * 0.16);
    final neck = Offset(w * 0.5, h * 0.30);
    final hip = Offset(w * 0.5, h * 0.60);
    final lHand = Offset(w * 0.18, h * 0.20);
    final rHand = Offset(w * 0.82, h * 0.20);
    final lFoot = Offset(w * 0.32, h * 0.92);
    final rFoot = Offset(w * 0.68, h * 0.92);

    // 머리
    canvas.drawCircle(head, w * 0.09, p);
    // 몸통
    canvas.drawLine(neck, hip, p);
    // 팔 (양쪽 위로 - 스트레칭 느낌)
    canvas.drawLine(neck, lHand, p);
    canvas.drawLine(neck, rHand, p);
    // 다리
    canvas.drawLine(hip, lFoot, p);
    canvas.drawLine(hip, rFoot, p);

    // 관절 점
    for (final o in [neck, hip, lHand, rHand, lFoot, rFoot]) {
      canvas.drawCircle(o, 5, joint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
