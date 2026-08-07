import 'dart:async';
import 'package:flutter/material.dart';
import '../config.dart';
import '../models/posture.dart';
import '../services/api_service.dart';
import '../widgets/seat_heatmap.dart';

/// 초기 설정 > 자세 등록 화면.
///
/// 시안의 "각 자세로 앉은 뒤 버튼을 눌러주세요" 화면입니다.
/// 여기서 등록한 값이 서버의 nearest-centroid 판정 기준이 되고,
/// 그래서 사람마다 다른 체형/습관에 맞는 판정이 가능해집니다.
/// (등록 전에는 서버가 규칙 기반 폴백으로 동작합니다)
class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key, required this.api});
  final ApiService api;

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  static const _countdown = 3; // 초

  SensorLayout? _layout;
  HeatmapFrame? _frame;
  Set<String> _registered = {};
  Timer? _preview;

  int _current = 0;
  int _remaining = 0;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
    _preview = Timer.periodic(AppConfig.heatmapInterval, (_) => _refreshFrame());
  }

  @override
  void dispose() {
    _preview?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final layout = await widget.api.fetchLayout();
      final status = await widget.api.fetchCalibration();
      if (!mounted) return;
      setState(() {
        _layout = layout;
        _registered = status.registered.toSet();
        _current = AppConfig.calibrationLabels
            .indexWhere((l) => !_registered.contains(l))
            .clamp(0, AppConfig.calibrationLabels.length - 1);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _refreshFrame() async {
    try {
      final f = await widget.api.fetchHeatmap();
      if (mounted) setState(() => _frame = f);
    } catch (_) {/* 미리보기라 조용히 무시 */}
  }

  /// 카운트다운 후 현재 프레임을 기준 자세로 등록
  Future<void> _register(String label) async {
    setState(() {
      _busy = true;
      _error = null;
      _remaining = _countdown;
    });

    for (var i = _countdown; i > 0; i--) {
      if (!mounted) return;
      setState(() => _remaining = i);
      await Future.delayed(const Duration(seconds: 1));
    }

    try {
      final ok = await widget.api.registerCalibration(label);
      if (!mounted) return;
      if (ok) {
        setState(() {
          _registered.add(label);
          final next = AppConfig.calibrationLabels
              .indexWhere((l) => !_registered.contains(l));
          if (next >= 0) _current = next;
        });
      } else {
        setState(() => _error = '등록에 실패했어요. 다시 시도해주세요.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    await widget.api.resetCalibration();
    if (mounted) {
      setState(() {
        _registered = {};
        _current = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final labels = AppConfig.calibrationLabels;
    final done = _registered.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('자세 등록'),
        actions: [
          if (done > 0)
            TextButton(onPressed: _reset, child: const Text('재보정')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 진행 표시
          Row(
            children: List.generate(labels.length, (i) {
              final filled = _registered.contains(labels[i]);
              return Expanded(
                child: Container(
                  height: 4,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: filled
                        ? const Color(0xFF2E9E6B)
                        : Colors.grey.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 20),
          Text('$done / ${labels.length} 완료',
              style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 6),
          const Text('각 자세로 앉은 뒤 버튼을 눌러주세요',
              style: TextStyle(fontSize: 15)),
          const SizedBox(height: 20),

          // 실시간 미리보기 — 지금 앉은 모양이 그대로 보입니다
          if (_layout != null)
            SeatHeatmap(
              layout: _layout!,
              channels: _frame?.channels ?? const [],
              showValues: true,
            )
          else
            const SizedBox(
              height: 160,
              child: Center(child: CircularProgressIndicator()),
            ),
          const SizedBox(height: 20),

          // 자세 목록
          ...List.generate(labels.length, (i) {
            final label = labels[i];
            final isDone = _registered.contains(label);
            final isCurrent = i == _current;
            return Card(
              elevation: 0,
              color: isCurrent
                  ? const Color(0xFF1B3A5C).withOpacity(0.15)
                  : Colors.transparent,
              child: ListTile(
                leading: Icon(
                  isDone ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: isDone ? const Color(0xFF2E9E6B) : Colors.grey,
                ),
                title: Text(label),
                trailing: isDone
                    ? const Text('완료')
                    : (isCurrent && _busy
                        ? Text('$_remaining초',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold))
                        : null),
                onTap: _busy ? null : () => setState(() => _current = i),
              ),
            );
          }),

          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ],

          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy || _layout == null
                ? null
                : () => _register(labels[_current]),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            child: Text(_busy
                ? '측정 중... $_remaining'
                : "'${labels[_current]}' 자세로 등록"),
          ),
        ],
      ),
    );
  }
}
