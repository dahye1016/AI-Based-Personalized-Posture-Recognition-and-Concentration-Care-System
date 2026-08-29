import 'package:flutter/material.dart';

import '../models/posture_class.dart';
import '../theme/app_theme.dart';
import '../widgets/bm.dart';
import 'stretch_coach_screen.dart';

/// 스트레칭 추천 — 피그마 「10 스트레칭 추천」.
///
/// 자세 유형별 루틴을 고르면 카메라 코칭 화면([StretchCoachScreen])으로 넘어간다.
/// 어떤 루틴을 위로 올릴지는 나중에 리포트의 "가장 많이 나온 나쁜 자세"로 정한다.
class StretchScreen extends StatelessWidget {
  const StretchScreen({super.key});

  static const routines = <StretchRoutine>[
    StretchRoutine(
      posture: PostureClass.leanForward,
      title: '목·어깨 풀기 루틴',
      moves: ['목 옆으로 늘이기', '턱 당기기', '어깨 열기'],
      duration: '약 2분',
    ),
    StretchRoutine(
      posture: PostureClass.crossLegUnknown,
      covers: {
        PostureClass.crossLegUnknown,
        PostureClass.crossLegRight,
        PostureClass.crossLegLeft,
        PostureClass.leanRight,
        PostureClass.leanLeft,
      },
      title: '골반 정렬 루틴',
      moves: ['골반 스트레칭', '햄스트링 늘이기'],
      duration: '약 1분 30초',
    ),
    StretchRoutine(
      posture: PostureClass.leanBack,
      title: '허리 세우기 루틴',
      moves: ['허리 세우기', '코어 활성'],
      duration: '약 1분',
    ),
  ];

  /// 자세에 맞는 루틴을 찾는다. 대응 루틴이 없으면 null.
  static StretchRoutine? routineFor(PostureClass posture) {
    for (final r in routines) {
      if (r.covers.contains(posture)) return r;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final top = routines.first;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: BmScreen(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BmHeader(
                eyebrow: '오늘 ${top.posture.label}가 40분',
                title: '${top.title.split(' ').first}부터 풀어볼까요'),

            // ── 오늘의 추천 ───────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen, 0, AppSpacing.screen, 18),
              child: BmSoftCard(
                color: AppColors.primarySoft,
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.bg,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.self_improvement_rounded,
                              color: AppColors.primary, size: 26),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(top.title,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  )),
                              const SizedBox(height: 4),
                              Text(
                                '${top.moves.length}동작 · ${top.duration} · 카메라로 동작 확인',
                                style: AppText.caption,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    BmPrimaryButton(
                      label: '바로 시작하기',
                      onPressed: () => _start(context, top),
                    ),
                  ],
                ),
              ),
            ),

            // ── 자세별 루틴 ──────────────────────
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('자세별 루틴',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      )),
                  const SizedBox(height: 12),
                  for (var i = 0; i < routines.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    _RoutineCard(
                      routine: routines[i],
                      badge: i == 0 ? '오늘 2회' : null,
                      onTap: () => _start(context, routines[i]),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _start(BuildContext context, StretchRoutine r) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => StretchCoachScreen(routine: r)),
    );
  }
}

/// 스트레칭 루틴 한 건.
class StretchRoutine {
  const StretchRoutine({
    required this.posture,
    required this.title,
    required this.moves,
    required this.duration,
    Set<PostureClass>? covers,
  }) : _covers = covers;

  /// 이 루틴을 대표하는 자세 (카드 제목·색의 출처)
  final PostureClass posture;
  final String title;
  final List<String> moves;
  final String duration;

  final Set<PostureClass>? _covers;

  /// 이 루틴이 커버하는 자세들. 지정하지 않으면 [posture] 하나만.
  Set<PostureClass> get covers => _covers ?? {posture};

  Color get color => posture.color;
}

class _RoutineCard extends StatelessWidget {
  const _RoutineCard({required this.routine, this.badge, this.onTap});

  final StretchRoutine routine;
  final String? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: BmCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                // ignore: deprecated_member_use
                color: routine.color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Text(
                routine.posture.label.substring(0, 1),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: routine.color,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(routine.posture.label,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          )),
                      if (badge != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.primarySoft,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text('✓ $badge',
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              )),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(routine.moves.join(' · '),
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: AppColors.textSecondary,
                      )),
                  const SizedBox(height: 3),
                  Text('${routine.moves.length}동작 · ${routine.duration}',
                      style: AppText.caption.copyWith(fontSize: 10)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}
