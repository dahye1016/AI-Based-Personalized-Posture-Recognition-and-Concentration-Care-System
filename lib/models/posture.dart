import 'package:flutter/material.dart';

/// 자세별 상태 색상/아이콘 정의
///
/// [변경] 기존 4종(바른자세/거북목/기대기/다리꼬기) → 서버가 실제로
/// 판정하는 7종 + 비착석으로 맞췄습니다.
/// 이름이 서버(posture_classifier.POSTURES)와 한 글자라도 다르면
/// 스타일이 회색 기본값으로 떨어지니 주의하세요.
class PostureStyle {
  final Color color;
  final IconData icon;
  const PostureStyle(this.color, this.icon);

  static const _map = {
    '정자세': PostureStyle(Color(0xFF2E9E6B), Icons.check_circle),
    '앞으로 숙이기': PostureStyle(Color(0xFFE58A00), Icons.trending_down),
    '뒤로 기대기': PostureStyle(Color(0xFFAD1457), Icons.airline_seat_recline_extra),
    '오른다리 꼬기': PostureStyle(Color(0xFF6A1B9A), Icons.swap_horiz),
    '왼다리 꼬기': PostureStyle(Color(0xFF4527A0), Icons.swap_horiz),
    '좌측 기대기': PostureStyle(Color(0xFF00838F), Icons.arrow_back),
    '우측 기대기': PostureStyle(Color(0xFF00838F), Icons.arrow_forward),
    '비착석': PostureStyle(Color(0xFF607D8B), Icons.event_seat_outlined),
  };

  static PostureStyle of(String posture) =>
      _map[posture] ?? const PostureStyle(Color(0xFF607D8B), Icons.help_outline);
}

/// GET /current-posture 응답
class CurrentPosture {
  final String posture;
  final String status; // good | warning | idle | unknown
  final String message;
  final String? action;
  final double confidence;
  final int heldSeconds; // 같은 자세를 유지한 시간
  final bool seated;
  final double cofX;
  final double cofY;
  final DateTime? timestamp;

  CurrentPosture({
    required this.posture,
    required this.status,
    required this.message,
    required this.confidence,
    required this.heldSeconds,
    required this.seated,
    required this.cofX,
    required this.cofY,
    this.action,
    this.timestamp,
  });

  bool get isBad => status == 'warning';

  /// "24분 유지 중" 처럼 표시할 문자열
  String get heldLabel {
    if (heldSeconds < 60) return '$heldSeconds초 유지 중';
    final m = heldSeconds ~/ 60;
    if (m < 60) return '$m분 유지 중';
    return '${m ~/ 60}시간 ${m % 60}분 유지 중';
  }

  factory CurrentPosture.fromJson(Map<String, dynamic> json) {
    final fb = json['feedback'];
    final cof = json['cof'];
    return CurrentPosture(
      posture: (json['posture'] ?? '데이터 없음').toString(),
      status: (fb is Map ? fb['status'] : null)?.toString() ?? 'unknown',
      message: (fb is Map ? fb['message'] : null)?.toString() ??
          '센서 데이터를 기다리는 중...',
      action: (fb is Map ? fb['action'] : null)?.toString(),
      confidence: _d(json['confidence']),
      heldSeconds: (json['held_seconds'] as num?)?.toInt() ?? 0,
      seated: json['seated'] == true,
      cofX: cof is Map ? _d(cof['x'], fallback: 0.5) : 0.5,
      cofY: cof is Map ? _d(cof['y'], fallback: 0.5) : 0.5,
      timestamp: json['timestamp'] == null
          ? null
          : DateTime.tryParse(json['timestamp'].toString()),
    );
  }
}

/// GET /heatmap 응답 — 방석 32칸 압력 격자
class HeatmapFrame {
  final List<int> channels;
  final double max;
  final String posture;
  final DateTime? timestamp;

  HeatmapFrame({
    required this.channels,
    required this.max,
    required this.posture,
    this.timestamp,
  });

  factory HeatmapFrame.fromJson(Map<String, dynamic> json) => HeatmapFrame(
        channels: ((json['channels'] as List?) ?? [])
            .map((e) => (e as num).toInt())
            .toList(),
        max: _d(json['max']),
        posture: (json['posture'] ?? '').toString(),
        timestamp: json['timestamp'] == null
            ? null
            : DateTime.tryParse(json['timestamp'].toString()),
      );
}

/// GET /layout 응답 — 각 채널이 방석 어디에 있는지
class SensorLayout {
  final int nChannels;
  final double widthMm;
  final double heightMm;
  final List<Offset> positions; // 채널 순서대로 (mm)

  SensorLayout({
    required this.nChannels,
    required this.widthMm,
    required this.heightMm,
    required this.positions,
  });

  factory SensorLayout.fromJson(Map<String, dynamic> json) {
    final raw = (json['positions'] as List?) ?? [];
    final pos = List<Offset>.filled(raw.length, Offset.zero);
    for (final p in raw) {
      final m = p as Map<String, dynamic>;
      pos[(m['ch'] as num).toInt()] = Offset(_d(m['x']), _d(m['y']));
    }
    return SensorLayout(
      nChannels: (json['n_channels'] as num?)?.toInt() ?? pos.length,
      widthMm: _d(json['width_mm'], fallback: 386),
      heightMm: _d(json['height_mm'], fallback: 382),
      positions: pos,
    );
  }
}

/// GET /report/daily 응답
class DailyReport {
  final String date;
  final int seatedSeconds;
  final double goodRatio;
  final Map<String, double> distribution; // 자세 -> %
  final List<HourlyStat> hourly;

  DailyReport({
    required this.date,
    required this.seatedSeconds,
    required this.goodRatio,
    required this.distribution,
    required this.hourly,
  });

  String get seatedLabel {
    final m = seatedSeconds ~/ 60;
    return '${m ~/ 60}h ${m % 60}m';
  }

  factory DailyReport.fromJson(Map<String, dynamic> json) => DailyReport(
        date: (json['date'] ?? '').toString(),
        seatedSeconds: (json['seated_seconds'] as num?)?.toInt() ?? 0,
        goodRatio: _d(json['good_ratio']),
        distribution: ((json['distribution'] as Map?) ?? {})
            .map((k, v) => MapEntry(k.toString(), _d(v))),
        hourly: ((json['hourly'] as List?) ?? [])
            .map((e) => HourlyStat.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class HourlyStat {
  final int hour;
  final String dominant;
  final double goodRatio;

  HourlyStat({
    required this.hour,
    required this.dominant,
    required this.goodRatio,
  });

  factory HourlyStat.fromJson(Map<String, dynamic> json) => HourlyStat(
        hour: (json['hour'] as num?)?.toInt() ?? 0,
        dominant: (json['dominant'] ?? '').toString(),
        goodRatio: _d(json['good_ratio']),
      );
}

/// GET /calibration 응답
class CalibrationStatus {
  final List<String> registered;
  final List<String> missing;
  final bool complete;

  CalibrationStatus({
    required this.registered,
    required this.missing,
    required this.complete,
  });

  factory CalibrationStatus.fromJson(Map<String, dynamic> json) =>
      CalibrationStatus(
        registered: ((json['registered'] as List?) ?? [])
            .map((e) => e.toString())
            .toList(),
        missing:
            ((json['missing'] as List?) ?? []).map((e) => e.toString()).toList(),
        complete: json['complete'] == true,
      );
}

double _d(dynamic v, {double fallback = 0}) =>
    v == null ? fallback : (double.tryParse(v.toString()) ?? fallback);
