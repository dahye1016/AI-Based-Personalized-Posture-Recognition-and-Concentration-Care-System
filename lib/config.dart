/// 앱 전역 설정
class AppConfig {
  /// FastAPI 서버 주소.
  ///
  /// ⚠️ 중요 — 구조가 바뀌었습니다.
  /// PoseLab Seat 방석센서는 USB 로 'PC' 에 연결됩니다. 폰에 직접 안 붙습니다.
  /// 따라서 폰은 반드시 PC 의 서버를 통해서만 데이터를 받습니다.
  ///
  ///   [Core 보드] --USB--> [PC: bridge/main.py] --> [PC: FastAPI] --> [폰]
  ///
  /// - Android 에뮬레이터: http://10.0.2.2:8000   (PC localhost 매핑)
  /// - iOS 시뮬레이터 / 웹: http://127.0.0.1:8000
  /// - 실기기(같은 WiFi):   http://<PC의 LAN IP>:8000   ← 실기기 테스트는 이걸로
  static const String baseUrl = 'http://127.0.0.1:8000';

  /// 현재 자세 폴링 주기 (브리지가 0.5초마다 전송하므로 1초면 충분)
  static const Duration pollInterval = Duration(seconds: 1);

  /// 히트맵 갱신 주기 (더 자주 갱신하면 부드럽지만 트래픽 증가)
  static const Duration heatmapInterval = Duration(milliseconds: 700);

  /// 센서 채널 수 — bridge/layout.py 의 N_CHANNELS 와 반드시 같아야 합니다.
  static const int channelCount = 32;

  /// 사용자 식별자 (로그인 붙이기 전까지 고정)
  static const String userId = 'default';

  /// 등록해야 하는 기준 자세 목록 (초기 설정 화면 순서)
  static const List<String> calibrationLabels = [
    '정자세',
    '앞으로 숙이기',
    '뒤로 기대기',
    '오른다리 꼬기',
    '왼다리 꼬기',
    '좌측 기대기',
    '우측 기대기',
  ];
}
