import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/posture.dart';

/// FastAPI 서버와 통신하는 클라이언트
class ApiService {
  ApiService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? AppConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;

  /// 현재(최신) 자세 1건 조회 — GET /current-posture
  Future<CurrentPosture> fetchCurrentPosture() async {
    final res = await _client
        .get(Uri.parse('$_baseUrl/current-posture'))
        .timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) {
      throw ApiException('서버 응답 오류 (${res.statusCode})');
    }
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return CurrentPosture.fromJson(json);
  }

  /// 최근 자세 이력 조회 (최대 100건, 시간 역순) — GET /sensor-data
  Future<List<SensorRecord>> fetchHistory() async {
    final res = await _client
        .get(Uri.parse('$_baseUrl/sensor-data'))
        .timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) {
      throw ApiException('서버 응답 오류 (${res.statusCode})');
    }
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return list
        .map((e) => SensorRecord.fromJson(e as Map<String, dynamic>))
        .toList();
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
