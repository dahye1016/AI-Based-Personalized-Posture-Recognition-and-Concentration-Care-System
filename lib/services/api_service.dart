import 'package:http/http.dart' as http;
import '../config.dart';

/// FastAPI 서버와 통신하는 클라이언트
class ApiService {
  ApiService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? AppConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;

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
