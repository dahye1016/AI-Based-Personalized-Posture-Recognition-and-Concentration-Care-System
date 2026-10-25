import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/posture_class.dart';
import '../models/sensor_frame.dart';
import 'posture_preprocessor.dart';

/// 온디바이스 자세 분류기. 좌석+등받이 병합 64ch [SensorFrame] 하나를 8클래스 중 하나로 판정한다.
///
/// 모델·json 은 feat/dahye(2bac866) 결과를 assets/model/ 에 복사해 둔 것이다.
///   - posture_model_gbt.tflite : 입력 [1, 128] float32 (원시 64 + 기준값 64), 출력 [1, 8] 확률
///   - norm_stats_gbt.json      : 라벨 순서, 입력 shape, raw_input (mean/std 없음)
/// 출력은 이미 확률이므로 softmax 를 하지 않는다 (argmax 만 쓴다).
///
/// 기준값이 없으면 판정하지 않는다(null). 지금은 [BaselineCollector] 로 앉은 첫 5초를
/// 임시 기준값으로 쓴다. 캘리브레이션 화면이 64ch 기준값을 주면 [setBaseline] 으로 넣는다.
class PostureModel {
  PostureModel._(this._interpreter, this._pre, int smoothWindow)
      : _smoother = MajoritySmoother(window: smoothWindow),
        _collector = BaselineCollector(channelCount: _pre.channelCount);

  static const String modelAsset = 'assets/model/posture_model_gbt.tflite';
  static const String statsAsset = 'assets/model/norm_stats_gbt.json';

  final Interpreter _interpreter;
  final PosturePreprocessor _pre;
  final MajoritySmoother _smoother;
  final BaselineCollector _collector;
  List<double>? _baseline;

  bool get hasBaseline => _baseline != null;

  /// 임시 기준값 수집 진행도 (모은 앉은 프레임 수 / 필요한 수).
  int get baselineCount => _collector.count;
  int get baselineFrames => _collector.frames;

  /// 캘리브레이션 결과(64ch 원시값 평균)를 기준값으로 쓴다.
  void setBaseline(List<double> baseline) {
    if (baseline.length != _pre.channelCount) {
      throw ArgumentError('기준값이 ${baseline.length}개입니다 (${_pre.channelCount}개여야 함).');
    }
    _baseline = List.unmodifiable(baseline);
    _collector.reset();
  }

  /// assets 에서 모델과 정규화 값을 읽는다. 순서·shape 가 맞지 않으면 예외를 던진다.
  ///
  /// [smoothWindow] 는 다수결 창 크기. 기본 20 = 병합 프레임 10Hz 에서 2초.
  /// 자세를 바꾸는 도중(다리를 드는 순간 등)은 학습에 없는 압력이라 0.5초 창에서는
  /// 앞으로 숙이기·기대기가 잠깐 튀었다. 2초 창이면 새 자세를 약 1초 유지해야 바뀐다.
  /// (시리얼 수집 50fps 경로는 같은 2초가 되도록 100 을 넘긴다.)
  static Future<PostureModel> load({int smoothWindow = 20}) async {
    final stats =
        jsonDecode(await rootBundle.loadString(statsAsset)) as Map<String, dynamic>;
    final pre = PosturePreprocessor.fromJson(stats);
    final interpreter = await Interpreter.fromAsset(modelAsset);

    final inShape = interpreter.getInputTensor(0).shape;
    final inLen = inShape.fold<int>(1, (a, b) => a * b);
    final outLen =
        interpreter.getOutputTensor(0).shape.fold<int>(1, (a, b) => a * b);
    if (inLen != pre.inputLength || outLen != PostureClass.canonical.length) {
      interpreter.close();
      throw StateError(
          '모델과 json 이 맞지 않습니다: 입력 $inShape (json ${pre.inputLength}), 출력 $outLen');
    }
    return PostureModel._(interpreter, pre, smoothWindow);
  }

  /// 프레임 1개 -> 원시 판정 (안정화 없음).
  /// 채널 수가 다르거나 기준값이 아직 없으면 null (기준값이 없을 때는 수집에 쓴다).
  PostureClass? predictRaw(SensorFrame frame) {
    if (frame.channels.length != _pre.channelCount) return null;
    final baseline = _baseline;
    if (baseline == null) {
      final collected = _collector.add(frame.channels);
      if (collected != null) {
        _baseline = List.unmodifiable(collected);
        final sum = collected.fold<double>(0, (a, b) => a + b);
        debugPrint('[Posture] 임시 기준값 수집 완료 (${_collector.frames}프레임, '
            '합 ${sum.toStringAsFixed(0)})');
      }
      return null;
    }

    // 모델 입력 [1, 128]. 출력 [1, 8] 은 확률 — argmax 만 본다.
    final input = [_pre.toInput(frame.channels, baseline)];
    final output = [List<double>.filled(PostureClass.canonical.length, 0)];
    _interpreter.run(input, output);
    return PostureClass.fromId(PosturePreprocessor.argmax(output[0]));
  }

  /// 프레임 1개 -> 최근 판정들과 다수결한 안정화 결과. 화면 표시용.
  PostureClass? predict(SensorFrame frame) {
    final raw = predictRaw(frame);
    if (raw == null) return null;
    return PostureClass.fromId(_smoother.add(raw.id!));
  }

  /// 연결이 끊겼다 다시 붙을 때 이전 판정이 남지 않게 한다.
  void reset() => _smoother.reset();

  void dispose() => _interpreter.close();
}
