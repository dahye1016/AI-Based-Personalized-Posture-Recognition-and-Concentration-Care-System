import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/sensor_frame.dart';
import '../models/sensor_layout.dart';
import '../services/ble_service.dart';
import '../services/target_posture.dart';
import '../theme/app_theme.dart';
import '../widgets/bm.dart';

/// 정자세 측정 전에 센서 연결이 안정적인지 확인하는 화면.
///
/// 통과 조건 ([stableFor] 동안 계속 유지):
/// - 좌석·등받이 보드가 모두 연결되고 데이터가 들어온다 (초당 5프레임 이상)
/// - 앉은 상태에서 좌석 왼쪽·오른쪽 절반 신호가 둘 다 들어온다 (한쪽 절반 0 = 연결 문제)
/// '좌석↔등받이 바꾸기' 저장 키.
const kSwapRolesKey = 'ble_swap_roles';

/// 앱 시작 시 저장된 '좌석↔등받이 바꾸기' 값을 불러온다 (BLE 연결 전에 호출).
Future<void> loadBoardSwap() async {
  try {
    final p = await SharedPreferences.getInstance();
    BleBoard.swapRoles = p.getBool(kSwapRolesKey) ?? true; // 10/27 보드 교체(SW1 그대로) 기준 기본 켜짐
    debugPrint('[BLE] 좌석↔등받이 바꾸기 ${BleBoard.swapRoles ? '켜짐' : '꺼짐'}');
  } catch (_) {}
}

class SensorCheckScreen extends StatefulWidget {
  const SensorCheckScreen({
    super.key,
    required this.ble,
    required this.onNext,
    this.onBack,
    this.onSkip,
    this.stableFor = const Duration(seconds: 3),
  });

  final BleService ble;
  final VoidCallback onNext;
  final VoidCallback? onBack;
  final VoidCallback? onSkip;
  final Duration stableFor;

  @override
  State<SensorCheckScreen> createState() => _SensorCheckScreenState();
}

class _SensorCheckScreenState extends State<SensorCheckScreen> {
  StreamSubscription<SensorFrame>? _seatSub;
  StreamSubscription<SensorFrame>? _backSub;
  Timer? _ticker;

  final List<DateTime> _seatTimes = [];
  final List<DateTime> _backTimes = [];
  SensorFrame? _seat;
  SensorFrame? _back;
  DateTime? _okSince;

  @override
  void initState() {
    super.initState();
    _seatSub = widget.ble.frames.listen((f) {
      _seat = f;
      _seatTimes.add(DateTime.now());
    });
    _backSub = widget.ble.backFrames.listen((f) {
      _back = f;
      _backTimes.add(DateTime.now());
    });
    widget.ble.statusListenable.addListener(_onStatus);
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
  }

  Future<void> _toggleSwap() async {
    BleBoard.swapRoles = !BleBoard.swapRoles;
    debugPrint('[BLE] 좌석↔등받이 바꾸기 ${BleBoard.swapRoles ? '켜짐' : '꺼짐'}');
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(kSwapRolesKey, BleBoard.swapRoles);
    } catch (_) {}
    _okSince = null;
    _seat = null;
    _back = null;
    await widget.ble.disconnect();
    await widget.ble.connect();
    if (mounted) setState(() {});
  }

  void _onStatus() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _seatSub?.cancel();
    _backSub?.cancel();
    widget.ble.statusListenable.removeListener(_onStatus);
    super.dispose();
  }

  static double _fps(List<DateTime> times, DateTime now) {
    times.removeWhere((t) => now.difference(t) > const Duration(seconds: 1));
    return times.length.toDouble();
  }

  // ── 상태 계산 ─────────────────────────────────────────────────
  double _seatFps = 0, _backFps = 0;

  bool get _seatLive =>
      widget.ble.statusOf(BleBoard.seat) == BoardLinkStatus.connected &&
      _seatFps >= 5;
  bool get _backLive =>
      widget.ble.statusOf(BleBoard.back) == BoardLinkStatus.connected &&
      _backFps >= 5;

  int _sum(List<int> idx) {
    final ch = _seat?.channels;
    if (ch == null) return 0;
    var t = 0;
    for (final i in idx) {
      if (i < ch.length) t += ch[i];
    }
    return t;
  }

  int get _seatLeft => _sum(SensorLayout.leftCh);
  int get _seatRight => _sum(SensorLayout.rightCh);
  bool get _seated => _seatLeft + _seatRight >= TargetPostureJudge.emptySum;
  bool get _halfFault {
    final ch = _seat?.channels;
    return ch != null &&
        ch.length >= SensorLayout.nChannels &&
        TargetPostureJudge.halfFault(ch);
  }

  bool get _allOk => _seatLive && _backLive && _seated && !_halfFault;

  bool get _ready =>
      _okSince != null &&
      DateTime.now().difference(_okSince!) >= widget.stableFor;

  void _tick() {
    if (!mounted) return;
    final now = DateTime.now();
    _seatFps = _fps(_seatTimes, now);
    _backFps = _fps(_backTimes, now);
    if (_allOk) {
      _okSince ??= now;
    } else {
      _okSince = null;
    }
    setState(() {});
  }

  /// 지금 가장 먼저 해결할 문제 (없으면 null).
  String? get _problem {
    if (!_seatLive) return '좌석 연결 확인';
    if (_halfFault) return '좌석 연결 확인';
    if (!_backLive) return '등받이 연결 확인';
    if (!_seated) return '의자에 앉아 주세요';
    return null;
  }

  // ── 화면 ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    final left = _ready
        ? 0
        : (_okSince == null
            ? widget.stableFor.inSeconds
            : (widget.stableFor - DateTime.now().difference(_okSince!))
                    .inSeconds +
                1);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: BmScreen(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen, 12, AppSpacing.screen, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap:
                        widget.onBack ?? () => Navigator.of(context).maybePop(),
                    behavior: HitTestBehavior.opaque,
                    child: const Icon(Icons.arrow_back_rounded,
                        color: AppColors.textPrimary),
                  ),
                  const BmPill(label: '센서 연결 확인'),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(
                  AppSpacing.screen, 12, AppSpacing.screen, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('센서 연결을 먼저 확인할게요', style: AppText.display),
                  SizedBox(height: 10),
                  Text('의자에 바르게 앉아 주세요. 좌석과 등받이 신호가 안정적으로 들어오면 정자세 측정으로 넘어가요.',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        color: AppColors.textSecondary,
                      )),
                ],
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
              child: BmSoftCard(
                child: Column(
                  children: [
                    const BmCardCaption(
                      title: '실시간 압력',
                      trailing: '등받이 + 좌석',
                    ),
                    const SizedBox(height: 12),
                    _matGrid('등받이', _back?.channels, _backLive, _backFps, 32),
                    const SizedBox(height: 14),
                    _matGrid('좌석', _seat?.channels, _seatLive, _seatFps, 0),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: BmPill(
                label: problem != null
                    ? '!  $problem'
                    : (_ready ? '✓  센서 연결이 안정적이에요' : '안정 확인 중… $left초'),
                color: problem != null ? AppColors.warnIcon : AppColors.primary,
                bg: problem != null ? AppColors.warnBg : AppColors.primarySoft,
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen, 0, AppSpacing.screen, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BmPrimaryButton(
                    label: '정자세 측정하기',
                    onPressed: _ready ? widget.onNext : null,
                  ),
                  const SizedBox(height: 8),
                  BmGhostButton(
                    label: '센서 다시 연결',
                    onPressed: () {
                      _okSince = null;
                      widget.ble.connect();
                    },
                  ),
                  BmGhostButton(
                    label: BleBoard.swapRoles
                        ? '좌석↔등받이 바꾸기 (켜짐)'
                        : '좌석↔등받이 바꾸기',
                    onPressed: _toggleSwap,
                  ),
                  if (widget.onSkip != null) ...[
                    const SizedBox(height: 4),
                    BmGhostButton(label: '건너뛰기', onPressed: widget.onSkip),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 정자세 측정 화면과 같은 8열 x 4줄 센서 보드. 프레임 최대값으로 0~1 정규화.
  Widget _matGrid(
      String title, List<int>? ch, bool live, double fps, int first) {
    const n = SensorLayout.nChannels;
    var mx = 1;
    if (ch != null) {
      for (var i = 0; i < n && i < ch.length; i++) {
        if (ch[i] > mx) mx = ch[i];
      }
    }
    double lv(int i) =>
        (ch == null || i >= ch.length) ? 0 : (ch[i] / mx).clamp(0.0, 1.0);
    final label = live
        ? '$title · ${fps.toStringAsFixed(0)} fps'
        : '$title (신호 대기)';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: live ? AppColors.textSecondary : AppColors.warnIcon,
            )),
        const SizedBox(height: 6),
        for (var r = 0; r < 4; r++) ...[
          if (r > 0) const SizedBox(height: 6),
          Row(
            children: [
              for (var c = 0; c < 8; c++) ...[
                if (c > 0) const SizedBox(width: 4),
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    height: 22,
                    decoration: BoxDecoration(
                      color: AppColors.heat(lv(r * 8 + c)),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}
