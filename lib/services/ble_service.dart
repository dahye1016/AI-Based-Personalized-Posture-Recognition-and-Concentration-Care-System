import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/sensor_frame.dart';
import '../models/sensor_layout.dart';

/// 방석센서(Cushion-MDEX) BLE 수신 서비스.
///
/// 책임 범위: 스캔 → 연결 → MTU 협상 → Notify 구독 → 66byte 프레임 파싱까지.
/// ★ 원시값을 서버로 보내지 않는다. 파싱한 [SensorFrame] 을 [frames] 스트림으로만
///   흘려보내고, 자세 판정은 앱(온디바이스)이 이 스트림을 구독해서 한다.
///
/// 펌웨어 스펙 (firmware/PoseLabCore_BLE):
///   - 기기명 Cushion-MDEX / Service 180A / TX char 2A98 (Notify) / 10Hz
///   - 페이로드 66byte = frame_no(uint16 LE) + ch0~31(각 uint16 LE)
///   - 66byte 수신하려면 MTU >= 69 (페이로드 66 + ATT 헤더 3)
class BleService {
  // ── 펌웨어 스펙 상수 ──────────────────────────────────────────────
  static const String _deviceName = 'Cushion-MDEX';
  static const String _service16 = '180a';
  static const String _char16 = '2a98';
  static final Guid _serviceGuid =
      Guid('0000180A-0000-1000-8000-00805F9B34FB');

  static const int _payloadLen = 66; // frame_no(2) + 32ch * 2
  static const int _minMtu = 69; // 66 + ATT 헤더 3

  // ── 재연결 backoff (2s → 4s → 8s → … → 최대 30s) ─────────────────
  static const int _baseReconnectMs = 2000;
  static const int _maxReconnectMs = 30000;
  int _reconnectDelayMs = _baseReconnectMs;
  Timer? _reconnectTimer;

  BluetoothDevice? _device;
  StreamSubscription? _scanSub;
  StreamSubscription? _dataSub;
  StreamSubscription? _connStateSub;

  bool _isConnected = false;
  bool _manualDisconnect = false;
  int? _lastFrameNo;

  final StreamController<SensorFrame> _frameController =
      StreamController<SensorFrame>.broadcast();

  /// 파싱된 압력 프레임 스트림. 온디바이스 판정기가 이걸 구독한다.
  Stream<SensorFrame> get frames => _frameController.stream;

  bool get isConnected => _isConnected;

  // ── 공개 API ─────────────────────────────────────────────────────
  Future<bool> connect() async {
    try {
      _manualDisconnect = false;

      if (!kIsWeb && Platform.isAndroid) {
        await [
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.locationWhenInUse,
        ].request();
      }

      if (await FlutterBluePlus.isSupported == false) return false;
      await FlutterBluePlus.adapterState
          .where((s) => s == BluetoothAdapterState.on)
          .first;

      _reconnectDelayMs = _baseReconnectMs; // 새 연결 시 backoff 초기화
      return await _scanAndConnect();
    } catch (e) {
      debugPrint('[BLE] connect 에러: $e');
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
    _isConnected = false;
    _device = null;
    _lastFrameNo = null;
  }

  /// 스트림까지 완전히 정리 (앱 종료/서비스 폐기 시).
  Future<void> dispose() async {
    await disconnect();
    await _frameController.close();
  }

  // ── 스캔 + 연결 ──────────────────────────────────────────────────
  Future<bool> _scanAndConnect() async {
    final completer = Completer<bool>();
    bool connecting = false; // 중복 연결 방지

    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.onScanResults.listen((results) async {
      if (connecting || completer.isCompleted) return;

      // 이름 AND Service UUID 둘 다 확인 (플랫폼별 편차 방어)
      ScanResult? hit;
      for (final r in results) {
        final advName = r.advertisementData.advName;
        final name = advName.isNotEmpty ? advName : r.device.platformName;
        final nameOk = name == _deviceName;
        final uuidOk = r.advertisementData.serviceUuids
            .any((g) => _sameUuid(g, _service16));
        if (nameOk && uuidOk) {
          hit = r;
          break;
        }
      }
      if (hit == null) return;

      connecting = true;
      await FlutterBluePlus.stopScan();
      final ok = await _establish(hit.device);
      if (!completer.isCompleted) completer.complete(ok);
    });

    await FlutterBluePlus.startScan(
      withServices: [_serviceGuid],
      timeout: const Duration(seconds: 10),
    );

    // 스캔 타임아웃 안전망
    Future.delayed(const Duration(seconds: 15), () {
      if (!completer.isCompleted) completer.complete(false);
    });

    return completer.future;
  }

  Future<bool> _establish(BluetoothDevice device) async {
    try {
      _device = device;
      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 15),
      );
      await device.connectionState
          .where((s) => s == BluetoothConnectionState.connected)
          .first
          .timeout(const Duration(seconds: 10));

      _isConnected = true;
      _reconnectDelayMs = _baseReconnectMs; // 연결 성공 → backoff 리셋

      await _negotiateMtu(device);
      _listenConnectionState(device); // 자동 재연결 감시
      return await _subscribe(device);
    } catch (e) {
      debugPrint('[BLE] 연결 실패: $e');
      _isConnected = false;
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

  // ── 프레임 파싱 ──────────────────────────────────────────────────
  void _onData(List<int> raw) {
    if (raw.length != _payloadLen) {
      debugPrint('[BLE] 프레임 길이 이상: ${raw.length} (기대 $_payloadLen) — skip');
      return;
    }

    final bytes = ByteData.sublistView(Uint8List.fromList(raw));
    final frameNo = bytes.getUint16(0, Endian.little);
    final channels = List<int>.generate(
      SensorLayout.nChannels,
      (i) => bytes.getUint16(2 + i * 2, Endian.little),
    );

    // 패킷 유실 감지 (uint16 wrap-around 고려). 건너뛴 개수만 로그.
    if (_lastFrameNo != null) {
      final gap = (frameNo - _lastFrameNo! - 1) & 0xFFFF;
      if (gap > 0 && gap < 0x8000) {
        debugPrint('[BLE] 프레임 유실 $gap개 (prev=$_lastFrameNo, cur=$frameNo)');
      }
    }
    _lastFrameNo = frameNo;

    _frameController.add(SensorFrame(
      frameNo: frameNo,
      channels: channels,
      receivedAt: DateTime.now(),
    ));
  }

  // ── 자동 재연결 ──────────────────────────────────────────────────
  void _listenConnectionState(BluetoothDevice device) {
    _connStateSub?.cancel();
    _connStateSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _isConnected = false;
        _dataSub?.cancel();
        if (!_manualDisconnect) {
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
        // 실패 시 backoff 증가 (2→4→8→…→30s). 방석 전원 오프 시 배터리 보호.
        _reconnectDelayMs =
            (_reconnectDelayMs * 2).clamp(_baseReconnectMs, _maxReconnectMs);
        _scheduleReconnect();
      }
    });
  }

  // ── UUID 매칭 (16bit 단축형 / 128bit 확장형 양쪽 허용) ────────────
  bool _sameUuid(Guid g, String short16) {
    final s = g.str.toLowerCase();
    final full = '0000${short16.toLowerCase()}-0000-1000-8000-00805f9b34fb';
    return s == short16.toLowerCase() || g.str128.toLowerCase() == full;
  }
}
