/// 모델 입력 전처리 + 결과 안정화. Flutter/TFLite 에 의존하지 않는 순수 Dart.
///
/// 학습(feat/dahye ml/train_posture_gbt.py)과 똑같이 만들어야 한다.
///   입력 128개 = [지금 프레임 원시값 ch0~63] + [기준값(정자세 5초 평균) ch0~63]
///   정규화하지 않는다 (특징 계산은 모델 안에서 한다). 0 패딩 없음.
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
  PosturePreprocessor({this.channelCount = 64, this.usesBaseline = true});

  /// `norm_stats_gbt.json` (assets/model) 을 파싱한 Map 으로 만든다.
  /// 원시값 입력 모델(`raw_input: true`)만 받는다. mean/std 는 쓰지 않는다.
  factory PosturePreprocessor.fromJson(Map<String, dynamic> json) {
    final labels = (json['label_order'] as List).cast<String>();
    if (labels.length != kExpectedLabelOrder.length) {
      throw StateError(
          '라벨 개수가 ${labels.length}개입니다 (${kExpectedLabelOrder.length}개여야 함).');
    }
    for (var i = 0; i < labels.length; i++) {
      if (labels[i] != kExpectedLabelOrder[i]) {
        throw StateError(
            '라벨 순서가 앱과 다릅니다: $i번이 ${labels[i]} (앱 기준 ${kExpectedLabelOrder[i]})');
      }
    }
    if (json['raw_input'] != true) {
      throw StateError('raw_input 모델이 아닙니다 (정규화 입력 모델은 지원하지 않음).');
    }
    final shape = ((json['model_io'] as Map)['input_shape'] as List).cast<int>();
    final length = shape.fold<int>(1, (a, b) => a * b);
    if (length.isOdd) {
      throw StateError('입력 길이 $length 가 [프레임 + 기준값] 구조가 아닙니다.');
    }
    // 기준값 계약은 json 의 `calibration` 유무로 판단한다.
    // gbt 모델은 있고(정자세 5초 평균), corrected 모델은 없다(뒤 64개 무시, 0 가능).
    return PosturePreprocessor(
      channelCount: length ~/ 2,
      usesBaseline: json.containsKey('calibration'),
    );
  }

  /// 프레임 채널 수 (64 = 좌석 32 + 등받이 32).
  final int channelCount;

  /// 모델이 뒤 64개(기준값)를 실제로 쓰는지. false 면 0 을 채워 넣어도 된다.
  final bool usesBaseline;

  /// 모델 입력 값 개수 (128 = 프레임 64 + 기준값 64).
  int get inputLength => channelCount * 2;

  /// 원시값 64개 + 기준값 64개 -> 모델 입력 128개. 정규화·패딩 없음.
  Float32List toInput(List<int> channels, List<double> baseline) {
    if (channels.length != channelCount) {
      throw ArgumentError('채널이 ${channels.length}개입니다 ($channelCount개여야 함).');
    }
    if (baseline.length != channelCount) {
      throw ArgumentError('기준값이 ${baseline.length}개입니다 ($channelCount개여야 함).');
    }
    final out = Float32List(inputLength);
    for (var i = 0; i < channelCount; i++) {
      out[i] = channels[i].toDouble();
      out[channelCount + i] = baseline[i];
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

/// ★ 임시 기준값 수집기 (작업 39) — 캘리브레이션 화면이 64ch 기준값을 주기 전까지 쓴다.
///
/// 앉아 있는 프레임(좌석 ch0~31 합 >= [seatMin])만 [frames] 개 모아 채널별 평균을 낸다.
/// 기본 50 프레임 = 병합 프레임 10Hz 에서 5초 (학습의 캘리브레이션 5초와 같은 길이).
/// [seatMin] 6000 은 팀 자세 정의(gen_dummy_spec.py SEAT_MIN)의 '앉아 있음' 기준.
/// 앉지 않은 프레임은 세지 않고 건너뛴다 — 빈 의자가 기준값이 되는 것을 막는다.
class BaselineCollector {
  BaselineCollector({
    this.frames = 50,
    this.seatMin = 6000,
    this.channelCount = 64,
  });

  final int frames;
  final double seatMin;
  final int channelCount;

  List<double>? _sum;
  int _count = 0;

  /// 지금까지 모은 앉은 프레임 수.
  int get count => _count;

  /// 프레임 1개를 넣는다. [frames] 개가 모이면 기준값(채널별 평균)을 돌려준다.
  List<double>? add(List<int> channels) {
    if (channels.length != channelCount) return null;
    var seat = 0;
    for (var i = 0; i < channelCount ~/ 2; i++) {
      seat += channels[i];
    }
    if (seat < seatMin) return null;

    final sum = _sum ??= List<double>.filled(channelCount, 0);
    for (var i = 0; i < channelCount; i++) {
      sum[i] += channels[i];
    }
    _count++;
    if (_count < frames) return null;
    return [for (final s in sum) s / _count];
  }

  void reset() {
    _sum = null;
    _count = 0;
  }
}

/// 최근 [window] 개 판정 중 가장 많은 값을 돌려줘서 화면이 깜빡이지 않게 한다.
/// 창 크기는 [PostureModel.load] 의 smoothWindow 로 주입된다 (기본 5 = BLE Notify 10Hz 에서 0.5초).
/// 시리얼 수집(50fps)처럼 프레임이 빠른 경로에서는 25 를 넘겨야 같은 0.5초가 된다.
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
