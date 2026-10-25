import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/posture.dart';
import '../services/api_service.dart';
import '../services/ble_service.dart';
import '../models/posture_alert.dart';
import '../models/posture_class.dart';
import '../models/sensor_frame.dart';
import '../models/sensor_layout.dart';
import '../services/alert_store.dart';
import '../services/posture_model.dart';
import '../services/sitting_stats.dart';
import '../theme/app_theme.dart';
import '../widgets/bm.dart';
import '../widgets/seat_heatmap.dart';
import 'alert_history_screen.dart';
import 'posture_alert_screen.dart';
import 'settings_screen.dart';
import 'stretch_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api, this.ble});
  final ApiService api;

  /// 앱 전체가 공유하는 센서 연결. null 이면 이 화면이 직접 만들고 닫을 때 끊는다.
  final BleService? ble;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {

  late final BleService _ble = widget.ble ?? BleService();

  /// 이 화면이 직접 만든 연결인지. 공유 연결이면 화면을 닫아도 끊지 않는다.
  bool get _ownsBle => widget.ble == null;
  bool _bleConnecting = false;

  // ── 실시간 히트맵 (BLE 전용, 서버 무관) ──────────────────────────
  StreamSubscription<SensorFrame>? _frameSub;
  Timer? _fpsTimer;
  SensorFrame? _lastFrame;
  final List<DateTime> _recvTimes = []; // 최근 1초 수신 시각 → fps
  double _fps = 0;
  bool _showIndex = false;

  // 등받이 보드 (표시·진단 전용 — 판정은 좌석 32ch 만 쓴다)
  StreamSubscription<SensorFrame>? _backSub;
  SensorFrame? _lastBackFrame;
  final List<DateTime> _backRecvTimes = [];
  double _backFps = 0;

  // ── 온디바이스 자세 판정 (assets/model 의 TFLite) ────────────────
  /// 모델 로드 전에는 null. 로드 실패하면 계속 null 이고 [_modelError] 에 원인이 담긴다.
  PostureModel? _model;

  /// 다수결로 안정화된 최신 판정. 아직 없으면 null (= 대기 중).
  PostureClass? _posture;

  /// 모델 로드 실패 원인. null 이면 정상.
  String? _modelError;

  // ── 나쁜 자세 알림 (기준 시간: [PostureAlertScreen.threshold]) ─────
  /// 프레임이 이보다 오래 끊겼다 다시 들어오면 지속 시간을 처음부터 잰다.
  /// (끊긴 동안의 자세는 모르므로 공백을 '유지'로 치지 않는다.)
  static const Duration _frameGapReset = Duration(milliseconds: 2000);

  /// 지금 이어지고 있는 나쁜 자세의 종류. 자세가 바뀌면 시간을 다시 잰다.
  PostureClass? _badPosture;

  /// 나쁜 자세가 이어지기 시작한 시각 (프레임 수신 시각 기준).
  DateTime? _badSince;

  /// 이 에피소드에 대해 이미 알림을 띄웠는지 (자세 이름으로 구분).
  PostureClass? _alertedFor;

  /// 알림 화면이 떠 있는 동안 중복으로 띄우지 않기 위한 잠금.
  bool _alertOpen = false;

  /// 오늘 몇 번째 알림인지. 보관 한도(4건)와 무관하게 계속 센다.
  int _todayAlerts = 0;

  @override
  void initState() {
    super.initState();
    _loadModel();
    // BLE 프레임 구독 + fps 감쇠 타이머
    _frameSub = _ble.frames.listen(_onFrame);
    _backSub = _ble.backFrames.listen(_onBackFrame);
    _ble.statusListenable.addListener(_onBleStatus);
    _fpsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      _recvTimes.removeWhere((t) => now.difference(t).inMilliseconds > 1000);
      _backRecvTimes
          .removeWhere((t) => now.difference(t).inMilliseconds > 1000);
      if (mounted) {
        setState(() {
          _fps = _recvTimes.length.toDouble();
          _backFps = _backRecvTimes.length.toDouble();
        });
      }
    });
    // 화면에 들어오면 좌석·등받이 센서를 이름(PoseLab-Seat/Back)으로 바로 찾는다.
    WidgetsBinding.instance.addPostFrameCallback((_) => _connectSensors());
  }

  void _onBleStatus() {
    if (mounted) setState(() {});
  }

  void _onBackFrame(SensorFrame f) {
    _backRecvTimes.add(f.receivedAt);
    if (!mounted) return;
    setState(() => _lastBackFrame = f);
  }

  /// TFLite 모델과 정규화 값을 읽는다.
  /// 실패해도 화면은 그대로 뜨고 [_modelError] 만 채워진다 (히트맵은 계속 동작).
  Future<void> _loadModel() async {
    try {
      final m = await PostureModel.load();
      if (!mounted) {
        m.dispose();
        return;
      }
      setState(() => _model = m);
    } catch (e) {
      debugPrint('[Posture] 모델 로드 실패: $e');
      if (mounted) setState(() => _modelError = '$e');
    }
  }

  void _onFrame(SensorFrame f) {
    final now = f.receivedAt;
    _recvTimes.add(now);
    _recvTimes.removeWhere((t) => now.difference(t).inMilliseconds > 1000);
    if (!mounted) return;
    final prevAt = _lastFrame?.receivedAt;
    if (prevAt != null && now.difference(prevAt) > _frameGapReset) _resetBad();
    final p = _model?.predict(f);
    if (p != null) SittingStats.instance.record(p, f.receivedAt);
    setState(() {
      _lastFrame = f;
      _fps = _recvTimes.length.toDouble();
      if (p != null) _posture = p;
    });
    // predict 가 null 인 프레임(채널 수 불일치·모델 미로드)은 판정이 없으므로
    // 알림 타이머를 건드리지 않는다.
    if (p != null) _trackBad(p, now);
  }

  /// 나쁜 자세 지속 시간을 잰다. 나쁜 자세가 새로 시작되거나 다른 나쁜
  /// 자세로 바뀌면 처음부터 다시 재고 진동한다 (REQ-F-05).
  void _trackBad(PostureClass p, DateTime at) {
    if (!p.isBad) {
      _resetBad();
      return;
    }
    if (_badPosture != p) {
      _badPosture = p;
      _badSince = at;
      HapticFeedback.mediumImpact();
    }
    _maybeAlert(p, at);
  }

  void _resetBad() {
    _badPosture = null;
    _badSince = null;
    _alertedFor = null;
  }

  /// 같은 나쁜 자세가 [PostureAlertScreen.threshold] 넘게 이어지면
  /// 알림 화면을 띄우고 기록으로 남긴다. 기록은 최근 4건만 보관된다(AlertStore).
  void _maybeAlert(PostureClass p, DateTime at) {
    final since = _badSince;
    if (since == null) return;
    if (_alertedFor == p) return; // 이 에피소드는 이미 알렸다

    final held = at.difference(since);
    if (held < PostureAlertScreen.threshold) return;

    _alertedFor = p;
    _todayAlerts++;

    final alert = PostureAlert(posture: p, heldFor: held, at: at);
    AlertStore.instance.add(alert);

    if (!mounted || _alertOpen) return;
    _alertOpen = true;
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => PostureAlertScreen(
            alert: alert,
            todayCount: _todayAlerts,
          ),
        ))
        .then((_) {
      if (mounted) _alertOpen = false;
    });
  }

  @override
  void dispose() {
    _frameSub?.cancel();
    _backSub?.cancel();
    _ble.statusListenable.removeListener(_onBleStatus);
    _fpsTimer?.cancel();
    _model?.dispose();
    if (_ownsBle) _ble.disconnect();
    super.dispose();
  }

  /// 센서가 하나라도 연결(또는 탐색) 중이면 끊고, 아니면 다시 찾는다.
  Future<void> _toggleBle() async {
    final active = _ble.statusOf(BleBoard.seat) != BoardLinkStatus.off ||
        _ble.statusOf(BleBoard.back) != BoardLinkStatus.off;
    if (active && !_bleConnecting) {
      await _ble.disconnect();
      // 다시 붙었을 때 끊기기 직전 판정이 다수결에 남지 않게 한다.
      _model?.reset();
      _resetBad(); // 끊긴 동안의 자세는 모르므로 다시 붙으면 처음부터 잰다.
      setState(() {
        _posture = null;
        _lastFrame = null;
        _lastBackFrame = null;
      });
    } else {
      await _connectSensors(showResult: true);
    }
  }

  /// 좌석·등받이를 함께 찾는다. 좌석 결과가 나오면 돌아오고,
  /// 등받이는 못 찾았으면 BleService 가 뒤에서 계속 재시도한다.
  Future<void> _connectSensors({bool showResult = false}) async {
    if (_bleConnecting) return;
    setState(() => _bleConnecting = true);
    final ok = await _ble.connect();
    if (!mounted) return;
    setState(() {
      _bleConnecting = false;
    });
    if (!showResult) return;
    final back = _ble.isBackConnected;
    final msg = ok && back
        ? '좌석·등받이 센서가 연결됐어요'
        : ok
            ? '좌석 센서가 연결됐어요. 등받이 센서는 계속 찾고 있어요'
            : '좌석 센서(PoseLab-Seat)를 찾지 못했어요. 전원을 확인해 주세요';
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── 표시용 계산 ────────────────────────────────────────────

  /// 화면에 쓰는 판정. 아직 없으면 waiting(연결 중) 으로 본다.
  PostureClass get _shown => _posture ?? PostureClass.waiting;

  bool get _isBad => _posture?.isBad ?? false;

  /// 상태별 상단 배너. 연결 중(waiting)에는 배너를 띄우지 않는다.
  Widget? get _banner {
    if (_isBad) {
      return _WarnBanner(
        title: '${_shown.label} 자세가 감지됐어요!',
        body: _shown.message,
      );
    }
    switch (_shown) {
      case PostureClass.straight:
        return const _GoodBanner(
          title: '자세가 아주 좋아요!',
          body: '바른 자세를 유지하고 있어요',
        );
      case PostureClass.notSitting:
        // 자리 비움은 경고 배너 모양만 빌려 쓴다.
        return const _WarnBanner(
          title: '자리를 비웠어요',
          body: '돌아와서 앉으면 다시 측정을 시작해요',
        );
      default:
        return null;
    }
  }

  /// 자세 카드 부제. 모델 상태가 정상이 아니면 그 원인을 대신 보여준다.
  String get _cardMessage {
    if (_modelError != null) return '모델 로드 실패: $_modelError';
    if (_model == null) return '모델 불러오는 중…';
    if (_shown == PostureClass.notSitting) return '착석이 감지되지 않아요';
    return _shown.message;
  }

  /// 자세 카드 안의 행동 버튼. 나쁜 자세·자리 비움일 때만 둔다.
  Widget? get _cardButton {
    if (_isBad || _shown == PostureClass.notSitting) {
      return _CardButton(
        label: '스트레칭 하러 가기',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const StretchScreen()),
        ),
      );
    }
    return null;
  }

  /// 센서 한 대의 상태 칩. 이름 기준으로 연결된 보드([BleBoard])별로 따로 그린다.
  Widget _sensorChip(String label, BleBoard board, double fps) {
    final st = _ble.statusOf(board);
    final String text;
    final Color color;
    final Color bg;
    if (st == BoardLinkStatus.connected && fps > 0) {
      text = '$label LIVE';
      color = AppColors.primary;
      bg = AppColors.primarySoft;
    } else if (st == BoardLinkStatus.connected) {
      text = '$label 데이터 없음';
      color = AppColors.warnIcon;
      bg = AppColors.warnBg;
    } else if (st == BoardLinkStatus.searching) {
      text = '$label 찾는 중';
      color = AppColors.textSecondary;
      bg = AppColors.surface;
    } else {
      text = '$label 꺼짐';
      color = AppColors.textTertiary;
      bg = AppColors.surface;
    }
    return BmPill(label: text, color: color, bg: bg, dot: true);
  }

  /// 헤더 아래 센서 상태 줄 — 좌석 / 등받이 + 연결·해제 버튼.
  Widget get _sensorRow {
    final active = _ble.statusOf(BleBoard.seat) != BoardLinkStatus.off ||
        _ble.statusOf(BleBoard.back) != BoardLinkStatus.off;
    return Row(
      children: [
        _sensorChip('좌석', BleBoard.seat, _fps),
        const SizedBox(width: 6),
        _sensorChip('등받이', BleBoard.back, _backFps),
        const Spacer(),
        if (_bleConnecting)
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          GestureDetector(
            onTap: _toggleBle,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Text(active ? '연결 해제' : '센서 연결',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  )),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: BmScreen(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BmHeader(
              eyebrow: '자세케어',
              title: '실시간 자세',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const AlertHistoryScreen()),
                    ),
                    icon: const Icon(Icons.notifications_none_rounded,
                        size: 22, color: AppColors.textTertiary),
                    tooltip: '알림 기록',
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const SettingsScreen()),
                    ),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text('설정',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          )),
                    ),
                  ),
                ],
              ),
            ),

            // ── 센서 상태 (좌석 / 등받이) ──────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen, 0, AppSpacing.screen, 12),
              child: _sensorRow,
            ),

            // ── 상태 배너 ─────────────────────────
            if (_banner != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screen, 0, AppSpacing.screen, 14),
                child: _banner,
              ),

            // ── 현재 자세 카드 ────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen, 0, AppSpacing.screen, 14),
              child: BmCard(
                child: Column(
                  children: [
                    Row(
                      children: [
                        _PostureIcon(color: _shown.color, bad: _isBad),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_shown.label,
                                  style:
                                      AppText.display.copyWith(fontSize: 26)),
                              const SizedBox(height: 4),
                              Text(_cardMessage,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.caption.copyWith(height: 1.4)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_cardButton != null) ...[
                      const SizedBox(height: 14),
                      _cardButton!,
                    ],
                  ],
                ),
              ),
            ),

            // ── 압력 분포 ────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen, 0, AppSpacing.screen, 14),
              child: BmSoftCard(
                child: Column(
                  children: [
                    BmCardCaption(
                      title: '압력 분포',
                      trailing: _pressureSummary,
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                          _lastBackFrame == null
                              ? '등받이 · 위 어깨 → 아래 허리 (센서 대기)'
                              : '등받이 · 위 어깨 → 아래 허리',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textTertiary,
                          )),
                    ),
                    const SizedBox(height: 8),
                    _HeatGrid(grid: _backHeatGrid),
                    const SizedBox(height: 14),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('좌석 · 위 엉덩이 → 아래 무릎',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textTertiary,
                          )),
                    ),
                    const SizedBox(height: 8),
                    // 채널 번호를 켜면 좌표계 검증용 SeatHeatmap 으로 바꿔 그린다.
                    if (_showIndex)
                      SeatHeatmap(
                        channels: _lastFrame?.channels ?? const [],
                        showIndex: true,
                      )
                    else
                      _HeatGrid(grid: _heatGrid),
                    const SizedBox(height: 10),
                    _buildDiagnostics(),
                  ],
                ),
              ),
            ),

            const Spacer(),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  /// 압력 카드 하단 진단 줄 — frameNo·fps 와 채널 번호 토글.
  Widget _buildDiagnostics() {
    return Row(
      children: [
        Expanded(
          child: Text(
            '좌석 #${_lastFrame?.frameNo ?? '—'} · ${_fps.toStringAsFixed(0)}fps   '
            '등받이 #${_lastBackFrame?.frameNo ?? '—'} · ${_backFps.toStringAsFixed(0)}fps',
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary,
            ),
          ),
        ),
        const Text('채널 번호',
            style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
        Switch(
          value: _showIndex,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onChanged: (v) => setState(() => _showIndex = v),
        ),
      ],
    );
  }

  // ── 아로 디자인 이식용 헬퍼 (feat/aro #16) ─────────────────────────
  // PostureLayout 대신 SensorLayout 으로 조립한다.

  /// 물리 행 순서 — 뒤(엉덩이) → 가운데(허벅지) → 앞(무릎). 10 / 14 / 8.
  static const List<List<int>> _rows = [
    SensorLayout.hipCh,
    SensorLayout.thighCh,
    SensorLayout.kneeCh,
  ];

  /// 전체 채널. 총압·정규화는 이걸 쓴다.
  static const List<int> _all = [
    ...SensorLayout.hipCh,
    ...SensorLayout.thighCh,
    ...SensorLayout.kneeCh,
  ];

  /// 현재 프레임의 채널값. 프레임이 없으면 빈 리스트.
  List<int> get _frame => _lastFrame?.channels ?? const [];

  /// 현재 프레임에서 주어진 채널들의 합.
  double _sum(List<int> idx) {
    var s = 0.0;
    for (final i in idx) {
      if (i < _frame.length) s += _frame[i];
    }
    return s;
  }

  /// 압력 분포 카드의 오른쪽 상태 요약. 구역 구분은 [SensorLayout] 을 쓴다.
  String get _pressureSummary {
    final posture = _posture ?? PostureClass.waiting;
    if (posture == PostureClass.waiting ||
        _frame.length < SensorLayout.nChannels) {
      return '신호 대기 중';
    }
    if (posture == PostureClass.notSitting) {
      return '압력이 감지되지 않아요';
    }

    final total = _sum(_all);
    if (total <= 0) return '압력이 감지되지 않아요';

    final l = _sum(SensorLayout.leftCh);
    final r = _sum(SensorLayout.rightCh);
    final lr = l + r;

    switch (posture) {
      case PostureClass.straight:
        if (lr <= 0) return '압력이 감지되지 않아요';
        final balance = 100 - ((l - r).abs() / lr * 100);
        return '좌우 균형 ${balance.round()}%';
      case PostureClass.leanForward:
        return '무릎 쪽 하중 ${(_sum(SensorLayout.kneeCh) / total * 100).round()}%';
      case PostureClass.leanBack:
        return '엉덩이 쪽 하중 ${(_sum(SensorLayout.hipCh) / total * 100).round()}%';
      default:
        // 다리 꼬기(잠정값)와 좌우 기울임 — 좌우 비중으로 보여준다.
        if (lr <= 0) return '압력이 감지되지 않아요';
        return '좌 ${(l / lr * 100).round()}% · 우 ${(r / lr * 100).round()}%';
    }
  }

  /// 방석 32채널을 물리 배치 그대로 0~1 로 정규화한 값.
  /// 프레임이 없으면 전부 0. 행 구성은 [_rows] (10 / 14 / 8).
  List<List<double>> get _heatGrid {
    final grid = [
      for (final row in _rows) List<double>.filled(row.length, 0),
    ];
    if (_frame.length < SensorLayout.nChannels) return grid;

    var maxV = 0;
    for (final i in _all) {
      if (_frame[i] > maxV) maxV = _frame[i];
    }
    if (maxV <= 0) return grid;

    for (var r = 0; r < _rows.length; r++) {
      final row = _rows[r];
      for (var c = 0; c < row.length; c++) {
        grid[r][c] = _frame[row[c]] / maxV;
      }
    }
    return grid;
  }

  /// 등받이 32채널을 [SensorLayout.backDisplayRows] 순서(어깨 → 중간 → 허리,
  /// 각 줄 Right → Left)로 0~1 정규화한 값. 등받이 자체 최댓값 기준.
  /// 등받이 보드 프레임은 ch0~31 이므로 64ch 번호에서 backFirstCh 를 빼서 읽는다.
  List<List<double>> get _backHeatGrid {
    const rows = SensorLayout.backDisplayRows;
    final grid = [for (final row in rows) List<double>.filled(row.length, 0)];
    final back = _lastBackFrame?.channels ?? const <int>[];
    if (back.length < SensorLayout.nBackChannels) return grid;

    var maxV = 0;
    for (final v in back) {
      if (v > maxV) maxV = v;
    }
    if (maxV <= 0) return grid;

    for (var r = 0; r < rows.length; r++) {
      for (var c = 0; c < rows[r].length; c++) {
        grid[r][c] = back[rows[r][c] - SensorLayout.backFirstCh] / maxV;
      }
    }
    return grid;
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

// ── 아로 디자인 부속 위젯 (feat/aro #16 원본 그대로) ─────────────────

/// 주황 경고 배너.
class _WarnBanner extends StatelessWidget {
  const _WarnBanner({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warnBg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.warnIcon,
              shape: BoxShape.circle,
            ),
            child: const Text('!',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                )),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    )),
                const SizedBox(height: 3),
                Text(body,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: AppColors.textSecondary,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 민트 정자세 배너.
class _GoodBanner extends StatelessWidget {
  const _GoodBanner({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.postureGood,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded,
                size: 20, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    )),
                const SizedBox(height: 3),
                Text(body,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: AppColors.textSecondary,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 자세 카드 안의 행동 버튼. 모양은 기존 버튼 그대로(민트 옅은 배경).
class _CardButton extends StatelessWidget {
  const _CardButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.primarySoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            )),
      ),
    );
  }
}

/// 자세 픽토그램 — 나쁜 자세면 고개가 앞으로 나온 모양.
class _PostureIcon extends StatelessWidget {
  const _PostureIcon({required this.color, required this.bad});

  final Color color;
  final bool bad;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        // ignore: deprecated_member_use
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            left: bad ? 27 : 21,
            top: 11,
            child: Container(
              width: 15,
              height: 15,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
          Positioned(
            left: 13,
            top: 30,
            child: Container(
              width: 13,
              height: 17,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 압력 히트맵. 행 구성은 [_HomeScreenState._rows] 를 그대로 따른다.
/// 행마다 셀 개수가 달라도(10/14/8) 각 행이 카드 폭을 꽉 채운다.
class _HeatGrid extends StatelessWidget {
  const _HeatGrid({required this.grid});

  final List<List<double>> grid;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (var r = 0; r < grid.length; r++) ...[
            if (r > 0) const SizedBox(height: 8),
            Row(
              children: [
                for (var c = 0; c < grid[r].length; c++) ...[
                  if (c > 0) const SizedBox(width: 3),
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 26,
                      decoration: BoxDecoration(
                        color: AppColors.heat(grid[r][c].clamp(0.0, 1.0)),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
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