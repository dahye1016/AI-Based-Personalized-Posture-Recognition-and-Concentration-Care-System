/// 앱 전역 설정
class AppConfig {
  /// FastAPI 서버 주소.
  /// - Android 에뮬레이터: http://10.0.2.2:8000  (PC localhost 매핑)
  /// - iOS 시뮬레이터 / 웹:  http://127.0.0.1:8000
  /// - 실기기:               http://<PC의 LAN IP>:8000
  /// 실기기는 PC LAN IP. 네트워크가 바뀌면 이 값도 바꿔야 함.
  static const String baseUrl = 'http://192.168.11.29:8000';

  /// 현재 자세 폴링 주기 (서버 simulator가 0.5초마다 전송하므로 1초면 충분)
  static const Duration pollInterval = Duration(seconds: 1);
}
