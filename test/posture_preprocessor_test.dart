import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:posturecare_ai/services/posture_preprocessor.dart';

/// 7클래스 64ch 원시값 모델(assets/model/norm_stats_gbt.json)용 전처리 검사.
/// 학습(feat/dahye ml/train_posture_gbt.py)의 입력은
/// [지금 프레임 원시값 ch0~63] + [기준값 ch0~63] 128개이고 정규화하지 않는다.
Map<String, dynamic> _json() =>
    jsonDecode(File('assets/model/norm_stats_gbt.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  test('json 의 라벨 순서가 앱 순서와 같다 (7개)', () {
    expect(_json()['label_order'], kExpectedLabelOrder);
    expect(kExpectedLabelOrder.length, 7);
  });

  test('json 으로 만들면 채널 64 / 입력 128', () {
    final pre = PosturePreprocessor.fromJson(_json());
    expect(pre.channelCount, 64);
    expect(pre.inputLength, 128);
  });

  test('앱이 쓰는 corrected json: 라벨 7개 일치, 입력 128, 기준값 안 씀', () {
    final json = jsonDecode(
            File('assets/model/norm_stats_corrected.json').readAsStringSync())
        as Map<String, dynamic>;
    expect(json['label_order'], kExpectedLabelOrder);
    final pre = PosturePreprocessor.fromJson(json);
    expect(pre.inputLength, 128);
    expect(pre.usesBaseline, isFalse);
  });

  test('gbt json 은 기준값을 쓴다 (calibration 있음)', () {
    expect(PosturePreprocessor.fromJson(_json()).usesBaseline, isTrue);
  });

  test('raw_input 이 아닌 json 은 거부', () {
    final json = _json()..remove('raw_input');
    expect(() => PosturePreprocessor.fromJson(json), throwsStateError);
  });

  test('라벨 개수가 다른 json(예전 8클래스 등)은 거부', () {
    final json = _json();
    json['label_order'] = [...json['label_order'] as List, 'extra'];
    expect(() => PosturePreprocessor.fromJson(json), throwsStateError);
  });

  test('입력 = 원시값 64 그대로 + 기준값 64 (정규화·0 패딩 없음)', () {
    final pre = PosturePreprocessor.fromJson(_json());
    final ch = List<int>.generate(64, (i) => i * 10);
    final base = List<double>.generate(64, (i) => 1000.0 + i);
    final x = pre.toInput(ch, base);
    expect(x.length, 128);
    for (var i = 0; i < 64; i++) {
      expect(x[i], ch[i].toDouble(), reason: 'frame $i');
      expect(x[64 + i], base[i], reason: 'baseline $i');
    }
  });

  test('채널·기준값 개수가 다르면 예외', () {
    final pre = PosturePreprocessor.fromJson(_json());
    expect(() => pre.toInput(List.filled(32, 0), List.filled(64, 0)),
        throwsArgumentError);
    expect(() => pre.toInput(List.filled(64, 0), List.filled(32, 0)),
        throwsArgumentError);
  });

  group('임시 기준값 수집기', () {
    List<int> seated(int v) => List<int>.filled(64, v); // 좌석 합 = 32 * v

    test('앉은 프레임 N개가 모이면 채널별 평균을 돌려준다', () {
      final c = BaselineCollector(frames: 3);
      expect(c.add(seated(200)), isNull);
      expect(c.add(seated(300)), isNull);
      final b = c.add(seated(400));
      expect(b, isNotNull);
      expect(b!.length, 64);
      expect(b.every((v) => v == 300), isTrue);
    });

    test('좌석 합이 기준 미만(빈 의자)인 프레임은 세지 않는다', () {
      // seatMin 은 8a549bf(아로)에서 6000 -> 1500. 근거: posture_preprocessor.dart
      // 주석 "매트 압력이 낮아 팀 기준(gen_dummy_spec.py SEAT_MIN 6000)에서 낮춤".
      final c = BaselineCollector(frames: 2);
      expect(c.add(seated(0)), isNull);
      expect(c.add(seated(40)), isNull); // 32*40 = 1280 < 1500
      expect(c.count, 0);
      c.add(seated(200));
      expect(c.add(seated(200)), isNotNull);
    });

    test('reset 하면 처음부터', () {
      final c = BaselineCollector(frames: 2);
      c.add(seated(200));
      c.reset();
      expect(c.count, 0);
      expect(c.add(seated(200)), isNull);
    });
  });

  test('argmax', () {
    expect(PosturePreprocessor.argmax([0.1, 2.0, -1.0, 1.9]), 1);
  });

  test('다수결 안정화: 튀는 값 한 개는 무시', () {
    final s = MajoritySmoother(window: 5);
    for (var i = 0; i < 4; i++) {
      s.add(1);
    }
    expect(s.add(2), 1);
  });
}
