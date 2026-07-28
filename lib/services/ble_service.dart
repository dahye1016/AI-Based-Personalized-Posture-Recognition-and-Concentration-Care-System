import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import '../config.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class BleService {
  static const String _serviceUuid = "12345678-1234-1234-1234-123456789012";
  static const String _characteristicUuid = "87654321-4321-4321-4321-210987654321";

  BluetoothDevice? _device;
  StreamSubscription? _scanSubscription;
  StreamSubscription? _dataSubscription;
  bool _isConnected = false;

  bool get isConnected => _isConnected;

  Future<bool> connect() async {
    try {
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

      final completer = Completer<bool>();
      bool connecting = false; // 중복 연결 방지

      _scanSubscription = FlutterBluePlus.onScanResults.listen((results) async {
        if (connecting || completer.isCompleted || results.isEmpty) return;
        connecting = true;

        await FlutterBluePlus.stopScan();
        _device = results.first.device;

        try {
          await _device!.connect(
            license: License.free,
            timeout: const Duration(seconds: 15),
          );

          // ★ 실제 '연결됨' 상태가 될 때까지 대기 (이게 핵심)
          await _device!.connectionState
              .where((s) => s == BluetoothConnectionState.connected)
              .first
              .timeout(const Duration(seconds: 10));

          _isConnected = true;

          final services = await _device!.discoverServices();
          for (final s in services) {
            if (s.serviceUuid.str128.toLowerCase() == _serviceUuid) {
              for (final c in s.characteristics) {
                if (c.characteristicUuid.str128.toLowerCase() ==
                    _characteristicUuid) {
                  await c.setNotifyValue(true);
                  _dataSubscription = c.onValueReceived.listen(_onData);
                  if (!completer.isCompleted) completer.complete(true);
                }
              }
            }
          }
          if (!completer.isCompleted) completer.complete(false);
        } catch (e) {
          print('연결 단계 에러: $e');
          if (!completer.isCompleted) completer.complete(false);
        }
      });

      await FlutterBluePlus.startScan(
        withServices: [Guid(_serviceUuid)],
        timeout: const Duration(seconds: 10),
      );

      Future.delayed(const Duration(seconds: 20), () {
        if (!completer.isCompleted) completer.complete(false);
      });

      return await completer.future;
    } catch (e) {
      print('BLE 에러: $e');
      return false;
    }
  }

  void _onData(List<int> raw) {
    final str = utf8.decode(raw);
    final parts = str.split(',');
    if (parts.length < 6) return;

    final body = {
      'sensor_1': int.tryParse(parts[0].trim()) ?? 0,
      'sensor_2': int.tryParse(parts[1].trim()) ?? 0,
      'sensor_3': int.tryParse(parts[2].trim()) ?? 0,
      'sensor_4': int.tryParse(parts[3].trim()) ?? 0,
      'sensor_5': int.tryParse(parts[4].trim()) ?? 0,
      'sensor_6': int.tryParse(parts[5].trim()) ?? 0,
    };

    http.post(
      Uri.parse('${AppConfig.baseUrl}/sensor-data'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    ).catchError((e) {
      print('서버 전송 실패: $e');
      return http.Response('', 500);
    });
  }

  Future<void> disconnect() async {
    _dataSubscription?.cancel();
    _scanSubscription?.cancel();
    await _device?.disconnect();
    _isConnected = false;
    _device = null;
  }
}