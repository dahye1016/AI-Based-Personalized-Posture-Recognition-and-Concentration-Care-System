import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import 'ble_sensor_source.dart';
import 'sensor_source.dart';

/// BLE 를 먼저 시도하는 소스.
///
/// [allowMock] 이 켜져 있을 때만, 정해진 시간 안에 프레임이 안 오면
/// 가짜 소스로 자동 전환한다. **기본값은 꺼짐(false)** 이다.
///
/// 폴백이 기본으로 켜져 있으면 BLE 가 실패해도 화면이 멀쩡히 움직여서
/// "연동이 된 것"과 "가짜 데이터가 흐르는 것"을 구분할 수 없다.
/// 그래서 기본은 꺼두고, 방석 없이 화면만 보고 싶을 때만 명시적으로 켠다:
///
/// ```bash
/// flutter run                                      # 진짜 BLE 만 (기본)
/// flutter run --dart-define=MOCK_FALLBACK=true     # 방석 없을 때 가짜로 폴백
/// flutter run --dart-define=USE_BLE=false          # 처음부터 가짜만
/// ```
///
/// 실제 프레임이 한 번이라도 들어오면 가짜 소스는 즉시 멈추고,
/// 그 뒤로는 진짜 데이터만 흐른다.
class FallbackSensorSource implements SensorSource {
  FallbackSensorSource({
    this.timeout = const Duration(seconds: 12),
    bool? allowMock,
  }) : allowMock = allowMock ?? _allowMockFromEnv;

  /// `--dart-define=MOCK_FALLBACK=true` 로만 켜진다. 기본 꺼짐.
  static const bool _allowMockFromEnv =
      bool.fromEnvironment('MOCK_FALLBACK', defaultValue: false);

  /// 가짜 소스 자동 전환을 허용할지. 꺼져 있으면 BLE 가 실패했을 때
  /// 데이터가 아예 안 흐르고, 화면은 "데이터 없음" 상태로 남는다.
  final bool allowMock;

  /// 이 시간 안에 BLE 프레임이 하나도 안 오면 (그리고 [allowMock] 이 켜져 있으면)
  /// 가짜 소스를 켠다.
  final Duration timeout;

  final _ctrl = StreamController<List<int>>.broadcast();
  final BleSensorSource _ble = BleSensorSource();

  MockSensorSource? _mock;
  StreamSubscription<List<int>>? _bleSub;
  StreamSubscription<List<int>>? _mockSub;
  Timer? _timer;

  bool _gotReal = false;
  bool _usingMock = false;

  /// 지금 가짜 데이터로 돌고 있는지. 화면에 배지로 알릴 때 쓴다.
  bool get usingMock => _usingMock;

  /// BLE 링크 상태 (연결됨 / 방석 찾는 중 …).
  Stream<BleLinkState> get linkState => _ble.linkState;

  @override
  Stream<List<int>> frames() => _ctrl.stream;

  /// 연결을 시작한다. 실패해도 예외를 던지지 않는다.
  Future<void> start() async {
    _bleSub = _ble.frames().listen((f) {
      if (!_gotReal) {
        _gotReal = true;
        debugPrint('[SOURCE] BLE 프레임 수신 — 가짜 소스 중단');
        _stopMock();
      }
      if (!_ctrl.isClosed) _ctrl.add(f);
    });

    _timer = Timer(timeout, () {
      if (_gotReal) return;
      if (allowMock) {
        debugPrint('[SOURCE] ${timeout.inSeconds}초 동안 프레임 없음 — 가짜 소스로 전환');
        debugPrint('[SOURCE] ⚠️ 지금 화면에 보이는 값은 가짜 데이터입니다.');
        _startMock();
      } else {
        debugPrint('[SOURCE] ${timeout.inSeconds}초 동안 BLE 프레임 없음.');
        debugPrint('[SOURCE] 링크 상태: ${_ble.state.label}');
        debugPrint('[SOURCE] 가짜 소스 폴백은 꺼져 있음 — 데이터가 흐르지 않습니다.');
        debugPrint('[SOURCE] 위 [BLE] 로그에서 실패 지점을 확인하세요. '
            '화면만 보려면 --dart-define=MOCK_FALLBACK=true 로 실행하세요.');
      }
    });

    await _ble.connect();
  }

  void _startMock() {
    if (!allowMock) return;
    if (_mock != null) return;
    final m = MockSensorSource();
    _mock = m;
    _usingMock = true;
    _mockSub = m.frames().listen((f) {
      if (!_gotReal && !_ctrl.isClosed) _ctrl.add(f);
    });
  }

  void _stopMock() {
    _usingMock = false;
    _mockSub?.cancel();
    _mockSub = null;
    _mock?.dispose();
    _mock = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _bleSub?.cancel();
    _stopMock();
    _ble.dispose();
    _ctrl.close();
  }
}
