import 'dart:math' as math;

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// 스트레칭 동작 판정 — ML Kit 관절 좌표로 "지금 그 동작을 하고 있는지"를 본다.
///
/// 좌표는 ML Kit 이미지 좌표(y 아래로 증가). 사람마다 체격이 달라서 거리는
/// 어깨 너비를 1 로 둔 상대값으로 비교한다. 좌우 대칭 판정만 써서
/// 전면 카메라 좌우 반전과 상관없다.
///
/// 횟수는 [RepCounter] 가 센다: 동작 자세를 [holdFor] 동안 유지했다가
/// 풀면 1회.
typedef PoseCheck = bool Function(PoseView p);

class PoseView {
  PoseView(this.pose, {this.minLikelihood = 0.5});

  final Pose pose;
  final double minLikelihood;

  /// 몸통 비틀기 판정용 기준 어깨너비 (이 동작 중 가장 넓었던 값). [RepCounter] 가 채운다.
  double? twistBase;

  PoseLandmark? _lm(PoseLandmarkType t) {
    final l = pose.landmarks[t];
    if (l == null || l.likelihood < minLikelihood) return null;
    return l;
  }

  PoseLandmark? get nose => _lm(PoseLandmarkType.nose);
  PoseLandmark? get lEar => _lm(PoseLandmarkType.leftEar);
  PoseLandmark? get rEar => _lm(PoseLandmarkType.rightEar);
  PoseLandmark? get lSh => _lm(PoseLandmarkType.leftShoulder);
  PoseLandmark? get rSh => _lm(PoseLandmarkType.rightShoulder);
  PoseLandmark? get lEl => _lm(PoseLandmarkType.leftElbow);
  PoseLandmark? get rEl => _lm(PoseLandmarkType.rightElbow);
  PoseLandmark? get lWr => _lm(PoseLandmarkType.leftWrist);
  PoseLandmark? get rWr => _lm(PoseLandmarkType.rightWrist);

  /// 어깨 너비 (픽셀). 어깨가 안 보이면 null.
  double? get shoulderWidth {
    final a = lSh, b = rSh;
    if (a == null || b == null) return null;
    final w = _dist(a, b);
    return w < 1 ? null : w;
  }

  /// 상체(어깨)가 화면에 보이는지.
  bool get upperBodyVisible => shoulderWidth != null;

  static double _dist(PoseLandmark a, PoseLandmark b) =>
      math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

  /// 두 점을 이은 선이 수평에서 기운 각도 (도, 0~90).
  static double tiltDeg(PoseLandmark a, PoseLandmark b) {
    final dx = (a.x - b.x).abs(), dy = (a.y - b.y).abs();
    return math.atan2(dy, dx) * 180 / math.pi;
  }
}

/// 동작 이름 → 판정 규칙. 없는 동작은 자동으로 세지 않는다(수동 진행).
class StretchPoses {
  StretchPoses._();

  static PoseCheck? checkFor(String move) => switch (move) {
        '목 옆으로 늘이기' => _neckSide,
        '목 뒤로 젖히기' => _neckBack,
        '팔 양 옆으로 늘리기' => _armsSide,
        '팔 위로 뻗기' => _armsUp,
        '몸통 옆으로 늘이기' => _torsoSide,
        '가슴 열기' => _chestOpen,
        '몸통 비틀기' => _twist,
        _ => null,
      };

  /// 귀를 이은 선이 15° 넘게 기울면 (고개를 옆으로 꺾음).
  static bool _neckSide(PoseView p) {
    final a = p.lEar, b = p.rEar;
    if (a == null || b == null) return false;
    return PoseView.tiltDeg(a, b) > 15;
  }

  /// 코가 두 귀 높이보다 어깨너비의 8% 이상 위로 올라가면 (턱을 듦).
  static bool _neckBack(PoseView p) {
    final n = p.nose, a = p.lEar, b = p.rEar, w = p.shoulderWidth;
    if (n == null || a == null || b == null || w == null) return false;
    final earY = (a.y + b.y) / 2;
    return (earY - n.y) / w > 0.08;
  }

  /// 두 손목이 어깨 바깥으로 어깨너비의 60% 이상 나가고, 높이는 어깨 근처.
  static bool _armsSide(PoseView p) {
    final ls = p.lSh, rs = p.rSh, lw = p.lWr, rw = p.rWr, w = p.shoulderWidth;
    if (ls == null || rs == null || lw == null || rw == null || w == null) {
      return false;
    }
    final left = ls.x < rs.x ? ls : rs, right = ls.x < rs.x ? rs : ls;
    final lwX = math.min(lw.x, rw.x), rwX = math.max(lw.x, rw.x);
    final out = (left.x - lwX) / w > 0.6 && (rwX - right.x) / w > 0.6;
    final level = (lw.y - ls.y).abs() / w < 0.5 && (rw.y - rs.y).abs() / w < 0.5;
    return out && level;
  }

  /// 두 손목이 모두 코보다 위.
  static bool _armsUp(PoseView p) {
    final n = p.nose, lw = p.lWr, rw = p.rWr;
    if (n == null || lw == null || rw == null) return false;
    return lw.y < n.y && rw.y < n.y;
  }

  /// 어깨선이 10° 넘게 기울면 (몸통을 옆으로 굽힘).
  static bool _torsoSide(PoseView p) {
    final a = p.lSh, b = p.rSh;
    if (a == null || b == null) return false;
    return PoseView.tiltDeg(a, b) > 10;
  }

  /// 팔꿈치가 어깨 높이로 벌어지고 손이 팔꿈치보다 위 (W 모양으로 가슴을 엶).
  static bool _chestOpen(PoseView p) {
    final ls = p.lSh, rs = p.rSh, le = p.lEl, re = p.rEl, lw = p.lWr, rw = p.rWr;
    final w = p.shoulderWidth;
    if (ls == null || rs == null || le == null || re == null) return false;
    if (lw == null || rw == null || w == null) return false;
    final elbowsLevel =
        (le.y - ls.y).abs() / w < 0.4 && (re.y - rs.y).abs() / w < 0.4;
    final elbowsWide = (le.x - re.x).abs() / w > 1.3;
    final handsUp = lw.y < le.y + 0.1 * w && rw.y < re.y + 0.1 * w;
    return elbowsLevel && elbowsWide && handsUp;
  }

  /// 몸통을 돌리면 화면에서 어깨너비가 줄어든다 — 이 동작 중 가장 넓었던
  /// 어깨너비의 75% 아래로 줄면. (기준 폭은 [RepCounter] 가 동작마다 새로 잰다.)
  static bool _twist(PoseView p) {
    final w = p.shoulderWidth;
    final base = p.twistBase;
    if (w == null || base == null || base <= 0) return false;
    return w / base < 0.75;
  }
}

/// 동작 자세를 [holdFor] 이상 유지했다가 풀면 1회로 센다.
class RepCounter {
  RepCounter(this.check, {this.holdFor = const Duration(milliseconds: 700)});

  final PoseCheck check;
  final Duration holdFor;

  DateTime? _activeSince;
  bool _held = false;
  double _maxShoulder = 0;

  /// 지금 동작 자세를 유지하고 있는지 (화면 배지용).
  bool get holding => _held;

  /// 프레임 하나를 넣는다. 1회가 완성되면 true.
  bool add(Pose pose, DateTime at) {
    final view = PoseView(pose);
    final w = view.shoulderWidth;
    if (w != null && w > _maxShoulder) _maxShoulder = w;
    view.twistBase = _maxShoulder;

    final active = check(view);
    if (active) {
      _activeSince ??= at;
      if (!_held && at.difference(_activeSince!) >= holdFor) _held = true;
      return false;
    }
    _activeSince = null;
    if (_held) {
      _held = false;
      return true; // 유지했다가 풀었다 → 1회
    }
    return false;
  }

  void reset() {
    _activeSince = null;
    _held = false;
    _maxShoulder = 0;
  }
}
