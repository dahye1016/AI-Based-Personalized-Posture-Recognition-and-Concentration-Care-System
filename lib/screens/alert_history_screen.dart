import 'package:flutter/material.dart';

import '../models/posture_alert.dart';
import '../services/alert_store.dart';
import '../theme/app_theme.dart';
import '../widgets/bm.dart';
import 'posture_alert_screen.dart';

/// 알림 기록 — 피그마 「14 알림 기록」.
///
/// [AlertStore] 는 최근 [AlertStore.maxRecords]건(=4)만 보관한다.
/// 그래서 이 화면의 요약 숫자도 "최근 4건 기준"이다.
class AlertHistoryScreen extends StatelessWidget {
  const AlertHistoryScreen({super.key});

  static Color colorOf(String posture) => switch (posture) {
        '거북목' => AppColors.postureLean,
        '다리꼬기' => AppColors.postureCross,
        '기대기' => AppColors.postureTilt,
        _ => AppColors.warnIcon,
      };

  @override
  Widget build(BuildContext context) {
    final store = AlertStore.instance;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          final items = store.items;
          return BmScreen(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BmHeader(
                  title: '알림 기록',
                  leading: GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    behavior: HitTestBehavior.opaque,
                    child: const Icon(Icons.arrow_back_rounded,
                        color: AppColors.textPrimary),
                  ),
                ),

                // 요약
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screen, 0, AppSpacing.screen, 18),
                  child: Row(
                    children: [
                      Expanded(
                          child: _Metric(
                              value: '${store.alertCount}회', label: '보관 중')),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _Metric(
                              value: '${store.stretchedCount}회',
                              label: '스트레칭')),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _Metric(
                              value: '${store.ignoredCount}회', label: '넘김')),
                    ],
                  ),
                ),

                // 목록
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.screen),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '최근 ${AlertStore.maxRecords}건',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (items.isEmpty)
                        const _EmptyState()
                      else
                        for (var i = 0; i < items.length; i++) ...[
                          if (i > 0) const SizedBox(height: 12),
                          _AlertRow(alert: items[i]),
                        ],
                    ],
                  ),
                ),

                // 안내
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screen, 16, AppSpacing.screen, 0),
                  child: BmSoftCard(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        const Icon(Icons.lightbulb_outline_rounded,
                            size: 18, color: AppColors.textTertiary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '같은 나쁜 자세가 ${PostureAlertScreen.threshold.inMinutes}분 넘게 이어지면 알려드려요. '
                            '기록은 최근 ${AlertStore.maxRecords}건까지만 보관합니다.',
                            style: const TextStyle(
                              fontSize: 12,
                              height: 1.6,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const Spacer(),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return BmSoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Column(
        children: [
          Text(value, style: AppText.statNumber.copyWith(fontSize: 20)),
          const SizedBox(height: 5),
          Text(label, style: AppText.caption.copyWith(fontSize: 10)),
        ],
      ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.alert});

  final PostureAlert alert;

  @override
  Widget build(BuildContext context) {
    final color = AlertHistoryScreen.colorOf(alert.posture);

    return BmCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              // ignore: deprecated_member_use
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('!',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: color,
                )),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(alert.posture,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        )),
                    if (alert.stretched) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text('✓ 스트레칭 완료',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            )),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(alert.heldLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    )),
              ],
            ),
          ),
          Text(alert.timeLabel,
              style: AppText.caption.copyWith(fontSize: 11)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return BmSoftCard(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: [
          const Icon(Icons.notifications_none_rounded,
              size: 32, color: AppColors.textTertiary),
          const SizedBox(height: 10),
          Text('아직 받은 알림이 없어요',
              style: AppText.caption.copyWith(fontSize: 13)),
          const SizedBox(height: 4),
          Text('바르게 앉고 계신다는 뜻이에요',
              style: AppText.caption.copyWith(fontSize: 11)),
        ],
      ),
    );
  }
}
