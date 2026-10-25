/// ★ 임시 (작업 38) — 다혜 부스팅 모델(posture_model_gbt.tflite)이 기기에서
/// 로드·추론되는지만 확인한다. 기존 판정 경로([PostureModel])와 무관.
/// 확인이 끝나면 이 파일과 main.dart 의 호출 한 줄을 지운다.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

const String _modelAsset = 'assets/model/posture_model_gbt.tflite';
const String _statsAsset = 'assets/model/norm_stats_gbt.json';
const int _runs = 100;

/// 앱 시작 시 한 번 호출. 예외는 모두 잡아서 로그만 남긴다.
Future<void> runGbtLoadProbe() async {
  const tag = '[GBT probe]';
  Interpreter? it;
  try {
    // 첫 화면 렌더링과 겹치지 않게 잠깐 미룬다.
    await Future<void>.delayed(const Duration(seconds: 2));

    final stats =
        jsonDecode(await rootBundle.loadString(_statsAsset)) as Map<String, dynamic>;
    final labels = (stats['label_order'] as List).cast<String>();
    debugPrint('$tag json OK — label_order ${labels.length}개: $labels');

    final loadWatch = Stopwatch()..start();
    it = await Interpreter.fromAsset(_modelAsset);
    loadWatch.stop();
    final inShape = it.getInputTensor(0).shape;
    final outShape = it.getOutputTensor(0).shape;
    debugPrint('$tag 로드 성공 (${loadWatch.elapsedMilliseconds}ms) — '
        '입력 $inShape ${it.getInputTensor(0).type} / 출력 $outShape');

    // 더미 입력: 지금 프레임 64 + 기준값 64, 모두 200 (원시값 크기 정도).
    final input = [List<double>.filled(128, 200)];
    final output = [List<double>.filled(8, 0)];
    it.run(input, output);
    final p = output[0];
    final sum = p.fold<double>(0, (a, b) => a + b);
    var best = 0;
    for (var i = 1; i < p.length; i++) {
      if (p[i] > p[best]) best = i;
    }
    debugPrint('$tag 추론 1회 OK — 출력 길이 ${p.length}, 합 ${sum.toStringAsFixed(3)}, '
        'argmax $best (${labels[best]})');

    final watch = Stopwatch()..start();
    for (var i = 0; i < _runs; i++) {
      it.run(input, output);
    }
    watch.stop();
    final avgMs = watch.elapsedMicroseconds / _runs / 1000;
    debugPrint('$tag 추론 $_runs회 평균 ${avgMs.toStringAsFixed(2)}ms '
        '(총 ${watch.elapsedMilliseconds}ms)');
  } catch (e, st) {
    debugPrint('$tag ❌ 실패: $e\n$st');
  } finally {
    it?.close();
  }
}
