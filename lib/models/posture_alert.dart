import 'posture_class.dart';

/// 나쁜 자세가 오래 이어져 사용자에게 알린 기록 한 건.
class PostureAlert {
  const PostureAlert({
    required this.posture,
    required this.heldFor,
    required this.at,
    this.stretched = false,
  });

  /// 어떤 자세로 알림이 났는지. 라벨·색·문구는 [PostureClass] 가 들고 있다.
  final PostureClass posture;

  /// 알림을 띄운 시점까지 그 자세를 유지한 시간.
  final Duration heldFor;

  /// 알림을 띄운 시각.
  final DateTime at;

  /// 이 알림을 받고 스트레칭까지 했는지.
  final bool stretched;

  PostureAlert copyWith({bool? stretched}) => PostureAlert(
        posture: posture,
        heldFor: heldFor,
        at: at,
        stretched: stretched ?? this.stretched,
      );

  /// "5분 12초 유지"
  String get heldLabel {
    final m = heldFor.inMinutes;
    final sec = heldFor.inSeconds % 60;
    if (m > 0) return '$m분 $sec초 유지';
    return '$sec초 유지';
  }

  /// "14:32"
  String get timeLabel {
    final h = at.hour.toString().padLeft(2, '0');
    final m = at.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
