import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/pose_skeleton.dart';

/// 스트레칭 코칭 화면 (별도 흐름 — 다른 화면에서 push 로 진입)
class StretchScreen extends StatefulWidget {
  const StretchScreen({super.key});

  @override
  State<StretchScreen> createState() => _StretchScreenState();
}

class _StretchScreenState extends State<StretchScreen> {
  static const _total = 30; // 동작 30초
  int _elapsed = 18; // 목업과 동일하게 00:18 부터 시작
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed = (_elapsed + 1) % (_total + 1));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _clock {
    final m = (_elapsed ~/ 60).toString().padLeft(2, '0');
    final s = (_elapsed % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('스트레칭'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.screen, 8, AppSpacing.screen, 28),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: const PillBadge('자세 인식 중'),
          ),
          const SizedBox(height: 8),

          // 스켈레톤 + 정확도
          Stack(
            alignment: Alignment.center,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: PoseSkeleton(size: 190),
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.textPrimary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    '정확도 92%',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          const Center(
            child: Text('목 좌우 늘이기',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
          ),
          const SizedBox(height: 4),
          const Center(
            child: Text('거북목 완화 · 2/5 동작', style: AppText.body),
          ),
          const SizedBox(height: 20),

          // 타이머 카드
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Text(
                  _clock,
                  style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: _elapsed / _total,
                    minHeight: 8,
                    backgroundColor: AppColors.surfaceAlt,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          const InfoBanner(
            text: '어깨를 내리고 천천히 기울여주세요',
            bg: AppColors.goodBg,
            fg: AppColors.goodText,
            icon: Icons.tips_and_updates_outlined,
          ),
        ],
      ),
    );
  }
}
