import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config.dart';
import '../models/posture.dart';
import '../services/api_service.dart';
import '../services/ble_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api});
  final ApiService api;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Timer? _timer;
  CurrentPosture? _data;
  String? _error;
  String? _lastAlertedPosture;

  final BleService _ble = BleService();
  bool _bleConnected = false;
  bool _bleConnecting = false;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(AppConfig.pollInterval, (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ble.disconnect();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final data = await widget.api.fetchCurrentPosture();
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
      });
      _maybeAlert(data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _toggleBle() async {
    print('버튼 눌림!');
    if (_bleConnected) {
      await _ble.disconnect();
      setState(() => _bleConnected = false);
    } else {
      setState(() => _bleConnecting = true);
      final ok = await _ble.connect();
      setState(() {
        _bleConnected = ok;
        _bleConnecting = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok ? '✅ ESP32 연결됨!' : '❌ 연결 실패. 다시 시도해주세요.'),
            backgroundColor: ok ? Colors.green : Colors.red,
          ),
        );
      }
    }
  }

  void _maybeAlert(CurrentPosture data) {
    if (data.isBad) {
      if (_lastAlertedPosture != data.posture) {
        _lastAlertedPosture = data.posture;
        HapticFeedback.heavyImpact();
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(
              SnackBar(
                content: Text(data.message),
                backgroundColor: PostureStyle.of(data.posture).color,
                duration: const Duration(seconds: 3),
              ),
            );
        }
      }
    } else {
      _lastAlertedPosture = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('실시간 자세'),
        actions: [
          if (_bleConnecting)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: Icon(
                Icons.bluetooth,
                color: _bleConnected ? Colors.blue : Colors.grey,
              ),
              tooltip: _bleConnected ? 'BLE 연결됨 (탭해서 해제)' : 'ESP32 연결',
              onPressed: _toggleBle,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '새로고침',
            onPressed: _poll,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _poll,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 12),
            if (_bleConnected)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.bluetooth_connected, color: Colors.blue),
                    SizedBox(width: 10),
                    Text('ESP32 센서 연결됨 - 데이터 수신 중'),
                  ],
                ),
              ),
            if (_error != null) _ErrorBanner(message: _error!),
            _PostureCard(data: _data),
            const SizedBox(height: 24),
            _StatusHint(data: _data),
          ],
        ),
      ),
    );
  }
}

class _PostureCard extends StatelessWidget {
  const _PostureCard({required this.data});
  final CurrentPosture? data;

  @override
  Widget build(BuildContext context) {
    if (data == null) {
      return const SizedBox(
        height: 320,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final style = PostureStyle.of(data!.posture);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        color: style.color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: style.color.withOpacity(0.4), width: 2),
      ),
      child: Column(
        children: [
          Icon(style.icon, size: 96, color: style.color),
          const SizedBox(height: 20),
          Text(
            data!.posture,
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.bold,
              color: style.color,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            data!.message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, height: 1.4),
          ),
          if (data!.action != null) ...[
            const SizedBox(height: 16),
            Chip(
              avatar: Icon(Icons.vibration, size: 18, color: style.color),
              label: Text(data!.action!),
              backgroundColor: style.color.withOpacity(0.15),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusHint extends StatelessWidget {
  const _StatusHint({required this.data});
  final CurrentPosture? data;

  @override
  Widget build(BuildContext context) {
    final ts = data?.timestamp;
    final timeText = ts == null
        ? '—'
        : '${ts.hour.toString().padLeft(2, '0')}:'
            '${ts.minute.toString().padLeft(2, '0')}:'
            '${ts.second.toString().padLeft(2, '0')}';
    return Center(
      child: Text(
        '마지막 갱신 $timeText · ${AppConfig.pollInterval.inSeconds}초마다 자동 확인',
        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off, color: Colors.red),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '서버에 연결할 수 없어요.\n$message',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}



/* import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config.dart';
import '../models/posture.dart';
import '../services/api_service.dart';

/// 실시간 자세 화면.
/// - 주기적으로 /current-posture 폴링
/// - 나쁜 자세가 새로 감지되면 진동 + 스낵바로 교정 알림
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api});
  final ApiService api;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Timer? _timer;
  CurrentPosture? _data;
  String? _error;
  String? _lastAlertedPosture; // 같은 나쁜 자세 반복 알림 방지

  @override
  void initState() {
    super.initState();
    _poll(); // 즉시 1회
    _timer = Timer.periodic(AppConfig.pollInterval, (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final data = await widget.api.fetchCurrentPosture();
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
      });
      _maybeAlert(data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  /// 나쁜 자세가 "새로" 감지된 순간에만 진동 + 알림
  void _maybeAlert(CurrentPosture data) {
    if (data.isBad) {
      if (_lastAlertedPosture != data.posture) {
        _lastAlertedPosture = data.posture;
        HapticFeedback.heavyImpact(); // 진동 알림
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(
              SnackBar(
                content: Text(data.message),
                backgroundColor: PostureStyle.of(data.posture).color,
                duration: const Duration(seconds: 3),
              ),
            );
        }
      }
    } else {
      _lastAlertedPosture = null; // 바른자세로 돌아오면 리셋
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('실시간 자세'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '새로고침',
            onPressed: _poll,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _poll,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 12),
            if (_error != null) _ErrorBanner(message: _error!),
            _PostureCard(data: _data),
            const SizedBox(height: 24),
            _StatusHint(data: _data),
          ],
        ),
      ),
    );
  }
}

/// 큰 자세 표시 카드
class _PostureCard extends StatelessWidget {
  const _PostureCard({required this.data});
  final CurrentPosture? data;

  @override
  Widget build(BuildContext context) {
    if (data == null) {
      return const SizedBox(
        height: 320,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final style = PostureStyle.of(data!.posture);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        color: style.color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: style.color.withOpacity(0.4), width: 2),
      ),
      child: Column(
        children: [
          Icon(style.icon, size: 96, color: style.color),
          const SizedBox(height: 20),
          Text(
            data!.posture,
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.bold,
              color: style.color,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            data!.message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, height: 1.4),
          ),
          if (data!.action != null) ...[
            const SizedBox(height: 16),
            Chip(
              avatar: Icon(Icons.vibration, size: 18, color: style.color),
              label: Text(data!.action!),
              backgroundColor: style.color.withOpacity(0.15),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusHint extends StatelessWidget {
  const _StatusHint({required this.data});
  final CurrentPosture? data;

  @override
  Widget build(BuildContext context) {
    final ts = data?.timestamp;
    final timeText = ts == null
        ? '—'
        : '${ts.hour.toString().padLeft(2, '0')}:'
            '${ts.minute.toString().padLeft(2, '0')}:'
            '${ts.second.toString().padLeft(2, '0')}';
    return Center(
      child: Text(
        '마지막 갱신 $timeText · ${AppConfig.pollInterval.inSeconds}초마다 자동 확인',
        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off, color: Colors.red),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '서버에 연결할 수 없어요.\n$message',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
 */