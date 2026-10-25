import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 스트레칭 동작의 목표 자세를 카메라 화면 위에 흐린 사람 모양으로 그린다.
/// 사용자는 이 가이드에 몸을 겹치듯 따라 하면 된다. 좌표는 화면 비율(0~1).
class StretchGuide extends StatelessWidget {
  const StretchGuide({super.key, required this.move, this.active = false});

  final String move;

  /// 지금 그 자세를 잘 하고 있으면 민트색으로 바뀐다.
  final bool active;

  @override
  Widget build(BuildContext context) {
    final pose = _GuidePose.of(move);
    if (pose == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(
        painter: _GuidePainter(pose, active),
        size: Size.infinite,
      ),
    );
  }
}

class _GuidePose {
  const _GuidePose({
    required this.head,
    this.headTilt = 0,
    this.chinUp = false,
    required this.lSh,
    required this.rSh,
    required this.lEl,
    required this.rEl,
    required this.lWr,
    required this.rWr,
    this.lHip = const Offset(0.42, 0.74),
    this.rHip = const Offset(0.58, 0.74),
    this.arrow,
  });

  final Offset head;
  final double headTilt; // 라디안, + = 시계 방향
  final bool chinUp;
  final Offset lSh, rSh, lEl, rEl, lWr, rWr, lHip, rHip;

  /// 움직일 방향 표시 (시작 → 끝).
  final (Offset, Offset)? arrow;

  // 화면 기준 '왼쪽' = 사용자의 오른쪽 (거울처럼 보이므로 좌우는 상관없음).
  static const _sh = (Offset(0.38, 0.44), Offset(0.62, 0.44));
  static const _armsDown = (
    Offset(0.33, 0.58), Offset(0.67, 0.58), // 팔꿈치
    Offset(0.35, 0.70), Offset(0.65, 0.70), // 손목
  );

  static _GuidePose? of(String move) => switch (move) {
        '팔 양 옆으로 늘리기' => const _GuidePose(
            head: Offset(0.5, 0.30),
            lSh: Offset(0.38, 0.44), rSh: Offset(0.62, 0.44),
            lEl: Offset(0.24, 0.44), rEl: Offset(0.76, 0.44),
            lWr: Offset(0.10, 0.44), rWr: Offset(0.90, 0.44),
          ),
        '팔 위로 뻗기' => const _GuidePose(
            head: Offset(0.5, 0.30),
            lSh: Offset(0.38, 0.44), rSh: Offset(0.62, 0.44),
            lEl: Offset(0.37, 0.27), rEl: Offset(0.63, 0.27),
            lWr: Offset(0.41, 0.10), rWr: Offset(0.59, 0.10),
          ),
        '가슴 열기' => const _GuidePose(
            head: Offset(0.5, 0.30),
            lSh: Offset(0.38, 0.44), rSh: Offset(0.62, 0.44),
            lEl: Offset(0.22, 0.45), rEl: Offset(0.78, 0.45),
            lWr: Offset(0.24, 0.28), rWr: Offset(0.76, 0.28),
          ),
        '목 옆으로 늘이기' => _GuidePose(
            head: const Offset(0.45, 0.31),
            headTilt: -0.35,
            lSh: _sh.$1, rSh: _sh.$2,
            lEl: _armsDown.$1, rEl: _armsDown.$2,
            lWr: _armsDown.$3, rWr: _armsDown.$4,
            arrow: (const Offset(0.56, 0.20), const Offset(0.40, 0.22)),
          ),
        '목 뒤로 젖히기' => _GuidePose(
            head: const Offset(0.5, 0.29),
            chinUp: true,
            lSh: _sh.$1, rSh: _sh.$2,
            lEl: _armsDown.$1, rEl: _armsDown.$2,
            lWr: _armsDown.$3, rWr: _armsDown.$4,
            arrow: (const Offset(0.5, 0.20), const Offset(0.5, 0.11)),
          ),
        '몸통 옆으로 늘이기' => const _GuidePose(
            head: Offset(0.45, 0.29),
            headTilt: -0.25,
            lSh: Offset(0.37, 0.48), rSh: Offset(0.60, 0.40),
            lEl: Offset(0.33, 0.62), rEl: Offset(0.66, 0.24),
            lWr: Offset(0.36, 0.74), rWr: Offset(0.52, 0.12),
            arrow: (Offset(0.72, 0.30), Offset(0.60, 0.14)),
          ),
        '몸통 비틀기' => const _GuidePose(
            head: Offset(0.5, 0.30),
            lSh: Offset(0.44, 0.44), rSh: Offset(0.60, 0.44),
            lEl: Offset(0.38, 0.55), rEl: Offset(0.56, 0.56),
            lWr: Offset(0.50, 0.60), rWr: Offset(0.40, 0.62),
            arrow: (Offset(0.36, 0.38), Offset(0.66, 0.36)),
          ),
        _ => null,
      };
}

class _GuidePainter extends CustomPainter {
  _GuidePainter(this.p, this.active);

  final _GuidePose p;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    Offset at(Offset o) => Offset(o.dx * size.width, o.dy * size.height);
    final base = active ? const Color(0xFF2AC1BC) : Colors.white;
    final limb = Paint()
      ..color = base.withValues(alpha: active ? 0.55 : 0.35)
      ..strokeWidth = size.width * 0.045
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    void line(Offset a, Offset b) => canvas.drawLine(at(a), at(b), limb);

    // 몸통
    final torso = Path()
      ..moveTo(at(p.lSh).dx, at(p.lSh).dy)
      ..lineTo(at(p.rSh).dx, at(p.rSh).dy)
      ..lineTo(at(p.rHip).dx, at(p.rHip).dy)
      ..lineTo(at(p.lHip).dx, at(p.lHip).dy)
      ..close();
    canvas.drawPath(
        torso, Paint()..color = base.withValues(alpha: active ? 0.22 : 0.14));
    line(p.lSh, p.rSh);
    // 목
    final neck = Offset((p.lSh.dx + p.rSh.dx) / 2, (p.lSh.dy + p.rSh.dy) / 2);
    line(neck, Offset(p.head.dx, p.head.dy + 0.05));
    // 팔
    line(p.lSh, p.lEl);
    line(p.lEl, p.lWr);
    line(p.rSh, p.rEl);
    line(p.rEl, p.rWr);

    // 머리
    final r = size.width * 0.075;
    canvas.save();
    canvas.translate(at(p.head).dx, at(p.head).dy);
    canvas.rotate(p.headTilt);
    final face = Paint()..color = base.withValues(alpha: active ? 0.45 : 0.3);
    if (p.chinUp) {
      // 턱을 든 얼굴 — 아래쪽이 앞으로 나온 타원
      canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: r * 2, height: r * 1.7),
          face);
    } else {
      canvas.drawCircle(Offset.zero, r, face);
    }
    canvas.restore();

    // 방향 화살표
    final a = p.arrow;
    if (a != null) {
      final s = at(a.$1), e = at(a.$2);
      final arrowPaint = Paint()
        ..color = (active ? base : const Color(0xFFFFD166)).withValues(alpha: 0.9)
        ..strokeWidth = size.width * 0.012
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawLine(s, e, arrowPaint);
      final ang = math.atan2(e.dy - s.dy, e.dx - s.dx);
      final h = size.width * 0.035;
      for (final d in [2.5, -2.5]) {
        canvas.drawLine(
            e, e + Offset(math.cos(ang + d) * h, math.sin(ang + d) * h),
            arrowPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_GuidePainter old) => old.p != p || old.active != active;
}
