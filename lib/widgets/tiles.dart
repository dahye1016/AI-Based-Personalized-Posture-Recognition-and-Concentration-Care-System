import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/mock_data.dart';
import 'common.dart';

/// 획득 배지 카드
class BadgeCard extends StatelessWidget {
  const BadgeCard({super.key, required this.badge});
  final BadgeItem badge;

  @override
  Widget build(BuildContext context) {
    final on = badge.unlocked;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: on ? badge.color.withOpacity(0.12) : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppSpacing.radiusChip),
        border: Border.all(
          color: on ? badge.color.withOpacity(0.3) : AppColors.border,
        ),
      ),
      child: Column(
        children: [
          Icon(
            badge.icon,
            color: on ? badge.color : AppColors.textTertiary,
            size: 26,
          ),
          const SizedBox(height: 8),
          Text(
            badge.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: on ? AppColors.textPrimary : AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 기기 연결 타일 (센서 + 배터리)
class DeviceTile extends StatelessWidget {
  const DeviceTile({
    super.key,
    required this.icon,
    required this.name,
    this.connected = true,
  });

  final IconData icon;
  final String name;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(connected ? '연결됨' : '연결 안 됨',
                    style: AppText.caption),
              ],
            ),
          ),
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: connected ? AppColors.primary : AppColors.textTertiary,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}

/// 알림 설정 토글 행
class SettingToggle extends StatelessWidget {
  const SettingToggle({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
          Switch(
            value: value,
            activeColor: Colors.white,
            activeTrackColor: AppColors.primary,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// 이동형 리스트 항목 (자세 재보정 > / 데이터 내보내기 >)
class ListActionTile extends StatelessWidget {
  const ListActionTile({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      onTap: onTap ?? () {},
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textTertiary),
        ],
      ),
    );
  }
}

/// 초기설정 자세 등록 항목
class RegisterPoseItem extends StatelessWidget {
  const RegisterPoseItem({super.key, required this.pose});
  final RegisterPose pose;

  @override
  Widget build(BuildContext context) {
    final active = pose.state == PoseRegState.active;
    final done = pose.state == PoseRegState.done;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: active ? AppColors.infoBg : AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusChip),
        border: Border.all(
          color: active ? AppColors.infoText.withOpacity(0.4) : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Icon(
            done
                ? Icons.check_circle
                : (active ? Icons.radio_button_checked : Icons.circle_outlined),
            color: done
                ? AppColors.primary
                : (active ? AppColors.infoText : AppColors.textTertiary),
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              pose.label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: active ? AppColors.infoText : AppColors.textPrimary,
              ),
            ),
          ),
          Text(
            done ? '완료' : (active ? '3초' : ''),
            style: TextStyle(
              fontSize: 13,
              color: done ? AppColors.textTertiary : AppColors.infoText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
