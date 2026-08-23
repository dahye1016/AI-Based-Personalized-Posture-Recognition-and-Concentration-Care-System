import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/bm.dart';

/// 알림 설정 — 피그마 「12 알림 설정」.
///
/// 지금은 화면 상태만 갖는다(앱 재시작하면 초기화).
/// 저장이 필요해지면 `shared_preferences` 로 값을 얹으면 된다.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _alert = true;

  /// 나쁜 자세가 몇 분 이어지면 알릴지.
  ///
  /// 기획 확정값은 5분(PostureAlertScreen.threshold)이고,
  /// 제작설계서 REQ-F-05 는 20초로 되어 있어 값이 다르다 — 팀 확정 필요.
  double _holdMin = 5;

  /// 같은 알림을 다시 보내는 간격 (분)
  double _repeatMin = 5;

  final _postures = <String, bool>{
    '거북목': true,
    '다리꼬기': true,
    '기대기': true,
    '한쪽 쏠림': false,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: BmScreen(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BmHeader(
              title: '알림 설정',
              leading: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                behavior: HitTestBehavior.opaque,
                child: const Icon(Icons.arrow_back_rounded,
                    color: AppColors.textPrimary),
              ),
            ),

            // ── 알림 기본 ────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen, 0, AppSpacing.screen, 16),
              child: BmCard(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    BmSwitchRow(
                      title: '나쁜 자세 알림',
                      description: '진동과 푸시로 알려드려요',
                      value: _alert,
                      onChanged: (v) => setState(() => _alert = v),
                    ),
                  ],
                ),
              ),
            ),

            // ── 임계값 ───────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen, 0, AppSpacing.screen, 16),
              child: BmSoftCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    _SliderRow(
                      label: '얼마나 버티면 알릴까요',
                      value: '${_holdMin.round()}분',
                      slider: Slider(
                        value: _holdMin,
                        min: 1,
                        max: 20,
                        divisions: 19,
                        activeColor: AppColors.primary,
                        inactiveColor: AppColors.border,
                        onChanged: (v) => setState(() => _holdMin = v),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _SliderRow(
                      label: '같은 알림 다시 보내기',
                      value: '${_repeatMin.round()}분마다',
                      slider: Slider(
                        value: _repeatMin,
                        min: 1,
                        max: 30,
                        divisions: 29,
                        activeColor: AppColors.primary,
                        inactiveColor: AppColors.border,
                        onChanged: (v) => setState(() => _repeatMin = v),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── 자세별 알림 ──────────────────────
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('어떤 자세를 알릴까요',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      )),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final e in _postures.entries)
                        GestureDetector(
                          onTap: () =>
                              setState(() => _postures[e.key] = !e.value),
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: e.value
                                  ? AppColors.primarySoft
                                  : AppColors.surface,
                              borderRadius: BorderRadius.circular(999),
                              border: e.value
                                  ? Border.all(color: AppColors.primary)
                                  : null,
                            ),
                            child: Text(
                              e.value ? '✓ ${e.key}' : e.key,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: e.value
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: e.value
                                    ? AppColors.primary
                                    : AppColors.textTertiary,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            const Spacer(),
            const Padding(
              padding: EdgeInsets.fromLTRB(
                  AppSpacing.screen, 24, AppSpacing.screen, 12),
              child: Text(
                '설정은 아직 앱을 껐다 켜면 초기화됩니다.\n저장 기능은 다음 작업에서 붙일 예정이에요.',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.6,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.slider,
  });

  final String label;
  final String value;
  final Widget slider;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                )),
            Text(value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                )),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 6,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
          ),
          child: slider,
        ),
      ],
    );
  }
}
