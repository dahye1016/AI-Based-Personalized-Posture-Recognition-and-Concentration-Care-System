import '../models/posture_class.dart';
import '../models/sensor_layout.dart';

/// 목표 자세(처음 10초 정자세 측정) 기준 판정.
///
/// 학습 모델과 달리 "이 사람·이 의자에서 잰 정자세"와 지금 좌석 압력 *분포*를 비교한다.
/// - 등받이: 정자세 때 등을 붙였으면(합 300 이상) 등이 떨어질 때 앞으로 숙이기로 본다.
/// - 다리 꼬기: 꼰 쪽 다리가 들리면 그쪽 무릎 압력이 목표 자세 대비 거의 사라진다.
/// - 그 밖에는 목표 자세와의 차이 점수(0~100)가 [outScore] 이상일 때만 나쁜 자세로 본다.
class TargetPostureJudge {
  TargetPostureJudge(List<double> seatMean, {List<double>? backMean})
      : assert(seatMean.length >= SensorLayout.nChannels),
        _base = _dist(seatMean),
        _bp = _Parts.of(seatMean),
        baseBack = backMean == null ? 0 : backMean.fold(0.0, (a, b) => a + b);

  /// 정자세 때 등받이 합. [backTouch] 이상이면 '등이 떨어짐 = 앞으로 숙이기' 규칙을 쓴다.
  final double baseBack;
  static const double backTouch = 300;

  /// 지금 등받이 합이 정자세의 이 비율 아래로 떨어지면 앞으로 숙이기.
  static const double backDrop = 0.3;

  /// 등받이 규칙을 쓰는지 (정자세 때 등을 붙였는지).
  bool get usesBack => baseBack >= backTouch;
  double lastBack = 0;

  /// 측정값으로 만들 수 있는지 (앉은 값이 충분한지).
  static bool usable(List<double>? seatMean) {
    if (seatMean == null || seatMean.length < SensorLayout.nChannels) return false;
    var s = 0.0;
    for (var i = 0; i < SensorLayout.nChannels; i++) {
      s += seatMean[i];
    }
    return s >= emptySum;
  }

  /// 정자세 대비 좌석 왼쪽 비율이 이만큼 바뀌면 좌우 기대기.
  static const double lrLean = 0.15;
  static const double emptySum = 300; // 좌석 합이 이보다 작으면 앉지 않음
  static const double outScore = 30; // 목표 자세와 이만큼 다르면 '벗어남'
  static const int window = 20; // 점수 중앙값 창 (10Hz 기준 2초)

  final List<double> _base;
  final _Parts _bp;
  final List<double> _recent = [];

  /// 마지막 프레임의 (2초 중앙값) 차이 점수. 화면 표시·로그용.
  /// 마지막 프레임의 좌석 왼쪽 비율 변화 (정자세 대비, +왼쪽 / -오른쪽). 로그용.
  double lastDlr = 0;
  double lastScore = 0;

  /// 목표 자세의 무릎 값이 작으면 다리 꼬기 구분이 약하다 (매트 위치 안내용).
  bool get weakKnee => _bp.kl < 300 || _bp.kr < 300;

  void reset() {
    _recent.clear();
    _hist.clear();
    _zeroSince = null;
  }

  final List<PostureClass> _hist = [];
  PostureClass _lastRaw = PostureClass.straight;
  PostureClass _lastShown = PostureClass.straight;
  DateTime? _zeroSince;

  /// 마지막 프레임이 센서 끊김으로 판단됐는지 (화면 안내용).
  bool lastFault = false;

  /// 좌석 한쪽 절반이 통째로 0 (실제로 기울어도 반대쪽은 수백 이상 남는다).
  static bool halfFault(List<int> ch) {
    var l = 0, r = 0;
    for (final i in SensorLayout.leftCh) {
      l += ch[i];
    }
    for (final i in SensorLayout.rightCh) {
      r += ch[i];
    }
    return (l < 50 && r > 800) || (r < 50 && l > 800);
  }

  /// 터미널(ml/app_judge_demo.py)과 같은 판정:
  /// 센서 끊김이면 직전 판정 유지, 좌석 전체 0은 3초까지 유지, 결과는 2초 다수결.
  PostureClass predict(List<int> channels, [PostureClass? modelGuess, DateTime? at]) {
    final now = at ?? DateTime.now();
    var sum = 0;
    for (var i = 0; i < SensorLayout.nChannels; i++) {
      sum += channels[i];
    }
    lastFault = false;
    if (halfFault(channels)) {
      lastFault = true;
      return _lastShown;
    }
    if (sum < emptySum && _lastRaw != PostureClass.notSitting) {
      _zeroSince ??= now;
      if (now.difference(_zeroSince!) < const Duration(seconds: 3)) {
        lastFault = true;
        return _lastShown;
      }
    }
    if (sum >= emptySum) _zeroSince = null;
    final raw = _rawPredict(channels, modelGuess);
    _lastRaw = raw;
    _hist.add(raw);
    if (_hist.length > window) _hist.removeAt(0);
    final count = <PostureClass, int>{};
    for (final p in _hist) {
      count[p] = (count[p] ?? 0) + 1;
    }
    var best = raw;
    var bestN = 0;
    count.forEach((p, n) {
      if (n > bestN) {
        best = p;
        bestN = n;
      }
    });
    _lastShown = best;
    return best;
  }

  /// 프레임 1개 판정 (안정화 없음). [modelGuess]: 학습 모델 판정(보조).
  PostureClass _rawPredict(List<int> channels, [PostureClass? modelGuess]) {
    final x = [for (var i = 0; i < SensorLayout.nChannels; i++) channels[i].toDouble()];
    final p = _Parts.of(x);
    if (p.sum < emptySum) {
      _recent.clear();
      lastScore = 0;
      return PostureClass.notSitting;
    }
    final d = _dist(x);
    var diff = 0.0;
    for (var i = 0; i < d.length; i++) {
      diff += (d[i] - _base[i]).abs();
    }
    _recent.add(50 * diff);
    if (_recent.length > window) _recent.removeAt(0);
    final sorted = [..._recent]..sort();
    lastScore = sorted[sorted.length ~/ 2];

    // 기울기: 한쪽 엉덩이가 통째로 뜬다. 다리 꼬기는 양쪽 엉덩이가 붙어 있어서 이걸 먼저 본다.
    final dhl = p.hipL - _bp.hipL;
    if (dhl <= -0.30) return PostureClass.leanRight;
    if (dhl >= 0.30) return PostureClass.leanLeft;
    final crossed = _crossed(p);
    if (crossed != null) return crossed;

    // 앞으로 숙이기: 정자세 때 등받이에 닿던 등이 떨어지면 (좌석만으로는 거의 안 변함, 10/27).
    if (channels.length >= 64) {
      var b = 0;
      for (var i = 32; i < 64; i++) {
        b += channels[i];
      }
      lastBack = b.toDouble();
    }

    // 좌우 쏠림은 점수와 상관없이 먼저 본다 (점수 < 30 이라 정자세로 묻히던 기울기 수정, 10/27).
    final dlr = p.lr - _bp.lr; // +: 왼쪽으로 쏠림
    lastDlr = dlr;
    if (dlr <= -lrLean) return PostureClass.leanRight;
    if (dlr >= lrLean) return PostureClass.leanLeft;
    if (lastScore < outScore) return PostureClass.straight;

    // 앞으로 숙이기 판정은 쓰지 않는다 (10/27 요청). 남은 건 좌우 기대기·다리 꼬기·정자세.
    if (dlr <= -0.20) return PostureClass.leanRight;
    if (dlr >= 0.20) return PostureClass.leanLeft;
    // 방향이 뚜렷하지 않으면 학습 모델 판정을 이름으로 쓴다 (숙이기는 제외).
    if (modelGuess != null &&
        modelGuess.isBad &&
        modelGuess != PostureClass.leanForward) {
      return modelGuess;
    }
    if (dlr.abs() >= 0.08) {
      return dlr < 0 ? PostureClass.leanRight : PostureClass.leanLeft;
    }
    return PostureClass.straight;
  }

  PostureClass? _crossed(_Parts p) {
    if (_bp.kr > 300 && p.kr < 0.25 * _bp.kr && p.kl > 0.6 * _bp.kl) {
      return PostureClass.crossLegRight;
    }
    if (_bp.kl > 300 && p.kl < 0.25 * _bp.kl && p.kr > 0.6 * _bp.kr) {
      return PostureClass.crossLegLeft;
    }
    return null;
  }

  static List<double> _dist(List<double> x) {
    var s = 0.0;
    for (var i = 0; i < SensorLayout.nChannels; i++) {
      s += x[i];
    }
    if (s <= 0) return List<double>.filled(SensorLayout.nChannels, 0);
    return [for (var i = 0; i < SensorLayout.nChannels; i++) x[i] / s];
  }
}

class _Parts {
  _Parts(this.sum, this.lr, this.hip, this.kl, this.kr, this.hipL);

  final double sum, lr, hip, kl, kr;

  /// 엉덩이 압력 중 왼쪽 비율 (0~1).
  final double hipL;

  static double _s(List<double> x, List<int> idx) {
    var t = 0.0;
    for (final i in idx) {
      t += x[i];
    }
    return t;
  }

  factory _Parts.of(List<double> x) {
    final sum = _s(x, [for (var i = 0; i < SensorLayout.nChannels; i++) i]);
    final s = sum <= 0 ? 1e-6 : sum;
    final hl = _s(x, SensorLayout.hipLeft);
    final h = hl + _s(x, SensorLayout.hipRight);
    return _Parts(
      sum,
      _s(x, SensorLayout.leftCh) / s,
      h / s,
      _s(x, SensorLayout.kneeLeft),
      _s(x, SensorLayout.kneeRight),
      h > 0 ? hl / h : 0.5,
    );
  }
}
