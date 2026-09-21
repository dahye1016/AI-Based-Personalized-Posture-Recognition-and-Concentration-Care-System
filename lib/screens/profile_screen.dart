import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/mock_data.dart';
import '../widgets/common.dart';
import '../widgets/tiles.dart';
import 'calibration_screen.dart';

/// 내 정보 — 프로필 / 기기 연결 / 알림 설정
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _postureAlert = true;
  bool _stretchAlert = true;
  bool _vibration = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('내 정보')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.screen, 4, AppSpacing.screen, 28),
        children: [
          // 프로필
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  MockData.userName.substring(1), // 예: 예원
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Text(MockData.userName,
                  style: AppText.cardTitle.copyWith(fontSize: 18)),
            ],
          ),
          const SizedBox(height: 24),

          const SectionHeader('기기 연결'),
          const DeviceTile(
            icon: Icons.chair_alt,
            name: '좌석 센서',
          ),
          const SizedBox(height: 10),
          const DeviceTile(
            icon: Icons.event_seat,
            name: '등받이 센서',
          ),
          const SizedBox(height: 24),

          const SectionHeader('알림 설정'),
          AppCard(
            child: Column(
              children: [
                SettingToggle(
                  label: '자세 알림',
                  value: _postureAlert,
                  onChanged: (v) => setState(() => _postureAlert = v),
                ),
                SettingToggle(
                  label: '스트레칭 알림',
                  value: _stretchAlert,
                  onChanged: (v) => setState(() => _stretchAlert = v),
                ),
                SettingToggle(
                  label: '진동',
                  value: _vibration,
                  onChanged: (v) => setState(() => _vibration = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          ListActionTile(
            icon: Icons.tune,
            label: '바른 자세 측정 (재보정)',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CalibrationScreen()),
            ),
          ),
          const SizedBox(height: 10),
          const ListActionTile(
              icon: Icons.file_download_outlined, label: '데이터 내보내기'),
        ],
      ),
    );
  }
}
