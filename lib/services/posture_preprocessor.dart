/// 모델 입력 전처리 + 결과 안정화. Flutter/TFLite 에 의존하지 않는 순수 Dart.
///
/// 학습(ml/train_posture_cnn.py)과 똑같이 만들어야 한다.
///   1. ch0~31 을 (값 - mean) / std 로 정규화  (mean/std 는 norm_stats.json)
///   2. 뒤에 0 을 32개 붙여 64개로 만든다 (등받이 센서 자리, 아직 없음)
library;

import 'dart:typed_data';

/// json 의 `label_order` 인덱스 -> 앱 [PostureClass.id] 와 같아야 하는 이름.
/// 순서가 어긋나면 로드 단계에서 바로 실패시켜 조용한 오분류를 막는다.
const List<String> kExpectedLabelOrder = [
  'not_sitting', // 0 앉지 않음
  'sitting_straight', // 1 정자세
  'lean_forward', // 2 앞으로 숙이기
  'cross_leg_right', // 3 오른다리 꼬기
  'cross_leg_left', // 4 왼다리 꼬기
  'lean_right', // 5 오른쪽 기대기
  'lean_left', // 6 왼쪽 기대기
];

class PosturePreprocessor {
  PosturePreprocessor({
    required this.mean,
    required this.std,
    this.inputLength = 64,
  }) {
    if (mean.length != std.length) {
      throw ArgumentError('mean/std 길이가 다릅니다: ${mean.length} vs ${std.length}');
    }
    if (mean.length > inputLength) {
      throw ArgumentError('채널 수(${mean.length})가 입력 길이($inputLength)보다 큽니다.');
    }
  }

  /// `norm_stats.json` (assets/model) 을 파싱한 Map 으로 만든다.
  factory PosturePreprocessor.fromJson(Map<String, dynamic> json) {
    final labels = (json['label_order'] as List).cast<String>();
    if (labels.length != kExpectedLabelOrder.length) {
      throw StateError('라벨 개수가 ${labels.length}개입니다 (7개여야 함).');
    }
    for (var i = 0; i < labels.length; i++) {
      if (labels[i] != kExpectedLabelOrder[i]) {
        throw StateError(
            '라벨 순서가 앱과 다릅니다: $i번이 ${labels[i]} (앱 기준 ${kExpectedLabelOrder[i]})');
      }
    }
    final shape = ((json['model_io'] as Map)['input_shape'] as List).cast<int>();
    final length = shape.fold<int>(1, (a, b) => a * b);
    return PosturePreprocessor(
      mean: (json['mean'] as List).map((e) => (e as num).toDouble()).toList(),
      std: (json['std'] as List).map((e) => (e as num).toDouble()).toList(),
      inputLength: length,
    );
  }

  final List<double> mean;
  final List<double> std;

  /// 모델 입력 값 개수 (64).
  final int inputLength;

  int get channelCount => mean.length;

  /// ch0~31 원시값 -> 모델 입력 64개. 나머지 자리는 0.
  Float32List toInput(List<int> channels) {
    if (channels.length != channelCount) {
      throw ArgumentError('채널이 ${channels.length}개입니다 ($channelCount개여야 함).');
    }
    final out = Float32List(inputLength); // 0 으로 초기화 = 패딩
    for (var i = 0; i < channelCount; i++) {
      out[i] = (channels[i] - mean[i]) / std[i];
    }
    return out;
  }

  /// 점수(logit) 중 가장 큰 것의 인덱스.
  static int argmax(List<double> scores) {
    var best = 0;
    for (var i = 1; i < scores.length; i++) {
      if (scores[i] > scores[best]) best = i;
    }
    return best;
  }
}

/// 최근 [window] 개 판정 중 가장 많은 값을 돌려줘서 화면이 깜빡이지 않게 한다.
/// (센서가 초당 약 50프레임이라 window=25 면 0.5초 분량)
class MajoritySmoother {
  MajoritySmoother({this.window = 25});

  final int window;
  final List<int> _recent = [];

  /// 새 판정을 넣고, 안정화된 결과를 돌려준다.
  int add(int classIndex) {
    _recent.add(classIndex);
    if (_recent.length > window) _recent.removeAt(0);
    final counts = <int, int>{};
    for (final c in _recent) {
      counts[c] = (counts[c] ?? 0) + 1;
    }
    var best = classIndex;
    var bestCount = 0;
    counts.forEach((c, n) {
      // 동률이면 가장 최근 값을 우선한다.
      if (n > bestCount || (n == bestCount && c == classIndex)) {
        best = c;
        bestCount = n;
      }
    });
    return best;
  }

  void reset() => _recent.clear();
}
