import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'posture_layout.dart';
import 'sensor_source.dart';

/// 방석센서(Cushion-MDEX) BLE 실수신 소스.
///
/// `sensor_source.dart` 에 비어 있던 [BleSensorSource] 자리를 채운 것이다.
/// 책임 범위: 스캔 → 연결 → MTU 협상 → Notify 구독 → 66byte 프레임 파싱까지.
/// 파싱한 32채널 raw 프레임을 [frames] 로 흘려보내고, 자세 판정은
/// 기존대로 `PostureClassifier` 가 온디바이스에서 한다. 원시값은 서버로 안 보낸다.
///
/// 펌웨어 스펙 (firmware/PoseLabCore_BLE):
///   - 기기명 `Cushion-MDEX` / Service `180A` / TX char `2A98` (Notify) / 10Hz
///   - 페이로드 66byte = frame_no(uint16 LE) + ch0~31(각 uint16 LE)
///   - 66byte를 받으려면 MTU >= 69 (페이로드 66 + ATT 헤더 3)
///
/// 사용법:
/// ```dart
/// final ble = BleSensorSource();
/// await ble.connect();          // 실패해도 예외 없이 false 반환
/// HomeScreen(source: ble);      // frames() 를 그대로 구독한다
/// ```
class BleSensorSource implements SensorSource {
  // ── 펌웨어 스펙 상수 ────────────────────────────────────────────
  static const String deviceName = 'Cushion-MDEX';
  static const String _service16 = '180a';
  static const String _char16 = '2a98';

  static const int _payloadLen = 66; // frame_no(2) + 32ch * 2
  static const int _minMtu = 69; // 66 + ATT 헤더 3

  // ── 재연결 backoff (2s → 4s → … → 최대 30s) ────────────────────
  static const int _baseReconnectMs = 2000;
  static const int _maxReconnectMs = 30000;
  int _reconnectDelayMs = _baseReconnectMs;
  Timer? _reconnectTimer;

  BluetoothDevice? _device;
  StreamSubscription? _scanSub;
  StreamSubscription? _dataSub;
  StreamSubscription? _connStateSub;

  bool _manualDisconnect = false;
  int? _lastFrameNo;

  final _frameCtrl = StreamController<List<int>>.broadcast();
  final _stateCtrl = StreamController<BleLinkState>.broadcast();

  BleLinkState _state = BleLinkState.idle;

  @override
  Stream<List<int>> frames() => _frameCtrl.stream;

  /// 연결 상태 변화. 화면 상단 배지 등에 쓴다.
  Stream<BleLinkState> get linkState => _stateCtrl.stream;

  BleLinkState get state => _state;
  bool get isConnected => _state == BleLinkState.connected;

  void _setState(BleLinkState s) {
    if (_state == s) return;
    _state = s;
    if (!_stateCtrl.isClosed) _stateCtrl.add(s);
  }

  // ── 공개 API ───────────────────────────────────────────────────

  /// 스캔해서 방석에 붙는다. 성공하면 true.
  /// 실패해도 예외를 던지지 않으므로 호출부에서 mock 으로 폴백하기 쉽다.
  Future<bool> connect() async {
    try {
      _manualDisconnect = false;
      _setState(BleLinkState.scanning);
      debugPrint('[BLE] connect() 시작');

      if (!kIsWeb && Platform.isAndroid) {
        await [
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.locationWhenInUse,
        ].request();
      }

      final supported = await FlutterBluePlus.isSupported;
      if (!supported) {
        debugPrint('[BLE] 이 기기는 BLE 미지원 — 중단');
        _setState(BleLinkState.unsupported);
        return false;
      }

      if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
        debugPrint('[BLE] 어댑터 ON 대기…');
        await FlutterBluePlus.adapterState
            .where((s) => s == BluetoothAdapterState.on)
            .first
            .timeout(const Duration(seconds: 5));
      }

      _reconnectDelayMs = _baseReconnectMs;
      return await _scanAndConnect();
    } catch (e) {
      debugPrint('[BLE] connect 에러: $e');
      _setState(BleLinkState.failed);
      return false;
    }
  }

  Future<void> disconnect() async {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    await _dataSub?.cancel();
    await _scanSub?.cancel();
    await _connStateSub?.cancel();
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    await _device?.disconnect();
    _device = null;
    _lastFrameNo = null;
    _setState(BleLinkState.idle);
  }

  @override
  void dispose() {
    disconnect();
    _frameCtrl.close();
    _stateCtrl.close();
  }

  // ── 스캔 + 연결 ────────────────────────────────────────────────
  Future<bool> _scanAndConnect() async {
    final completer = Completer<bool>();
    var connecting = false;
    final seen = <String>{};

    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.onScanResults.listen((results) async {
      if (connecting || completer.isCompleted) return;

      // 이름 OR 서비스 UUID 중 하나만 맞아도 매칭한다.
      // iOS 는 광고에서 로컬명이나 서비스 UUID 를 숨기는 경우가 있어
      // 둘 다 요구하면 영영 못 찾는다.
      ScanResult? hit;
      for (final r in results) {
        final id = r.device.remoteId.str;
        final advName = r.advertisementData.advName;
        final name = advName.isNotEmpty ? advName : r.device.platformName;
        final uuids = r.advertisementData.serviceUuids;

        if (seen.add(id)) {
          debugPrint('[BLE] 발견 id=$id name="$name" '
              'services=${uuids.map((g) => g.str).toList()} rssi=${r.rssi}');
        }

        final nameOk = name == deviceName;
        final uuidOk = uuids.any((g) => _sameUuid(g, _service16));
        if (nameOk || uuidOk) {
          hit = r;
          break;
        }
      }
      if (hit == null) return;

      connecting = true;
      debugPrint('[BLE] 대상 매칭 id=${hit.device.remoteId.str} → 연결 시도');
      await FlutterBluePlus.stopScan();
      final ok = await _establish(hit.device);
      if (!completer.isCompleted) completer.complete(ok);
    });

    debugPrint('[BLE] 스캔 시작');
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

    Future.delayed(const Duration(seconds: 15), () {
      if (!completer.isCompleted) {
        debugPrint('[BLE] 스캔 타임아웃 — 대상 기기 못 찾음 '
            '(위 발견 로그에서 방석 id 를 확인하세요)');
        _setState(BleLinkState.notFound);
        completer.complete(false);
      }
    });

    return completer.future;
  }

  Future<bool> _establish(BluetoothDevice device) async {
    try {
      _device = device;
      _setState(BleLinkState.connecting);
      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 15),
      );
      await device.connectionState
          .where((s) => s == BluetoothConnectionState.connected)
          .first
          .timeout(const Duration(seconds: 10));
      debugPrint('[BLE] 연결됨 (GATT connected)');

      _reconnectDelayMs = _baseReconnectMs;

      await _negotiateMtu(device);
      _listenConnectionState(device);
      final ok = await _subscribe(device);
      _setState(ok ? BleLinkState.connected : BleLinkState.failed);
      debugPrint(ok ? '[BLE] 준비 완료 — 프레임 수신 대기' : '[BLE] 구독 실패');
      return ok;
    } catch (e) {
      debugPrint('[BLE] 연결 실패: $e');
      _setState(BleLinkState.failed);
      return false;
    }
  }

  Future<void> _negotiateMtu(BluetoothDevice device) async {
    // iOS 는 MTU 를 자동 협상하므로 requestMtu 가 무시된다 → Android 만 명시 요청.
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final mtu = await device.requestMtu(517);
        if (mtu < _minMtu) {
          debugPrint('[BLE] ⚠️ MTU $mtu < $_minMtu — 66byte 프레임이 잘려 파싱 실패 가능');
        } else {
          debugPrint('[BLE] MTU=$mtu');
        }
      } catch (e) {
        debugPrint('[BLE] MTU 협상 실패(연결 유지): $e');
      }
    } else {
      final mtu = device.mtuNow;
      if (mtu < _minMtu) {
        debugPrint('[BLE] ⚠️ MTU $mtu < $_minMtu (자동협상) — 프레임 잘림 가능');
      } else {
        debugPrint('[BLE] MTU=$mtu (자동협상)');
      }
    }
  }

  Future<bool> _subscribe(BluetoothDevice device) async {
    final services = await device.discoverServices();
    for (final s in services) {
      if (!_sameUuid(s.serviceUuid, _service16)) continue;
      for (final c in s.characteristics) {
        if (!_sameUuid(c.characteristicUuid, _char16)) continue;
        await c.setNotifyValue(true);
        await _dataSub?.cancel();
        _dataSub = c.onValueReceived.listen(_onData);
        debugPrint('[BLE] Notify 구독 시작: 180A/2A98');
        return true;
      }
    }
    debugPrint('[BLE] 대상 characteristic(2A98) 미발견');
    return false;
  }

  // ── 프레임 파싱 ────────────────────────────────────────────────
  void _onData(List<int> raw) {
    if (raw.length != _payloadLen) {
      debugPrint('[BLE] 프레임 길이 이상: ${raw.length} (기대 $_payloadLen) — skip');
      return;
    }

    final bytes = ByteData.sublistView(Uint8List.fromList(raw));
    final frameNo = bytes.getUint16(0, Endian.little);
    final channels = List<int>.generate(
      PostureLayout.channels,
      (i) => bytes.getUint16(2 + i * 2, Endian.little),
    );

    // 패킷 유실 감지 (uint16 wrap-around 고려)
    if (_lastFrameNo != null) {
      final gap = (frameNo - _lastFrameNo! - 1) & 0xFFFF;
      if (gap > 0 && gap < 0x8000) {
        debugPrint('[BLE] 프레임 유실 $gap개 (prev=$_lastFrameNo, cur=$frameNo)');
      }
    }
    _lastFrameNo = frameNo;

    if (!_frameCtrl.isClosed) _frameCtrl.add(channels);
  }

  // ── 자동 재연결 ────────────────────────────────────────────────
  void _listenConnectionState(BluetoothDevice device) {
    _connStateSub?.cancel();
    _connStateSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _dataSub?.cancel();
        if (!_manualDisconnect) {
          _setState(BleLinkState.reconnecting);
          debugPrint('[BLE] 연결 끊김 — 재연결 예약');
          _scheduleReconnect();
        }
      }
    });
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    debugPrint('[BLE] ${_reconnectDelayMs ~/ 1000}s 후 재연결 시도');
    _reconnectTimer = Timer(Duration(milliseconds: _reconnectDelayMs), () async {
      if (_manualDisconnect) return;
      final ok = await _scanAndConnect();
      if (!ok && !_manualDisconnect) {
        // 방석 전원이 꺼진 동안 배터리를 갉아먹지 않도록 간격을 늘린다.
        _reconnectDelayMs =
            (_reconnectDelayMs * 2).clamp(_baseReconnectMs, _maxReconnectMs);
        _scheduleReconnect();
      }
    });
  }

  // ── UUID 매칭 (16bit 단축형 / 128bit 확장형 양쪽 허용) ──────────
  bool _sameUuid(Guid g, String short16) {
    final s = g.str.toLowerCase();
    final full = '0000${short16.toLowerCase()}-0000-1000-8000-00805f9b34fb';
    return s == short16.toLowerCase() || g.str128.toLowerCase() == full;
  }
}

/// BLE 링크 상태.
enum BleLinkState {
  idle,
  scanning,
  connecting,
  connected,
  reconnecting,
  notFound,
  failed,
  unsupported,
}

extension BleLinkStateLabel on BleLinkState {
  String get label => switch (this) {
        BleLinkState.idle => '연결 안 됨',
        BleLinkState.scanning => '방석 찾는 중…',
        BleLinkState.connecting => '연결 중…',
        BleLinkState.connected => '연결됨',
        BleLinkState.reconnecting => '재연결 중…',
        BleLinkState.notFound => '방석을 못 찾았어요',
        BleLinkState.failed => '연결 실패',
        BleLinkState.unsupported => 'BLE 미지원 기기',
      };
}
