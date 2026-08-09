import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../models/mock_data.dart';
import '../services/sensor_source.dart';
import '../services/posture_classifier.dart';
import '../widgets/common.dart';
import '../widgets/stat_tile.dart';
import 'stretch_screen.dart';

/// 홈 — 실시간 자세.
/// SensorSource(입구) → PostureClassifier(판정) → 화면.
/// 지금은 MockSensorSource(가짜)로 돌아가고, BLE 확정 시 source 만 갈아끼우면 된다.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.source});

  /// 데이터 입구. 안 넘기면 가짜 소스로 자동 동작.
  final SensorSource? source;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final SensorSource _source;
  StreamSubscription<List<int>>? _sub;
  PostureResult _result =
      const PostureResult('연결 중', PostureStatus.good, '센서 데이터를 기다리는 중...');
  String? _lastWarned;

  @override
  void initState() {
    super.initState();
    _source = widget.source ?? MockSensorSource();
    _sub = _source.frames().listen((frame) {
      final r = PostureClassifier.classify(frame);
      if (!mounted) return;
      setState(() => _result = r);
      // 나쁜 자세가 새로 감지된 순간에만 진동 (REQ-F-05)
      if (r.status == PostureStatus.warning) {
        if (_lastWarned != r.posture) {
          _lastWarned = r.posture;
          HapticFeedback.mediumImpact();
        }
      } else {
        _lastWarned = null;
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final warning = _result.status == PostureStatus.warning;
    final cardBg = warning ? AppColors.warnBg : AppColors.goodBg;
    final cardFg = warning ? AppColors.warnText : AppColors.goodText;
    final icon = warning ? Icons.warning_amber_rounded : Icons.check_circle;
    final iconColor = warning ? AppColors.warnIcon : AppColors.postureGood;

    return Scaffold(
      appBar: AppBar(
        title: const Text('홈'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: AppSpacing.screen),
            child: Row(
              children: [
                Icon(Icons.check_box_outlined, size: 18, color: AppColors.primary),
                SizedBox(width: 4),
                Text('2/2',
                    style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.screen, 4, AppSpacing.screen, 28),
        children: [
          // 현재 자세 카드 (실시간 판정 결과)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: cardFg.withOpacity(0.25)),
            ),
            child: Column(
              children: [
                Icon(icon, size: 60, color: iconColor),
                const SizedBox(height: 16),
                Text('현재 자세',
                    style: AppText.body.copyWith(color: cardFg)),
                const SizedBox(height: 10),
                Text(
                  _result.posture,
                  style: TextStyle(
                    fontSize: 46,
                    fontWeight: FontWeight.w800,
                    color: cardFg,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _result.message,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cardFg, fontSize: 14, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          const SectionHeader('오늘'),
          Row(
            children: const [
              Expanded(child: StatTile(value: MockData.sitTime, label: '착석')),
              SizedBox(width: 12),
              Expanded(
                  child: StatTile(value: MockData.goodRatio, label: '바른자세')),
              SizedBox(width: 12),
              Expanded(
                child: StatTile(
                  value: MockData.alertCount,
                  label: '알림',
                  valueColor: AppColors.warnIcon,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const StretchScreen()),
            ),
            child: const InfoBanner(
              title: '스트레칭 시간',
              text: '1시간 경과 · 눌러서 스트레칭 시작',
              bg: AppColors.warnBg,
              fg: AppColors.warnText,
              icon: Icons.self_improvement,
            ),
          ),
        ],
      ),
    );
  }
}
