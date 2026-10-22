import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:posturecare_ai/models/sensor_frame.dart';
import 'package:posturecare_ai/services/frame_merger.dart';

/// 기준 시각 + ms.
final DateTime _t0 = DateTime(2026, 10, 22, 12);
DateTime _at(int ms) => _t0.add(Duration(milliseconds: ms));

/// 32ch 프레임. 채널 i 값 = base + i (좌석/등받이 구분용).
SensorFrame _frame(int ms, int base, {int n = 32}) => SensorFrame(
      frameNo: ms,
      channels: List<int>.generate(n, (i) => base + i),
      receivedAt: _at(ms),
    );

void main() {
  group('FrameMergeCore', () {
    test('두 보드 최신 → 64ch, 등받이 ch0 이 64ch 의 ch32', () {
      final core = FrameMergeCore()
        ..addSeat(_frame(0, 100))
        ..addBack(_frame(10, 500));
      final f = core.tick(_at(100))!;
      expect(f.channels.length, 64);
      expect(f.channels.sublist(0, 32), List.generate(32, (i) => 100 + i));
      expect(f.channels[32], 500); // 등받이 보드 ch0
      expect(f.channels[63], 531); // 등받이 보드 ch31
      expect(f.receivedAt, _at(100));
    });

    test('한쪽만 갱신 → 다른 쪽은 직전 값 유지', () {
      final core = FrameMergeCore()
        ..addSeat(_frame(0, 100))
        ..addBack(_frame(0, 500));
      expect(core.tick(_at(100)), isNotNull);

      core.addSeat(_frame(150, 200)); // 좌석만 새 값
      final f = core.tick(_at(200))!;
      expect(f.channels[0], 200);
      expect(f.channels[32], 500); // 등받이는 직전 값
    });

    test('등받이 499ms 는 출력 / 500ms 는 출력 없음 (0 패딩 없음)', () {
      final core = FrameMergeCore()..addBack(_frame(0, 500));

      core.addSeat(_frame(450, 100));
      expect(core.tick(_at(499)), isNotNull);

      core.addSeat(_frame(480, 100));
      expect(core.tick(_at(500)), isNull);
    });

    test('좌석 없음 (등받이만) → 출력 없음', () {
      final core = FrameMergeCore()..addBack(_frame(0, 500));
      expect(core.tick(_at(100)), isNull);
      core.addBack(_frame(150, 500));
      expect(core.tick(_at(200)), isNull);
    });

    test('공백 후 복구 → 다시 출력', () {
      final core = FrameMergeCore()
        ..addSeat(_frame(0, 100))
        ..addBack(_frame(0, 500));
      expect(core.tick(_at(100)), isNotNull);

      // 등받이가 600ms 끊김
      core.addSeat(_frame(550, 100));
      expect(core.tick(_at(600)), isNull);

      core.addBack(_frame(650, 600));
      core.addSeat(_frame(660, 100));
      final f = core.tick(_at(700))!;
      expect(f.channels[32], 600);
    });

    test('빈 버킷(두 보드 모두 갱신 없음) → 출력 없음', () {
      final core = FrameMergeCore()
        ..addSeat(_frame(0, 100))
        ..addBack(_frame(0, 500));
      expect(core.tick(_at(100)), isNotNull);
      expect(core.tick(_at(200)), isNull); // 아직 500ms 안 지났지만 새 값이 없음
    });

    test('32ch 가 아닌 프레임은 무시', () {
      final core = FrameMergeCore()
        ..addSeat(_frame(0, 100, n: 31))
        ..addBack(_frame(0, 500));
      expect(core.tick(_at(100)), isNull); // 좌석이 들어온 적 없는 것과 같음

      core
        ..addSeat(_frame(150, 100))
        ..addBack(_frame(160, 900, n: 64)); // 무시 → 직전 등받이 유지
      final f = core.tick(_at(200))!;
      expect(f.channels[32], 500);
    });
  });

  test('FrameMerger — 주입한 ticks 로 스트림 병합', () async {
    final seat = StreamController<SensorFrame>();
    final back = StreamController<SensorFrame>();
    final ticks = StreamController<DateTime>();
    final merger = FrameMerger(seat.stream, back.stream, ticks: ticks.stream);
    final out = <SensorFrame>[];
    final sub = merger.frames.listen(out.add);

    seat.add(_frame(0, 100));
    back.add(_frame(0, 500));
    await Future<void>.delayed(Duration.zero);
    ticks.add(_at(100));
    await Future<void>.delayed(Duration.zero);

    expect(out.length, 1);
    expect(out.single.channels.length, 64);

    await sub.cancel();
    await merger.dispose();
    await seat.close();
    await back.close();
    await ticks.close();
  });
}
