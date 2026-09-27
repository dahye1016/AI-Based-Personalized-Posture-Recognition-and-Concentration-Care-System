import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 배민 스타일 공용 위젯 모음.
///
/// 피그마 「한이음 자세케어 앱」의 반복 요소를 한 파일에 모았다.
/// 화면 파일들은 여기 있는 것만 조립해서 쓴다.

/// 화면 본문 껍데기.
///
/// SafeArea + "내용이 화면보다 짧으면 Spacer 가 남는 공간을 먹고,
/// 길면 스크롤" 동작. 작은 기기에서 RenderFlex 오버플로가 나지 않는다.
class BmScreen extends StatelessWidget {
  const BmScreen({super.key, required this.child, this.bottom = true});

  final Widget child;

  /// 하단 SafeArea 적용 여부. 탭바가 따로 있으면 false.
  final bool bottom;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: bottom,
      child: LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight),
            child: IntrinsicHeight(child: child),
          ),
        ),
      ),
    );
  }
}

/// 화면 헤더 — 작은 라벨 + 큰 제목(한나체) + 우측 위젯.
class BmHeader extends StatelessWidget {
  const BmHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.trailing,
    this.leading,
  });

  final String title;
  final String? eyebrow;
  final Widget? trailing;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.screen, 12, AppSpacing.screen, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null) ...[
                  Text(eyebrow!,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textTertiary,
                      )),
                  const SizedBox(height: 2),
                ],
                Text(title, style: AppText.screenTitle),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// 민트 알약 뱃지. (LIVE, STEP 1/3, 유지율 84% 등)
class BmPill extends StatelessWidget {
  const BmPill({
    super.key,
    required this.label,
    this.color = AppColors.primary,
    this.bg = AppColors.primarySoft,
    this.dot = false,
  });

  final String label;
  final Color color;
  final Color bg;

  /// 앞에 작은 원을 붙일지 (LIVE 표시용)
  final bool dot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(dot ? 10 : 12, 6, 12, 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Text(label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              )),
        ],
      ),
    );
  }
}

/// 흰 배경 + 얇은 테두리 카드.
class BmCard extends StatelessWidget {
  const BmCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color = AppColors.bg,
    this.bordered = true,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color color;
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
        border: bordered ? Border.all(color: AppColors.border) : null,
      ),
      child: child,
    );
  }
}

/// 회색 표면 카드 (테두리 없음).
class BmSoftCard extends StatelessWidget {
  const BmSoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color = AppColors.surface,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color color;

  @override
  Widget build(BuildContext context) => BmCard(
        padding: padding,
        color: color,
        bordered: false,
        child: child,
      );
}

/// 카드 안쪽 상단 캡션 줄 — 좌측 제목 / 우측 보조문구.
class BmCardCaption extends StatelessWidget {
  const BmCardCaption({super.key, required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            )),
        if (trailing != null)
          Flexible(
            child: Text(trailing!,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textTertiary,
                )),
          ),
      ],
    );
  }
}

/// 민트 채움 기본 버튼 (높이 56 / 라운드 14).
class BmPrimaryButton extends StatelessWidget {
  const BmPrimaryButton({super.key, required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppSpacing.buttonHeight,
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          disabledBackgroundColor: AppColors.primaryMid,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
          ),
        ),
        child: Text(label, style: AppText.button),
      ),
    );
  }
}

/// 흰 배경 + 테두리 보조 버튼.
class BmGhostButton extends StatelessWidget {
  const BmGhostButton({super.key, required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: AppColors.bg,
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
          ),
        ),
        child: Text(label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textTertiary,
            )),
      ),
    );
  }
}

/// 두 칸짜리 세그먼트 컨트롤 (일간 / 주간).
class BmSegmented extends StatelessWidget {
  const BmSegmented({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusChip),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: i == index ? AppColors.bg : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    labels[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          i == index ? FontWeight.w700 : FontWeight.w500,
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

/// 선택 가능한 알약 칩.
class BmChip extends StatelessWidget {
  const BmChip({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusChip),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? Colors.white : AppColors.textTertiary,
          ),
        ),
      ),
    );
  }
}

/// 통계 두 칸 (바른 자세 62% / 오늘 착석 3시간 40분).
class BmStatTile extends StatelessWidget {
  const BmStatTile({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return BmSoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.caption),
          const SizedBox(height: 4),
          Text(value, style: AppText.statNumber),
        ],
      ),
    );
  }
}

/// 링 게이지 (카운트다운 / 챌린지 진행).
class BmRing extends StatelessWidget {
  const BmRing({
    super.key,
    required this.ratio,
    required this.child,
    this.size = 200,
    this.stroke = 14,
    this.color = AppColors.primary,
    this.trackColor = AppColors.primarySoft,
  });

  /// 0.0 ~ 1.0
  final double ratio;
  final Widget child;
  final double size;
  final double stroke;
  final Color color;
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(ratio, stroke, color, trackColor),
        child: Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.ratio, this.stroke, this.color, this.trackColor);

  final double ratio;
  final double stroke;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);

    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = trackColor,
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * ratio.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.ratio != ratio || old.color != color;
}

/// 도넛 차트 한 조각.
class BmDonutSlice {
  const BmDonutSlice(this.label, this.value, this.color);

  final String label;

  /// 비율의 분자. 합이 얼마든 내부에서 정규화한다.
  final double value;
  final Color color;
}

/// 자세 분포 도넛.
class BmDonut extends StatelessWidget {
  const BmDonut({
    super.key,
    required this.slices,
    required this.center,
    this.size = 160,
    this.thickness = 0.34,
  });

  final List<BmDonutSlice> slices;
  final Widget center;
  final double size;

  /// 링 두께 비율 (0~1). 0.34 면 안쪽 구멍이 66%.
  final double thickness;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _DonutPainter(slices, thickness),
        child: Center(child: center),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter(this.slices, this.thickness);

  final List<BmDonutSlice> slices;
  final double thickness;

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<double>(0, (a, s) => a + s.value);
    if (total <= 0) return;

    final stroke = size.width * thickness / 2;
    final rect = Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);

    var start = -math.pi / 2;
    for (final s in slices) {
      final sweep = math.pi * 2 * (s.value / total);
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = s.color,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => true;
}

/// 색 구간이 이어진 가로 띠 (최근 30분 타임라인 / 집중 구간).
class BmBand extends StatelessWidget {
  const BmBand({
    super.key,
    required this.segments,
    this.height = 14,
    this.gap = 2,
  });

  /// (가중치, 색) 목록
  final List<MapEntry<int, Color>> segments;
  final double height;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < segments.length; i++) ...[
          if (i > 0) SizedBox(width: gap),
          Expanded(
            flex: segments[i].key,
            child: Container(
              height: height,
              decoration: BoxDecoration(
                color: segments[i].value,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 범례 한 줄 — 색 점 + 라벨 + 우측 값.
class BmLegendRow extends StatelessWidget {
  const BmLegendRow({
    super.key,
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              )),
        ),
        Text(value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textTertiary,
            )),
      ],
    );
  }
}

/// 온오프 토글 한 줄 (설정 화면).
class BmSwitchRow extends StatelessWidget {
  const BmSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.description,
  });

  final String title;
  final String? description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    )),
                if (description != null) ...[
                  const SizedBox(height: 3),
                  Text(description!,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.5,
                        color: AppColors.textTertiary,
                      )),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.white,
            activeTrackColor: AppColors.primary,
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: AppColors.border,
            // 이 저장소의 다른 파일(app_theme.dart)과 맞춰 구버전 API를 쓴다.
            trackOutlineColor: MaterialStateProperty.all(Colors.transparent),
          ),
        ],
      ),
    );
  }
}

/// 카드 안 구분선.
class BmDivider extends StatelessWidget {
  const BmDivider({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 1,
        width: double.infinity,
        child: ColoredBox(color: AppColors.border),
      );
}
