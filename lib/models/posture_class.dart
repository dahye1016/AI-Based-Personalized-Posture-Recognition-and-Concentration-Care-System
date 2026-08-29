import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 자세 클래스 **단일 출처**.
///
/// 화면·판정기·목데이터가 각자 문자열로 들고 있던 자세 이름을 여기로 모았다.
/// 라벨/색/문구를 바꿀 일이 생기면 이 파일만 고치면 된다.
///
/// ## [id] 는 함부로 바꾸지 말 것
/// 0~6 은 팀 확정 7클래스이며, 이 숫자가 그대로
///   · 다혜 TFLite 모델의 출력 인덱스
///   · 서버 `posture_logs.posture` 컬럼 값
/// 이다. 순서를 바꾸거나 중간에 값을 끼워 넣으면 저장된 기록과 어긋난다.
///
/// ## [id] 가 null 인 값 = 잠정값
/// 규칙 기반 판정기([PostureClassifier])가 아직 7클래스를 다 못 가려서
/// 임시로 쓰는 값이다. TFLite 로 교체할 때 해당 분기와 함께 지운다.
/// null 이므로 모델 인덱스·서버 값과 구조적으로 충돌할 수 없다.
enum PostureClass {
  // ── 팀 확정 7클래스 (id = TFLite 출력 인덱스) ──────────────────
  notSitting(
    id: 0,
    label: '앉지 않음',
    message: '의자에 앉으면 자세를 측정할게요.',
    color: AppColors.textTertiary,
  ),
  straight(
    id: 1,
    label: '정자세',
    message: '좋아요! 바른 자세를 유지하고 있어요.',
    color: AppColors.postureGood,
  ),
  leanForward(
    id: 2,
    label: '앞으로 숙이기',
    message: '상체가 앞으로 쏠렸어요. 허리를 세우고 등을 붙여주세요.',
    advice: '허리와 목에 부담이 쌓이고 있어요.\n잠깐 펴고 가실래요?',
    color: AppColors.postureLean,
    isBad: true,
  ),
  crossLegRight(
    id: 3,
    label: '오른다리 꼬기',
    message: '오른다리를 꼬고 있어요! 골반이 틀어질 수 있어요.',
    advice: '골반이 한쪽으로 틀어지고 있어요.\n다리를 풀고 잠깐 움직여요.',
    color: AppColors.postureCross,
    isBad: true,
  ),
  crossLegLeft(
    id: 4,
    label: '왼다리 꼬기',
    message: '왼다리를 꼬고 있어요! 골반이 틀어질 수 있어요.',
    advice: '골반이 한쪽으로 틀어지고 있어요.\n다리를 풀고 잠깐 움직여요.',
    color: AppColors.postureCross,
    isBad: true,
  ),
  leanRight(
    id: 5,
    label: '오른쪽 기대기',
    message: '몸이 오른쪽으로 기울었어요. 가운데로 앉아주세요.',
    advice: '몸이 한쪽으로 기울어 있어요.\n가운데로 앉아 잠깐 움직여요.',
    color: AppColors.postureTilt,
    isBad: true,
  ),
  leanLeft(
    id: 6,
    label: '왼쪽 기대기',
    message: '몸이 왼쪽으로 기울었어요. 가운데로 앉아주세요.',
    advice: '몸이 한쪽으로 기울어 있어요.\n가운데로 앉아 잠깐 움직여요.',
    color: AppColors.postureTilt,
    isBad: true,
  ),

  // ── 잠정값 (id 없음). TFLite 교체 시 제거 ──────────────────────
  /// 규칙 판정기는 `(left-right).abs()` 로 좌우 부호를 버려서
  /// [crossLegRight] / [crossLegLeft] 를 못 가른다. 그 동안 쓰는 값.
  crossLegUnknown(
    label: '다리 꼬기',
    message: '다리를 꼬고 있어요! 골반이 틀어질 수 있어요.',
    advice: '골반이 한쪽으로 틀어지고 있어요.\n다리를 풀고 잠깐 움직여요.',
    color: AppColors.postureCross,
    isBad: true,
  ),

  /// 등받이 쪽으로 파묻힌 상태. 팀 확정 7클래스에는 없지만
  /// 규칙 판정기에 해당 분기가 살아 있어 표시가 필요하다.
  leanBack(
    label: '등받이에 기대기',
    message: '등받이에 너무 기대고 있어요. 앞으로 조금 당겨주세요.',
    advice: '허리가 무너진 채로 오래 있었어요.\n앞으로 당겨 앉아볼까요?',
    color: AppColors.postureTilt,
    isBad: true,
  ),

  /// 아직 판정할 프레임이 없는 상태 (연결 중 / 데이터 부족).
  waiting(
    label: '연결 중',
    message: '센서 데이터를 기다리는 중...',
    color: AppColors.textTertiary,
  );

  const PostureClass({
    required this.label,
    required this.message,
    required this.color,
    this.id,
    this.advice = '같은 자세가 너무 오래 이어졌어요.\n잠깐 움직여 주세요.',
    this.isBad = false,
  });

  /// TFLite 출력 인덱스 겸 서버 `posture_logs.posture` 값.
  /// null 이면 7클래스가 아닌 잠정값이다.
  final int? id;

  /// 화면에 보여줄 한글 이름.
  final String label;

  /// 실시간 화면에 띄우는 한 줄 안내.
  final String message;

  /// 알림 화면에 띄우는 두 줄 권유 문구.
  final String advice;

  /// 자세 색 (타임라인 띠·알림 카드 공용).
  final Color color;

  /// 경고 대상인지. 알림·스트레칭 유도의 기준이 된다.
  final bool isBad;

  /// 팀 확정 7클래스만, id 순서대로.
  static const List<PostureClass> canonical = [
    notSitting,
    straight,
    leanForward,
    crossLegRight,
    crossLegLeft,
    leanRight,
    leanLeft,
  ];

  /// 알림을 띄울 수 있는 7클래스 (잠정값 제외).
  static List<PostureClass> get badClasses =>
      canonical.where((p) => p.isBad).toList();

  /// TFLite 출력 인덱스 / 서버 값 -> 클래스.
  /// 0~6 이 아니면 [StateError].
  static PostureClass fromId(int id) => canonical.firstWhere(
        (p) => p.id == id,
        orElse: () => throw StateError('알 수 없는 자세 id: $id (0~6 이어야 함)'),
      );
}
