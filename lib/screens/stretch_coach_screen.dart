import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/bm.dart';
import 'stretch_screen.dart';

/// 스트레칭 코칭 — 피그마 「11 스트레칭 코칭」.
///
/// ⚠ 지금은 **카메라와 ML Kit 이 붙지 않은 화면 껍데기**다.
/// 관절 랜드마크는 고정 좌표로 그린 자리표시자이고, 횟수는 타이머로 센다.
///
/// 실제 연동 시 할 일:
///   1. `camera` 패키지로 프리뷰를 [_PosePreview] 자리에 넣는다.
///   2. `google_mlkit_pose_detection` 으로 프레임마다 관절 좌표를 얻어
///      [_landmarks] 를 갱신한다.
///   3. 관절 각도로 동작 완료를 판정해 [_count] 를 올린다.
///   4. 영상은 저장·전송하지 않는다 (온디바이스 처리 원칙).
class StretchCoachScreen extends StatefulWidget {
  const StretchCoachScreen({super.key, required this.routine});

  final StretchRoutine routine;

  @override
  State<StretchCoachScreen> createState() => _StretchCoachScreenState();
}

class _StretchCoachScreenState extends State<StretchCoachScreen> {
  static const _targetCount = 5;

  int _moveIndex = 0;
  int _count = 0;
  bool _holding = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // ML Kit 이 붙기 전까지 진행 상황을 흉내내는 타이머.
    // 실제 연동 시에는 관절 각도 판정으로 대체한다.
    _timer = Timer.periodic(const Duration(milliseconds: 1800), (_) {
      if (!mounted) return;
      setState(() {
        _holding = !_holding;
        if (_holding && _count < _targetCount) _count++;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _next() {
    if (_moveIndex < widget.routine.moves.length - 1) {
      setState(() {
        _moveIndex++;
        _count = 0;
      });
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final moves = widget.routine.moves;
    final isLast = _moveIndex == moves.length - 1;

    return Scaffold(
      backgroundColor: const Color(0xFF212429),
      body: Column(
        children: [
          // ── 카메라 프리뷰 자리 ──────────────────
          Expanded(
            child: Stack(
              children: [
                const Positioned.fill(child: _PosePreview()),

                // 상단 바
                Positioned(
                  left: 20,
                  right: 20,
                  top: MediaQuery.of(context).padding.top + 8,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _GlassButton(
                        icon: Icons.close_rounded,
                        onTap: () => Navigator.of(context).pop(),
                      ),
                      _GlassLabel(
                          text: '동작 ${_moveIndex + 1} / ${moves.length}'),
                    ],
                  ),
                ),

                // 프라이버시 고지
                Positioned(
                  left: 0,
                  right: 0,
                  top: MediaQuery.of(context).padding.top + 56,
                  child: const Center(
                    child: _GlassLabel(text: '영상은 저장·전송되지 않아요'),
                  ),
                ),

                // 판정 배지
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 24,
                  child: Center(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: _holding ? 1 : 0.35,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _holding ? '✓  좋아요, 그대로 3초' : '자세를 잡아주세요',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── 하단 시트 ──────────────────────────
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
              AppSpacing.screen,
              20,
              AppSpacing.screen,
              MediaQuery.of(context).padding.bottom + 16,
            ),
            decoration: const BoxDecoration(
              color: AppColors.bg,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${widget.routine.posture} 루틴',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              )),
                          const SizedBox(height: 4),
                          Text(moves[_moveIndex],
                              style: AppText.display.copyWith(fontSize: 24)),
                        ],
                      ),
                    ),
                    Text('$_count / $_targetCount회',
                        style: AppText.display.copyWith(
                          fontSize: 22,
                          color: AppColors.primary,
                        )),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    for (var i = 0; i < _targetCount; i++) ...[
                      if (i > 0) const SizedBox(width: 6),
                      Expanded(
                        child: Container(
                          height: 8,
                          decoration: BoxDecoration(
                            color: i < _count
                                ? AppColors.primary
                                : AppColors.border,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                BmSoftCard(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Icon(Icons.lightbulb_outline_rounded,
                          size: 18, color: AppColors.textTertiary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _tipFor(moves[_moveIndex]),
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.55,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: BmGhostButton(label: '건너뛰기', onPressed: _next),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 52,
                        child: FilledButton(
                          onPressed: _next,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  AppSpacing.radiusButton),
                            ),
                          ),
                          child: Text(isLast ? '루틴 끝내기' : '다음 동작',
                              style: AppText.button.copyWith(fontSize: 17)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _tipFor(String move) => switch (move) {
        '목 옆으로 늘이기' => '반대쪽 어깨는 아래로 눌러주세요. 통증이 느껴지면 바로 멈추세요.',
        '턱 당기기' => '고개를 뒤로 젖히지 말고, 턱만 수평으로 당깁니다.',
        '어깨 열기' => '가슴을 펴고 날개뼈를 모은다는 느낌으로.',
        '골반 스트레칭' => '허리를 세운 채로 상체만 앞으로 기울입니다.',
        '햄스트링 늘이기' => '무릎을 완전히 펴지 말고 살짝 여유를 두세요.',
        '허리 세우기' => '배에 힘을 주고 허리 곡선을 유지합니다.',
        '코어 활성' => '숨을 참지 말고 천천히 내쉬면서 버팁니다.',
        _ => '천천히, 반동 없이. 통증이 느껴지면 바로 멈추세요.',
      };
}

/// 카메라 프리뷰 자리표시자 — 실루엣 + 관절 랜드마크.
///
/// 실제 연동 시 이 위젯을 `CameraPreview` + 랜드마크 오버레이로 교체한다.
class _PosePreview extends StatelessWidget {
  const _PosePreview();

  /// 프리뷰 기준 좌표(비율 0~1). ML Kit 이 붙으면 실제 관절 좌표로 대체된다.
  static const _landmarks = <Offset>[
    Offset(0.56, 0.30), // 머리
    Offset(0.50, 0.38), // 목
    Offset(0.43, 0.40), // 왼어깨
    Offset(0.61, 0.40), // 오른어깨
    Offset(0.36, 0.50), // 왼팔꿈치
    Offset(0.64, 0.49), // 오른팔꿈치
    Offset(0.35, 0.60), // 왼손목
    Offset(0.62, 0.37), // 오른손 (머리 쪽)
    Offset(0.45, 0.62), // 왼골반
    Offset(0.55, 0.62), // 오른골반
    Offset(0.45, 0.75), // 왼무릎
    Offset(0.55, 0.75), // 오른무릎
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth, h = c.maxHeight;
        return Stack(
          children: [
            // 실루엣
            Positioned(
              left: w * 0.48,
              top: h * 0.25,
              child: _Blob(size: Size(w * 0.14, w * 0.14), round: true),
            ),
            Positioned(
              left: w * 0.40,
              top: h * 0.36,
              child: _Blob(size: Size(w * 0.20, h * 0.20)),
            ),
            Positioned(
              left: w * 0.31,
              top: h * 0.38,
              child: _Blob(size: Size(w * 0.07, h * 0.18)),
            ),
            Positioned(
              left: w * 0.61,
              top: h * 0.36,
              child: _Blob(size: Size(w * 0.07, h * 0.11)),
            ),
            Positioned(
              left: w * 0.42,
              top: h * 0.56,
              child: _Blob(size: Size(w * 0.07, h * 0.20)),
            ),
            Positioned(
              left: w * 0.51,
              top: h * 0.56,
              child: _Blob(size: Size(w * 0.07, h * 0.20)),
            ),

            // 관절 랜드마크
            for (final p in _landmarks)
              Positioned(
                left: w * p.dx - 5,
                top: h * p.dy - 5,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.size, this.round = false});

  final Size size;
  final bool round;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(
        color: const Color(0xFF383D45),
        borderRadius:
            BorderRadius.circular(round ? size.width : size.width * 0.4),
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          // ignore: deprecated_member_use
          color: Colors.white.withOpacity(0.16),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: Colors.white),
      ),
    );
  }
}

class _GlassLabel extends StatelessWidget {
  const _GlassLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      decoration: BoxDecoration(
        // ignore: deprecated_member_use
        color: Colors.white.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          )),
    );
  }
}
