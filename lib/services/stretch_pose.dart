import 'dart:math' as math;

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// 스트레칭 동작 판정 — ML Kit 관절 좌표로 "지금 그 동작을 하고 있는지"를 본다.
///
/// 좌표는 ML Kit 이미지 좌표(y 아래로 증가). 사람마다 체격이 달라서 거리는
/// 어깨 너비를 1 로 둔 상대값으로 비교한다. 좌우 대칭 판정만 써서
/// 전면 카메라 좌우 반전과 상관없다.
///
/// 동작마다 [MoveRule] 이 '판정값'을 계산하고, 값이 [MoveRule.threshold] 이상이면
/// 그 동작을 하고 있는 것으로 본다. 화면(디버그)에 값/기준을 띄워 기준을 맞춘다.
class PoseView {
  PoseView(this.pose, {this.minLikelihood = 0.3});

  final Pose pose;

  /// 이보다 확신도가 낮은 관절은 없는 것으로 본다.
  final double minLikelihood;

  /// 몸통 비틀기 판정용 기준 어깨너비 (이 동작 중 가장 넓었던 값). [RepCounter] 가 채운다.
  double? twistBase;

  PoseLandmark? _lm(PoseLandmarkType t) {
    final l = pose.landmarks[t];
    if (l == null || l.likelihood < minLikelihood) return null;
    return l;
  }

  PoseLandmark? get nose => _lm(PoseLandmarkType.nose);
  PoseLandmark? get lEar => _lm(PoseLandmarkType.leftEar) ?? _lm(PoseLandmarkType.leftEye);
  PoseLandmark? get rEar => _lm(PoseLandmarkType.rightEar) ?? _lm(PoseLandmarkType.rightEye);
  PoseLandmark? get lSh => _lm(PoseLandmarkType.leftShoulder);
  PoseLandmark? get rSh => _lm(PoseLandmarkType.rightShoulder);
  PoseLandmark? get lEl => _lm(PoseLandmarkType.leftElbow);
  PoseLandmark? get rEl => _lm(PoseLandmarkType.rightElbow);

  /// 손목이 화면 밖이면 팔꿈치로 대신한다 (팔을 쭉 뻗으면 손목이 잘 잘린다).
  PoseLandmark? get lHand => _lm(PoseLandmarkType.leftWrist) ?? lEl;
  PoseLandmark? get rHand => _lm(PoseLandmarkType.rightWrist) ?? rEl;

  /// 어깨 너비 (픽셀). 어깨가 안 보이면 null.
  double? get shoulderWidth {
    final a = lSh, b = rSh;
    if (a == null || b == null) return null;
    final w = math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));
    return w < 1 ? null : w;
  }

  /// 상체(어깨)가 화면에 보이는지.
  bool get upperBodyVisible => shoulderWidth != null;

  /// 두 점을 이은 선이 수평에서 기운 각도 (도, 0~90).
  static double tiltDeg(PoseLandmark a, PoseLandmark b) {
    final dx = (a.x - b.x).abs(), dy = (a.y - b.y).abs();
    return math.atan2(dy, dx) * 180 / math.pi;
  }
}

/// 동작 하나의 판정 규칙. [value] 가 null 이면 필요한 관절이 안 보이는 것.
class MoveRule {
  const MoveRule(this.value, this.threshold, this.unit);

  final double? Function(PoseView p) value;

  /// 이 값 이상이면 동작 중.
  final double threshold;

  /// 디버그 표시용 단위 ('°' 또는 '' = 어깨너비 배수).
  final String unit;
}

/// 동작 이름 → 판정 규칙. 없는 동작은 자동으로 세지 않는다(수동 진행).
class StretchPoses {
  StretchPoses._();

  static MoveRule? ruleFor(String move) => switch (move) {
        '목 옆으로 늘이기' => const MoveRule(_neckSide, 8, '°'),
        '목 뒤로 젖히기' => const MoveRule(_neckBack, -0.03, ''),
        '팔 양 옆으로 늘리기' => const MoveRule(_armsSide, 0.1, ''),
        '팔 위로 뻗기' => const MoveRule(_armsUp, 0.0, ''),
        '몸통 옆으로 늘이기' => const MoveRule(_torsoSide, 5, '°'),
        '가슴 열기' => const MoveRule(_chestOpen, 1.05, ''),
        '몸통 비틀기' => const MoveRule(_twist, 0.1, ''),
        _ => null,
      };

  /// 귀(없으면 눈)를 이은 선의 기울기 (°). 고개를 옆으로 꺾으면 커진다.
  static double? _neckSide(PoseView p) {
    final a = p.lEar, b = p.rEar;
    if (a == null || b == null) return null;
    return PoseView.tiltDeg(a, b);
  }

  /// (귀 높이 − 코 높이) / 어깨너비. 턱을 들면 코가 귀보다 올라가 커진다.
  static double? _neckBack(PoseView p) {
    final n = p.nose, a = p.lEar, b = p.rEar, w = p.shoulderWidth;
    if (n == null || a == null || b == null || w == null) return null;
    return ((a.y + b.y) / 2 - n.y) / w;
  }

  /// 손(없으면 팔꿈치)이 어깨 바깥으로 나간 거리 중 작은 쪽 / 어깨너비.
  /// 양팔을 옆으로 뻗으면 커진다.
  static double? _armsSide(PoseView p) {
    final ls = p.lSh, rs = p.rSh, lh = p.lHand, rh = p.rHand, w = p.shoulderWidth;
    if (ls == null || rs == null || lh == null || rh == null || w == null) {
      return null;
    }
    final leftSh = math.min(ls.x, rs.x), rightSh = math.max(ls.x, rs.x);
    final leftHand = math.min(lh.x, rh.x), rightHand = math.max(lh.x, rh.x);
    return math.min(leftSh - leftHand, rightHand - rightSh) / w;
  }

  /// 어깨보다 손(없으면 팔꿈치)이 올라간 높이 중 낮은 쪽 / 어깨너비.
  /// 양팔을 위로 뻗으면 커진다.
  static double? _armsUp(PoseView p) {
    final ls = p.lSh, rs = p.rSh, lh = p.lHand, rh = p.rHand, w = p.shoulderWidth;
    if (ls == null || rs == null || lh == null || rh == null || w == null) {
      return null;
    }
    final shY = (ls.y + rs.y) / 2;
    return math.min(shY - lh.y, shY - rh.y) / w;
  }

  /// 어깨선 기울기 (°). 몸통을 옆으로 굽히면 커진다.
  static double? _torsoSide(PoseView p) {
    final a = p.lSh, b = p.rSh;
    if (a == null || b == null) return null;
    return PoseView.tiltDeg(a, b);
  }

  /// 양 팔꿈치 사이 거리 / 어깨너비. 팔꿈치를 벌려 가슴을 열면 커진다.
  /// (팔꿈치가 어깨보다 한참 아래로 처지면 0)
  static double? _chestOpen(PoseView p) {
    final ls = p.lSh, rs = p.rSh, le = p.lEl, re = p.rEl, w = p.shoulderWidth;
    if (ls == null || rs == null || le == null || re == null || w == null) {
      return null;
    }
    final shY = (ls.y + rs.y) / 2;
    final dropped = ((le.y + re.y) / 2 - shY) / w > 0.9;
    if (dropped) return 0;
    return (le.x - re.x).abs() / w;
  }

  /// 1 − (지금 어깨너비 / 이 동작 중 가장 넓었던 어깨너비).
  /// 몸통을 돌리면 화면에서 어깨너비가 줄어 커진다.
  static double? _twist(PoseView p) {
    final w = p.shoulderWidth, base = p.twistBase;
    if (w == null || base == null || base <= 0) return null;
    return 1 - w / base;
  }
}

/// 동작 자세를 [holdFor] 동안 유지하면 1회. 다음 회는 자세를 한 번 풀었다가 다시.
///
/// 경계에서 깜빡이며 여러 번 세지 않도록, 풀린 것으로 보는 기준은 [threshold] 의
/// [releaseRatio] 배로 낮게 잡는다.
class RepCounter {
  RepCounter(
    this.rule, {
    this.holdFor = const Duration(milliseconds: 300),
    this.releaseRatio = 0.7,
  });

  final MoveRule rule;
  final Duration holdFor;
  final double releaseRatio;

  DateTime? _activeSince;
  bool _counted = false; // 이번 자세에서 이미 셌는지 (풀기 전까지)
  bool _holding = false;
  double _maxShoulder = 0;

  /// 마지막 판정값 (관절이 안 보이면 null). 디버그 표시용.
  double? lastValue;

  /// 지금 동작 자세를 하고 있는지 (화면 배지용).
  bool get holding => _holding;

  /// 프레임 하나를 넣는다. 1회가 완성되면 true.
  bool add(Pose pose, DateTime at) {
    final view = PoseView(pose);
    final w = view.shoulderWidth;
    if (w != null && w > _maxShoulder) _maxShoulder = w;
    view.twistBase = _maxShoulder;

    final v = rule.value(view);
    lastValue = v;
    if (v == null) return false; // 관절이 안 보이면 상태 유지

    if (v >= rule.threshold) {
      _holding = true;
      _activeSince ??= at;
      if (!_counted && at.difference(_activeSince!) >= holdFor) {
        _counted = true;
        return true;
      }
      return false;
    }
    // 풀림 기준: 기준보다 충분히 아래로 내려가면 (기준이 0 이하인 동작은 0.1 아래).
    final release = rule.threshold > 0
        ? rule.threshold * releaseRatio
        : rule.threshold - 0.1;
    if (v < release) {
      _holding = false;
      _activeSince = null;
      _counted = false;
    }
    return false;
  }
}
