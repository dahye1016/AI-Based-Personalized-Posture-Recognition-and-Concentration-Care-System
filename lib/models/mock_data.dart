import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'posture_class.dart';

/// UI 렌더용 목업(가짜) 데이터.
/// 센서/BLE가 붙기 전까지 화면을 그대로 띄우기 위한 값들이다.
/// 나중에 BleService/ApiService 결과로 이 값들만 갈아끼우면 된다.

class PostureSlice {
  final PostureClass posture;
  final int percent;
  const PostureSlice(this.posture, this.percent);

  String get label => posture.label;
  Color get color => posture.color;
}

class BadgeItem {
  final String label;
  final IconData icon;
  final bool unlocked;
  final Color color;
  const BadgeItem(this.label, this.icon, this.unlocked, this.color);
}

class RegisterPose {
  final PostureClass posture;
  final PoseRegState state;
  const RegisterPose(this.posture, this.state);

  String get label => posture.label;
}

enum PoseRegState { done, active, todo }

class MockData {
  // ── 홈 ──────────────────────────────
  static const currentPosture = PostureClass.straight;
  static const currentHold = '24분 유지 중';
  static const sitTime = '4h 12m';
  static const goodRatio = '78%';
  static const alertCount = '6';

  // 좌석 / 등받이 압력(0~1). 각 6칸씩 예시.
  static const seatPressure = <double>[0.1, 0.6, 0.2, 0.5, 0.9, 0.3];
  static const backPressure = <double>[0.4, 0.7, 0.5, 0.8, 0.6, 0.4];

  // ── 리포트 ──────────────────────────
  // 합계 100%. 미착석(id 0)은 '자세 분포'에서 제외한다.
  static const distribution = <PostureSlice>[
    PostureSlice(PostureClass.straight, 52),
    PostureSlice(PostureClass.leanForward, 18),
    PostureSlice(PostureClass.leanRight, 10),
    PostureSlice(PostureClass.leanLeft, 8),
    PostureSlice(PostureClass.crossLegRight, 7),
    PostureSlice(PostureClass.crossLegLeft, 5),
  ];

  // 시간대별 막대(값 0~1, 색상 카테고리)
  static const hourly = <MapEntry<double, Color>>[
    MapEntry(0.55, AppColors.postureGood),
    MapEntry(0.72, AppColors.postureGood),
    MapEntry(0.40, AppColors.postureLean),
    MapEntry(0.85, AppColors.postureGood),
    MapEntry(0.68, AppColors.postureGood),
    MapEntry(0.35, AppColors.postureCross),
    MapEntry(0.45, AppColors.postureLean),
    MapEntry(0.60, AppColors.postureGood),
  ];

  // ── 챌린지 ──────────────────────────
  static const challengeDone = 21;
  static const challengeGoal = 30;
  static const week = <double>[1.0, 1.0, 0.0, 1.0, 1.0, 0.4, 0.0]; // 월~일
  static const badges = <BadgeItem>[
    BadgeItem('5일 연속', Icons.local_fire_department, true, AppColors.warnIcon),
    BadgeItem('첫 완주', Icons.emoji_events, true, AppColors.infoText),
    BadgeItem('잠김', Icons.lock, false, AppColors.textTertiary),
  ];

  // ── 초기 설정(자세 등록) ─────────────
  // 등록 대상 6종 = 7클래스에서 미착석 제외.
  static const registerPoses = <RegisterPose>[
    RegisterPose(PostureClass.straight, PoseRegState.done),
    RegisterPose(PostureClass.leanForward, PoseRegState.done),
    RegisterPose(PostureClass.crossLegRight, PoseRegState.active),
    RegisterPose(PostureClass.crossLegLeft, PoseRegState.todo),
    RegisterPose(PostureClass.leanRight, PoseRegState.todo),
    RegisterPose(PostureClass.leanLeft, PoseRegState.todo),
  ];

  // ── 내 정보 ─────────────────────────
  static const userName = '김예원';
  static const userSince = '함께한 지 12일';
  static const seatBattery = 82;
  static const backBattery = 67;
}
