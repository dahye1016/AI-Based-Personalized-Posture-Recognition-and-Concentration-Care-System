import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../models/sensor_frame.dart';
import '../models/sensor_layout.dart';

/// 좌석(`BleService.frames`)과 등받이(`BleService.backFrames`) 32ch 프레임을
/// 64ch 프레임 하나로 합친다. 두 보드는 시계가 따로라 타임스탬프 동기화는 하지 않고,
/// **앱 수신 시각([SensorFrame.receivedAt]) 기준 100ms 버킷**으로 묶는다.
///
/// 규칙 (팀 결정):
///   · 버킷마다 각 보드의 가장 최근 값을 쓴다. 이번 버킷에 없으면 직전 값을 유지한다.
///   · 한쪽이 500ms 이상 안 들어오면 그 구간은 내보내지 않는다. ★ 0 으로 채우지 않는다
///     — 등받이 0 은 "앞으로 숙이기/등 뗌"처럼 실제 자세로 읽힌다.
///   · 좌석이 끊긴 상태(최신값 없음/오래됨)면 출력 없음. 등받이도 마찬가지.
///   · 두 보드 모두 이번 버킷에 갱신이 없으면 내보내지 않는다 — 판정 안정화가
///     "N프레임 연속"으로 세므로 중복 프레임이 들어가면 실제보다 빨리 확정된다.
///   · 출력 채널: 좌석 ch0~31 + 등받이 ch32~63 (등받이 보드 ch0 → 64ch 의 ch32).
///
/// 아직 아무 데도 연결하지 않는다 (8클래스 모델 교체 묶음 때 연결).
class FrameMerger {
  FrameMerger(
    Stream<SensorFrame> seat,
    Stream<SensorFrame> back, {
    Duration bucket = const Duration(milliseconds: 100),
    Duration staleAfter = const Duration(milliseconds: 500),
    DateTime Function() clock = DateTime.now,
    Stream<DateTime>? ticks,
  }) : _core = FrameMergeCore(staleAfter: staleAfter) {
    _seatSub = seat.listen(_core.addSeat);
    _backSub = back.listen(_core.addBack);
    final tickStream = ticks ??
        Stream<DateTime>.periodic(bucket, (_) => clock());
    _tickSub = tickStream.listen((now) {
      final f = _core.tick(now);
      if (f != null && !_out.isClosed) _out.add(f);
    });
  }

  final FrameMergeCore _core;
  final StreamController<SensorFrame> _out =
      StreamController<SensorFrame>.broadcast();
  late final StreamSubscription<SensorFrame> _seatSub;
  late final StreamSubscription<SensorFrame> _backSub;
  late final StreamSubscription<DateTime> _tickSub;

  /// 병합된 64ch 프레임.
  Stream<SensorFrame> get frames => _out.stream;

  Future<void> dispose() async {
    await _tickSub.cancel();
    await _seatSub.cancel();
    await _backSub.cancel();
    await _out.close();
  }
}

/// 병합 규칙만 담은 순수 로직 (타이머 없음). 시각은 호출하는 쪽이 넣는다.
class FrameMergeCore {
  FrameMergeCore({this.staleAfter = const Duration(milliseconds: 500)});

  /// 이보다 오래 안 들어온 보드가 있으면 출력하지 않는다.
  final Duration staleAfter;

  static const int _boardChannels = SensorLayout.nChannels; // 32
  static const int _outChannels = SensorLayout.nAllChannels; // 64

  SensorFrame? _seat;
  SensorFrame? _back;
  bool _seatUpdated = false;
  bool _backUpdated = false;
  int _seq = 0;

  void addSeat(SensorFrame f) {
    if (!_valid(f, 'seat')) return;
    _seat = f;
    _seatUpdated = true;
  }

  void addBack(SensorFrame f) {
    if (!_valid(f, 'back')) return;
    _back = f;
    _backUpdated = true;
  }

  /// 버킷 하나를 닫는다. 내보낼 64ch 프레임이 있으면 돌려주고, 없으면 null.
  SensorFrame? tick(DateTime now) {
    final updated = _seatUpdated || _backUpdated;
    _seatUpdated = false;
    _backUpdated = false;

    final seat = _seat;
    final back = _back;
    if (seat == null || back == null) return null;
    if (_isStale(seat, now) || _isStale(back, now)) return null;
    if (!updated) return null;

    final channels = List<int>.filled(_outChannels, 0);
    channels.setRange(0, _boardChannels, seat.channels);
    channels.setRange(
        SensorLayout.backFirstCh, _outChannels, back.channels);

    final f = SensorFrame(frameNo: _seq, channels: channels, receivedAt: now);
    _seq = (_seq + 1) & 0xFFFF;
    return f;
  }

  bool _isStale(SensorFrame f, DateTime now) =>
      now.difference(f.receivedAt) >= staleAfter;

  bool _valid(SensorFrame f, String tag) {
    if (f.channels.length == _boardChannels) return true;
    debugPrint('[MERGE $tag] 채널 수 ${f.channels.length} (기대 $_boardChannels) — 무시');
    return false;
  }
}
