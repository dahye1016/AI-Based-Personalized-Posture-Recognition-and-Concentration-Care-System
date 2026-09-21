import 'package:flutter/material.dart';

/// 자세별 상태 색상/아이콘 정의
class PostureStyle {
  final Color color;
  final IconData icon;
  const PostureStyle(this.color, this.icon);

  static const _map = {
    '바른자세': PostureStyle(Color(0xFF2E7D32), Icons.check_circle),
    '거북목': PostureStyle(Color(0xFFE65100), Icons.warning_amber_rounded),
    '기대기': PostureStyle(Color(0xFFAD1457), Icons.airline_seat_recline_extra),
    '다리꼬기': PostureStyle(Color(0xFF6A1B9A), Icons.swap_horiz),
  };

  static PostureStyle of(String posture) =>
      _map[posture] ?? const PostureStyle(Color(0xFF607D8B), Icons.help_outline);
}

/// /current-posture 응답 모델
class CurrentPosture {
  final String posture;
  final String status; // good | warning | unknown
  final String message;
  final String? action; // 예: "진동 알림"
  final DateTime? timestamp;

  CurrentPosture({
    required this.posture,
    required this.status,
    required this.message,
    this.action,
    this.timestamp,
  });

  bool get isBad => status == 'warning';

  factory CurrentPosture.fromJson(Map<String, dynamic> json) {
    final fb = json['feedback'];
    return CurrentPosture(
      posture: (json['posture'] ?? '데이터 없음').toString(),
      status: (fb is Map ? fb['status'] : null)?.toString() ?? 'unknown',
      message: (fb is Map ? fb['message'] : null)?.toString() ??
          '센서 데이터를 기다리는 중...',
      action: (fb is Map ? fb['action'] : null)?.toString(),
      timestamp: _parseTime(json['timestamp']),
    );
  }

  static DateTime? _parseTime(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }
}
