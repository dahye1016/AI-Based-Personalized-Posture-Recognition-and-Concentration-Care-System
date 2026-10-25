import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'package:flutter/foundation.dart'
    show kIsWeb, debugPrint, Listenable, ValueNotifier;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/sensor_frame.dart';
import '../models/sensor_layout.dart';

/// 보드 한 대의 연결 상태 (화면 표시용).
enum BoardLinkStatus {
  /// 연결도 탐색도 하지 않음 (사용자가 끊었거나 아직 시작 전).
  off,

  /// 스캔·연결 시도·재연결 대기 중.
  searching,

  /// GATT 연결됨.
  connected,
}

/// PoseLab 보드의 역할. 같은 펌웨어를 두 보드에 올리고 부팅 시 DIP SW1 로 정한다.
/// 광고 이름은 펌웨어 `BLE_NAME_SEAT` / `BLE_NAME_BACK` 과 철자가 같아야 한다.
enum BleBoard {
  /// 좌석 (SW1 OFF).
  seat('PoseLab-Seat'),

  /// 등받이 (SW1 ON).
  back('PoseLab-Back');

  const BleBoard(this.advName);

  /// BLE 광고 이름.
  final String advName;

  /// 광고 이름 -> 보드 역할. PoseLab 보드가 아니면 null.
  static BleBoard? fromName(String name) {
    for (final b in values) {
      if (b.advName == name) return b;
    }
    return null;
  }
}

/// 방석센서(PoseLab) BLE 수신 서비스.
///
/// 책임 범위: 스캔 → 연결 → MTU 협상 → Notify 구독 → 66byte 프레임 파싱까지.
/// ★ 원시값을 서버로 보내지 않는다. 파싱한 [SensorFrame] 을 [frames] 스트림으로만
///   흘려보내고, 자세 판정은 앱(온디바이스)이 이 스트림을 구독해서 한다.
///
/// 펌웨어 스펙 (firmware/PoseLabCore_BLE):
///   - 기기명 PoseLab-Seat / PoseLab-Back ([BleBoard], DIP SW1) / Service 180A /
///     TX char 2A98 (Notify) / 10Hz
///   - 좌석·등받이 2대를 각각 독립적으로 연결한다. [frames] 는 좌석, [backFrames] 는 등받이.
///     둘의 병합(64ch 프레임)은 아직 하지 않는다.
///   - 페이로드 66byte = frame_no(uint16 LE) + ch0~31(각 uint16 LE)
///   - 66byte 수신하려면 MTU >= 69 (페이로드 66 + ATT 헤더 3)
class BleService {
  // ── 펌웨어 스펙 상수 ──────────────────────────────────────────────
  static const String _service16 = '180a';
  static const String _char16 = '2a98';
  // NOTE: 스캔 필터(withServices)는 쓰지 않는다. 광고 매칭은 이름([BleBoard])만 보고,
  //       180A/2A98 은 연결 후 GATT 에서 확인한다([_subscribe]).
  //       (두 보드가 같은 UUID 라 광고 UUID 로는 좌석/등받이를 못 가르고,
  //        180A 는 표준 서비스라 다른 기기도 광고한다.)

  static const int _payloadLen = 66; // frame_no(2) + 32ch * 2
  static const int _minMtu = 69; // 66 + ATT 헤더 3

  // ── 스캔 창 ──────────────────────────────────────────────────────
  static const Duration _scanTimeout = Duration(seconds: 10);
  static const Duration _scanWindow = Duration(seconds: 15); // 안전망 포함

  // ── 재연결 backoff (2s → 4s → 8s → … → 최대 30s) ─────────────────
  static const int _baseReconnectMs = 2000;
  static const int _maxReconnectMs = 30000;

  /// 보드별 연결 상태. 좌석·등받이가 각각 독립적으로 연결·해제·재연결된다.
  final Map<BleBoard, _BoardLink> _links = {
    for (final b in BleBoard.values) b: _BoardLink(b),
  };

  _BoardLink get _seat => _links[BleBoard.seat]!;
  _BoardLink get _back => _links[BleBoard.back]!;

  /// 스캔은 FlutterBluePlus 전역에 하나뿐이라 두 보드가 공유한다.
  StreamSubscription? _scanSub;
  Timer? _scanWindowTimer;

  /// 지금 스캔에서 찾고 있는 보드.
  final Set<BleBoard> _wanted = {};

  /// 사용자가 끊었는지. true 면 자동 재연결을 하지 않는다. [connect] 에서 false 로 되돌린다.
  bool _manualDisconnect = false;

  /// 좌석 프레임 스트림. 온디바이스 판정기가 이걸 구독한다.
  Stream<SensorFrame> get frames => _seat.frameController.stream;

  /// 좌석 연결 상태.
  bool get isConnected => _seat.isConnected;

  /// 등받이 프레임 스트림. channels 는 **등받이 보드 기준 ch0~31**
  /// (= 64ch 프레임의 ch32~63). 좌석과의 병합은 아직 하지 않는다.
  Stream<SensorFrame> get backFrames => _back.frameController.stream;

  /// 등받이 연결 상태.
  bool get isBackConnected => _back.isConnected;

  /// 보드 연결 상태가 바뀔 때마다 알린다. 화면은 이걸 듣고 [statusOf] 를 다시 읽는다.
  Listenable get statusListenable => _statusTick;
  final ValueNotifier<int> _statusTick = ValueNotifier<int>(0);
  void _notifyStatus() => _statusTick.value++;

  /// 보드별 연결 상태. 이름(`PoseLab-Seat` / `PoseLab-Back`)으로 구분된 보드 기준.
  BoardLinkStatus statusOf(BleBoard b) {
    final l = _links[b]!;
    if (l.isConnected) return BoardLinkStatus.connected;
    if (_manualDisconnect) return BoardLinkStatus.off;
    if (_wanted.contains(b) ||
        l.connecting ||
        l.pending != null ||
        (l.reconnectTimer?.isActive ?? false)) {
      return BoardLinkStatus.searching;
    }
    return BoardLinkStatus.off;
  }

  // ── 공개 API ─────────────────────────────────────────────────────
  /// 좌석·등받이를 한 스캔 창에서 함께 찾아 연결한다.
  ///
  /// 반환값은 **좌석**이 초기 스캔 창 안에 연결됐는지다. 좌석·등받이 모두 초기 창에서
  /// 못 찾으면, 수동 해제가 아닌 한 backoff 로 계속 재스캔한다 (보드를 늦게 켜는 경우 대비).
  Future<bool> connect() async {
    try {
      _manualDisconnect = false;
      debugPrint('[BLE] connect() 시작');

      if (!kIsWeb && Platform.isAndroid) {
        debugPrint('[BLE] Android 권한 요청');
        await [
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.locationWhenInUse,
        ].request();
      } else {
        debugPrint('[BLE] iOS/기타 — 권한은 Info.plist 기반(첫 사용 시 시스템 팝업)');
      }

      final supported = await FlutterBluePlus.isSupported;
      debugPrint('[BLE] isSupported=$supported');
      if (!supported) {
        debugPrint('[BLE] 이 기기는 BLE 미지원 — 중단');
        return false;
      }

      debugPrint('[BLE] 어댑터 상태=${FlutterBluePlus.adapterStateNow}');
      if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
        debugPrint('[BLE] 어댑터 ON 대기…');
        await FlutterBluePlus.adapterState
            .where((s) => s == BluetoothAdapterState.on)
            .first
            .timeout(const Duration(seconds: 5));
      }
      debugPrint('[BLE] 어댑터 ON');

      for (final l in _links.values) {
        l.reconnectDelayMs = _baseReconnectMs; // 새 연결 시 backoff 초기화
      }
      final results = _scanFor(BleBoard.values.toSet());

      // 두 보드 모두, 처음 스캔 창에서 못 찾으면 backoff 로 계속 다시 찾는다.
      // (예전엔 좌석은 재시도하지 않아, 보드가 늦게 켜지거나 잠깐 다른 기기에
      //  붙어 있으면 '꺼짐'으로 남았다.)
      results[BleBoard.back]!.then((ok) {
        if (!ok && !_manualDisconnect) _scheduleReconnect(_back);
      });
      final seatOk = await results[BleBoard.seat]!;
      if (!seatOk && !_manualDisconnect) _scheduleReconnect(_seat);
      return seatOk;
    } catch (e) {
      debugPrint('[BLE] connect 에러: $e');
      return false;
    }
  }

  Future<void> disconnect() async {
    _manualDisconnect = true;
    _endScanSession();
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    for (final l in _links.values) {
      await l.disconnect();
    }
    _notifyStatus();
  }

  /// 스트림까지 완전히 정리 (앱 종료/서비스 폐기 시).
  Future<void> dispose() async {
    await disconnect();
    for (final l in _links.values) {
      await l.frameController.close();
    }
  }

  // ── 스캔 (두 보드 공유) ──────────────────────────────────────────
  /// [want] 보드를 찾아 연결한다. 보드별 결과(연결 성공 여부)를 돌려준다.
  /// 이미 스캔 중이면 새 스캔을 열지 않고 찾는 목록에만 더한다 (남은 창 시간 동안 찾음).
  Map<BleBoard, Future<bool>> _scanFor(Set<BleBoard> want) {
    final out = <BleBoard, Future<bool>>{};
    for (final b in want) {
      final link = _links[b]!;
      if (link.isConnected) {
        out[b] = Future.value(true);
        continue;
      }
      link.pending ??= Completer<bool>();
      out[b] = link.pending!.future;
      if (!link.connecting) _wanted.add(b);
    }
    if (_wanted.isNotEmpty && _scanSub == null) _startScanSession();
    _notifyStatus();
    return out;
  }

  void _startScanSession() {
    final seen = <String>{}; // 발견 로그 중복 방지 (remoteId 단위)
    final idsByBoard = <BleBoard, Set<String>>{}; // 같은 이름 중복 감지용
    final warned = <BleBoard>{};

    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        final id = r.device.remoteId.str; // iOS=기기별 고유 UUID / Android=MAC
        // iOS 는 platformName 을 캐시하므로 지금 광고 이름(advName)을 우선한다.
        final advName = r.advertisementData.advName;
        final name = advName.isNotEmpty ? advName : r.device.platformName;
        final uuids = r.advertisementData.serviceUuids;

        if (seen.add(id)) {
          debugPrint('[BLE] 발견 id=$id name="$name" '
              'services=${uuids.map((g) => g.str).toList()} rssi=${r.rssi}');
        }

        final board = BleBoard.fromName(name);
        if (board == null) continue; // 이름이 PoseLab 이 아니면 UUID 가 맞아도 무시

        final ids = idsByBoard.putIfAbsent(board, () => <String>{})..add(id);
        if (ids.length > 1 && warned.add(board)) {
          debugPrint('[BLE] ${board.advName} 이 ${ids.length}대 보임 — DIP SW1 확인 '
              '(등받이는 ON)');
        }

        if (!_wanted.remove(board)) continue;
        final link = _links[board]!;
        link.connecting = true;
        debugPrint('[BLE ${board.name}] 대상 매칭 id=$id name="$name" → 연결 시도');
        _establish(link, r.device).then((ok) {
          link.connecting = false;
          _completePending(link, ok);
          if (_wanted.isEmpty) _endScanSession();
        });
      }
    });

    debugPrint('[BLE] 스캔 시작 (필터 없음, 이름 매칭) 대상=${_wanted.map((b) => b.name)}');
    FlutterBluePlus.startScan(timeout: _scanTimeout).catchError((Object e) {
      debugPrint('[BLE] 스캔 시작 실패: $e');
    });

    // 스캔 창 안전망 — 창이 끝날 때까지 못 찾은 보드는 실패로 끝낸다.
    _scanWindowTimer = Timer(_scanWindow, () {
      for (final b in _wanted) {
        debugPrint('[BLE ${b.name}] 스캔 창 종료 — ${b.advName} 못 찾음');
      }
      _endScanSession();
    });
  }

  /// 스캔 세션을 닫는다. 아직 찾는 중이던 보드는 실패(false)로 완료한다.
  void _endScanSession() {
    _scanWindowTimer?.cancel();
    _scanWindowTimer = null;
    _scanSub?.cancel();
    _scanSub = null;
    final missed = _wanted.toList();
    _wanted.clear();
    for (final b in missed) {
      _completePending(_links[b]!, false);
    }
    FlutterBluePlus.stopScan().catchError((Object _) {});
    _notifyStatus();
  }

  void _completePending(_BoardLink link, bool ok) {
    final p = link.pending;
    link.pending = null;
    if (p != null && !p.isCompleted) p.complete(ok);
    _notifyStatus();
  }

  // ── 연결 (보드별) ────────────────────────────────────────────────
  Future<bool> _establish(_BoardLink link, BluetoothDevice device) async {
    final tag = '[BLE ${link.board.name}]';
    try {
      link.device = device;
      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 15),
      );
      await device.connectionState
          .where((s) => s == BluetoothConnectionState.connected)
          .first
          .timeout(const Duration(seconds: 10));
      debugPrint('$tag 연결됨 (GATT connected)');

      link.isConnected = true;
      link.reconnectDelayMs = _baseReconnectMs; // 연결 성공 → backoff 리셋
      _notifyStatus();

      await _negotiateMtu(link, device);
      _listenConnectionState(link, device); // 자동 재연결 감시
      final ok = await _subscribe(link, device);
      debugPrint(ok ? '$tag 준비 완료 — 프레임 수신 대기' : '$tag 구독 실패');
      return ok;
    } catch (e) {
      debugPrint('$tag 연결 실패: $e');
      link.isConnected = false;
      _notifyStatus();
      return false;
    }
  }

  Future<void> _negotiateMtu(_BoardLink link, BluetoothDevice device) async {
    final tag = '[BLE ${link.board.name}]';
    // iOS 는 MTU 를 자동 협상하므로 requestMtu 가 무시된다 → Android 만 명시 요청.
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final mtu = await device.requestMtu(517);
        if (mtu < _minMtu) {
          debugPrint('$tag ⚠️ MTU $mtu < $_minMtu — 66byte 프레임이 잘려 파싱 실패 가능');
        } else {
          debugPrint('$tag MTU=$mtu');
        }
      } catch (e) {
        debugPrint('$tag MTU 협상 실패(연결 유지): $e');
      }
    } else {
      final mtu = device.mtuNow;
      if (mtu < _minMtu) {
        debugPrint('$tag ⚠️ MTU $mtu < $_minMtu (자동협상) — 프레임 잘림 가능');
      } else {
        debugPrint('$tag MTU=$mtu (자동협상)');
      }
    }
  }

  /// 180A/2A98 Notify 구독. 이름은 맞는데 이 서비스가 없으면 우리 보드가 아니다.
  Future<bool> _subscribe(_BoardLink link, BluetoothDevice device) async {
    final tag = '[BLE ${link.board.name}]';
    final services = await device.discoverServices();
    for (final s in services) {
      if (!_sameUuid(s.serviceUuid, _service16)) continue;
      for (final c in s.characteristics) {
        if (!_sameUuid(c.characteristicUuid, _char16)) continue;
        await c.setNotifyValue(true);
        await link.dataSub?.cancel();
        link.dataSub = c.onValueReceived.listen((raw) => _onData(link, raw));
        debugPrint('$tag Notify 구독 시작: 180A/2A98');
        return true;
      }
    }
    debugPrint('$tag 대상 characteristic(2A98) 미발견');
    return false;
  }

  // ── 프레임 파싱 (좌석·등받이 공용, 같은 66byte 형식) ────────────────
  void _onData(_BoardLink link, List<int> raw) {
    final tag = '[BLE ${link.board.name}]';
    if (raw.length != _payloadLen) {
      debugPrint('$tag 프레임 길이 이상: ${raw.length} (기대 $_payloadLen) — skip');
      return;
    }

    final bytes = ByteData.sublistView(Uint8List.fromList(raw));
    final frameNo = bytes.getUint16(0, Endian.little);
    final channels = List<int>.generate(
      SensorLayout.nChannels,
      (i) => bytes.getUint16(2 + i * 2, Endian.little),
    );

    // 패킷 유실 감지 (uint16 wrap-around 고려). 건너뛴 개수만 로그.
    final last = link.lastFrameNo;
    if (last != null) {
      final gap = (frameNo - last - 1) & 0xFFFF;
      if (gap > 0 && gap < 0x8000) {
        debugPrint('$tag 프레임 유실 $gap개 (prev=$last, cur=$frameNo)');
      }
    }
    link.lastFrameNo = frameNo;
    if (frameNo % 10 == 0) debugPrint('$tag rx len=${raw.length} frameNo=$frameNo sum=${channels.fold<int>(0, (a, b) => a + b)}'); // TODO(작업36): 등받이 수신 확인 후 삭제

    if (link.frameController.isClosed) return;
    link.frameController.add(SensorFrame(
      frameNo: frameNo,
      channels: channels,
      receivedAt: DateTime.now(),
    ));
  }

  // ── 자동 재연결 (보드별) ─────────────────────────────────────────
  void _listenConnectionState(_BoardLink link, BluetoothDevice device) {
    link.connStateSub?.cancel();
    link.connStateSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        link.isConnected = false;
        link.dataSub?.cancel();
        _notifyStatus();
        if (!_manualDisconnect) {
          debugPrint('[BLE ${link.board.name}] 연결 끊김 — 재연결 예약 (다른 보드는 유지)');
          _scheduleReconnect(link);
        }
      }
    });
  }

  void _scheduleReconnect(_BoardLink link) {
    final tag = '[BLE ${link.board.name}]';
    link.reconnectTimer?.cancel();
    debugPrint('$tag ${link.reconnectDelayMs ~/ 1000}s 후 재연결 시도');
    link.reconnectTimer =
        Timer(Duration(milliseconds: link.reconnectDelayMs), () async {
      _notifyStatus();
      if (_manualDisconnect) return;
      final ok = await _scanFor({link.board})[link.board]!;
      if (!ok && !_manualDisconnect) {
        // 실패 시 backoff 증가 (2→4→8→…→30s). 방석 전원 오프 시 배터리 보호.
        link.reconnectDelayMs =
            (link.reconnectDelayMs * 2).clamp(_baseReconnectMs, _maxReconnectMs);
        _scheduleReconnect(link);
      }
    });
    _notifyStatus();
  }

  // ── UUID 매칭 (16bit 단축형 / 128bit 확장형 양쪽 허용) ────────────
  bool _sameUuid(Guid g, String short16) {
    final s = g.str.toLowerCase();
    final full = '0000${short16.toLowerCase()}-0000-1000-8000-00805f9b34fb';
    return s == short16.toLowerCase() || g.str128.toLowerCase() == full;
  }
}

/// 보드 한 대의 연결 상태 묶음.
class _BoardLink {
  _BoardLink(this.board);

  final BleBoard board;

  BluetoothDevice? device;
  StreamSubscription? dataSub;
  StreamSubscription? connStateSub;
  Timer? reconnectTimer;
  int reconnectDelayMs = 2000;

  bool isConnected = false;

  /// 스캔에서 매칭돼 연결 시도 중인지 (같은 보드 중복 연결 방지).
  bool connecting = false;

  /// 지금 스캔 창에서 기다리는 연결 결과. 없으면 null.
  Completer<bool>? pending;

  int? lastFrameNo;

  final StreamController<SensorFrame> frameController =
      StreamController<SensorFrame>.broadcast();

  /// 이 보드만 끊는다. 스트림은 닫지 않는다.
  Future<void> disconnect() async {
    reconnectTimer?.cancel();
    await dataSub?.cancel();
    await connStateSub?.cancel();
    dataSub = null;
    connStateSub = null;
    try {
      await device?.disconnect();
    } catch (_) {}
    isConnected = false;
    connecting = false;
    device = null;
    lastFrameNo = null;
  }
}
