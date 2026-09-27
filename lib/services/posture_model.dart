import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/posture_class.dart';
import '../models/sensor_frame.dart';
import 'posture_preprocessor.dart';

/// 온디바이스 자세 분류기. BLE 로 받은 [SensorFrame] 하나를 7클래스 중 하나로 판정한다.
///
/// 모델·정규화 값은 ml/ 에서 학습·변환한 것을 assets/model/ 에 복사해 둔 것이다.
///   - posture_model.tflite : 입력 [1, 64, 1] float32, 출력 [1, 7] 점수
///   - norm_stats.json      : ch0~31 mean/std, 라벨 순서, 입력 shape
class PostureModel {
  PostureModel._(this._interpreter, this._pre);

  static const String modelAsset = 'assets/model/posture_model.tflite';
  static const String statsAsset = 'assets/model/norm_stats.json';

  final Interpreter _interpreter;
  final PosturePreprocessor _pre;
  final MajoritySmoother _smoother = MajoritySmoother();

  /// assets 에서 모델과 정규화 값을 읽는다. 순서·shape 가 맞지 않으면 예외를 던진다.
  static Future<PostureModel> load() async {
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
    return PostureModel._(interpreter, pre);
  }

  /// 프레임 1개 -> 원시 판정 (안정화 없음). 채널 수가 다르면 null.
  PostureClass? predictRaw(SensorFrame frame) {
    if (frame.channels.length != _pre.channelCount) return null;
    final input = _pre.toInput(frame.channels);

    // 모델 입력 [1, 64, 1] 형태로 감싼다.
    final shaped = [
      List.generate(_pre.inputLength, (i) => [input[i]]),
    ];
    final output = [List<double>.filled(PostureClass.canonical.length, 0)];
    _interpreter.run(shaped, output);
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
