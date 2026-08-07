import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config.dart';
import '../models/posture.dart';
import '../services/api_service.dart';
import '../widgets/seat_heatmap.dart';
import 'calibration_screen.dart';

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

  SensorLayout? _layout;
  HeatmapFrame? _heatmap;
  Timer? _heatTimer;
  bool _calibrated = false;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(AppConfig.pollInterval, (_) => _poll());
    _heatTimer =
        Timer.periodic(AppConfig.heatmapInterval, (_) => _pollHeatmap());
    _loadLayout();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _heatTimer?.cancel();
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

  /// 센서 물리 배치를 한 번만 받아옵니다 (히트맵 그리기용)
  Future<void> _loadLayout() async {
    try {
      final layout = await widget.api.fetchLayout();
      final calib = await widget.api.fetchCalibration();
      if (!mounted) return;
      setState(() {
        _layout = layout;
        _calibrated = calib.complete;
      });
    } catch (_) {/* 서버가 아직 안 떴을 수 있음 — 폴링이 알아서 재시도 */}
  }

  Future<void> _pollHeatmap() async {
    if (_layout == null) return;
    try {
      final h = await widget.api.fetchHeatmap();
      if (mounted) setState(() => _heatmap = h);
    } catch (_) {/* 조용히 무시 */}
  }

  Future<void> _openCalibration() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CalibrationScreen(api: widget.api),
    ));
    _loadLayout();
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
          IconButton(
            icon: Icon(
              Icons.tune,
              color: _calibrated ? const Color(0xFF2E9E6B) : Colors.orange,
            ),
            tooltip: _calibrated ? '자세 재보정' : '자세 등록이 필요해요',
            onPressed: _openCalibration,
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
            if (!_calibrated)
              InkWell(
                onTap: _openCalibration,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withOpacity(0.5)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.tune, color: Colors.orange),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text('자세를 등록하면 훨씬 정확해져요. 탭해서 등록하기'),
                      ),
                      Icon(Icons.chevron_right, color: Colors.orange),
                    ],
                  ),
                ),
              ),
            if (_layout != null) ...[
              SeatHeatmap(
                layout: _layout!,
                channels: _heatmap?.channels ?? const [],
                cof: _data == null ? null : Offset(_data!.cofX, _data!.cofY),
              ),
              const SizedBox(height: 20),
            ],
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