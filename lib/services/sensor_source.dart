import 'dart:async';
import 'dart:math';
import 'posture_layout.dart';

/// 자세 데이터가 앱으로 들어오는 "입구"(추상).
///
/// 전송 방식이 BLE든 서버든 온디바이스든, 결국 앱이 받는 건
/// "32개 정수 한 묶음(raw 프레임)"으로 똑같다.
/// 화면은 이 인터페이스만 바라보므로, 전송 방식이 확정되면
/// 아래 구현체(Ble…)만 갈아끼우면 된다. 화면 코드는 안 바뀐다.
abstract class SensorSource {
  Stream<List<int>> frames(); // 32채널 raw 프레임 스트림
  void dispose();
}

/// 지금 당장 앱을 돌리기 위한 가짜 소스.
/// 센서 없이도 자세가 바뀌며 흐르도록 4가지 자세를 순환 생성한다.
/// (시연·개발용. 실제 센서 붙기 전까지 이걸로 화면이 살아 움직인다.)
class MockSensorSource implements SensorSource {
  Timer? _timer;
  final _ctrl = StreamController<List<int>>.broadcast();
  final _rng = Random();
  int _phase = 0;

  MockSensorSource() {
    _timer = Timer.periodic(const Duration(milliseconds: 900), (_) {
      _ctrl.add(_frameFor(_phase));
      _phase = (_phase + 1) % 4;
    });
  }

  List<int> _frameFor(int phase) {
    final v = List<int>.generate(
        PostureLayout.channels, (_) => 300 + _rng.nextInt(120));
    void boost(List<int> idx, int amount) {
      for (final i in idx) {
        v[i] += amount;
      }
    }

    switch (phase) {
      case 0:
        break; // 바른자세 (고른 분포)
      case 1:
        boost(PostureLayout.left, 380); // 다리꼬기 (좌 쏠림)
        break;
      case 2:
        boost(PostureLayout.front, 420); // 거북목 (앞 쏠림)
        break;
      case 3:
        boost(PostureLayout.back, 420); // 기대기 (뒤 쏠림)
        break;
    }
    return v;
  }

  @override
  Stream<List<int>> frames() => _ctrl.stream;

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.close();
  }
}

/// 실제 BLE 연결용 소스는 `ble_sensor_source.dart` 로 옮겼다.
///
/// 이 파일은 추상(SensorSource)과 개발용 가짜 소스(MockSensorSource)만 갖는다.
/// 실기기 연동은 `import 'ble_sensor_source.dart';` 후 [BleSensorSource] 를 쓴다.
