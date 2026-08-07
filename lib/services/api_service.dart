import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/posture.dart';

/// FastAPI 서버와 통신하는 클라이언트
///
/// [변경 요약]
///   - /sensor-data(6채널) → /sensor-frame, /heatmap, /layout (32채널)
///   - 리포트 집계를 앱에서 직접 하지 않고 서버 /report/daily 를 씁니다.
///     (프레임이 하루 수만 건이라 앱으로 다 내려받으면 못 버팁니다)
///   - 자세 등록(캘리브레이션) API 추가
class ApiService {
  ApiService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? AppConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;

  Future<Map<String, dynamic>> _getJson(String path) async {
    final res = await _client
        .get(Uri.parse('$_baseUrl$path'))
        .timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) {
      throw ApiException('서버 응답 오류 (${res.statusCode})');
    }
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  /// 현재 자세 — GET /current-posture
  Future<CurrentPosture> fetchCurrentPosture() async =>
      CurrentPosture.fromJson(await _getJson('/current-posture'));

  /// 실시간 압력 분포 — GET /heatmap
  Future<HeatmapFrame> fetchHeatmap() async =>
      HeatmapFrame.fromJson(await _getJson('/heatmap'));

  /// 센서 물리 배치 — GET /layout (앱 시작 시 1회만 받으면 됩니다)
  Future<SensorLayout> fetchLayout() async =>
      SensorLayout.fromJson(await _getJson('/layout'));

  /// 일간 리포트 — GET /report/daily
  Future<DailyReport> fetchDailyReport({String? date}) async =>
      DailyReport.fromJson(
          await _getJson('/report/daily${date == null ? '' : '?date=$date'}'));

  /// 주간 기록 — GET /report/weekly
  Future<List<Map<String, dynamic>>> fetchWeekly() async {
    final json = await _getJson('/report/weekly');
    return ((json['days'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  /// 자세 등록 현황 — GET /calibration
  Future<CalibrationStatus> fetchCalibration() async => CalibrationStatus
      .fromJson(await _getJson('/calibration?user_id=${AppConfig.userId}'));

  /// 자세 등록 — POST /calibration
  ///
  /// 앱은 센서에 직접 붙지 않으므로, '지금 이 순간의 프레임'을 서버에서
  /// 가져와(=/heatmap) 그걸 기준값으로 등록합니다.
  Future<bool> registerCalibration(String label) async {
    final frame = await fetchHeatmap();
    if (frame.channels.length != AppConfig.channelCount) {
      throw ApiException('센서 데이터가 아직 안 들어옵니다. 브리지가 실행 중인지 확인하세요.');
    }
    final res = await _client
        .post(
          Uri.parse('$_baseUrl/calibration'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'label': label,
            'frame': frame.channels,
            'user_id': AppConfig.userId,
          }),
        )
        .timeout(const Duration(seconds: 5));
    return res.statusCode == 200;
  }

  /// 자세 재보정(전체 초기화) — DELETE /calibration
  Future<bool> resetCalibration() async {
    final res = await _client
        .delete(Uri.parse('$_baseUrl/calibration?user_id=${AppConfig.userId}'))
        .timeout(const Duration(seconds: 5));
    return res.statusCode == 200;
  }

  /// 서버 동작 확인 — GET /
  Future<bool> ping() async {
    try {
      final res = await _client
          .get(Uri.parse('$_baseUrl/'))
          .timeout(const Duration(seconds: 3));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  void dispose() => _client.close();
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}
