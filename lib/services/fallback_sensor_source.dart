import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import 'ble_sensor_source.dart';
import 'sensor_source.dart';

/// BLE 를 먼저 시도하고, 정해진 시간 안에 프레임이 안 오면
/// 가짜 소스로 자동 전환하는 소스.
///
/// 방석 없이 앱을 켰을 때 화면이 영영 "센서 데이터를 기다리는 중"에
/// 멈춰 있는 걸 막는다. 실제 프레임이 한 번이라도 들어오면 가짜 소스는
/// 즉시 멈추고, 그 뒤로는 진짜 데이터만 흐른다.
class FallbackSensorSource implements SensorSource {
  FallbackSensorSource({this.timeout = const Duration(seconds: 12)});

  /// 이 시간 안에 BLE 프레임이 하나도 안 오면 가짜 소스를 켠다.
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
      if (!_gotReal) {
        debugPrint('[SOURCE] ${timeout.inSeconds}초 동안 프레임 없음 — 가짜 소스로 전환');
        _startMock();
      }
    });

    await _ble.connect();
  }

  void _startMock() {
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
