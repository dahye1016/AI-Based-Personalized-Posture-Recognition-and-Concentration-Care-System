import 'package:flutter/foundation.dart';

import '../models/user_profile.dart';
import 'sitting_stats.dart';

/// 사용자 프로필 보관소.
///
/// ⚠ 지금은 메모리에만 있다. 앱을 껐다 켜면 사라져서 로그인 화면이 다시 뜬다.
///
/// 실제로 쓰려면 두 가지가 더 필요하다.
///   1. 기기 저장 — `shared_preferences` 로 프로필과 서버가 준 user_id 를 남긴다
///   2. 서버 — `POST /users` 로 프로필을 만들고 user_id 를 받아온다
///      (현재 서버에는 users 테이블에 이름·생년월일·성별 컬럼이 없고
///       사용자 생성 엔드포인트도 없다)
class ProfileStore extends ChangeNotifier {
  ProfileStore._();

  static final ProfileStore instance = ProfileStore._();

  UserProfile? _profile;

  /// 서버가 발급한 사용자 번호. 아직 발급 수단이 없어 임시로 1을 쓴다.
  int userId = 1;

  UserProfile? get profile => _profile;

  bool get hasProfile => _profile != null;

  /// 화면에 부를 이름. 프로필이 없으면 기본값.
  String get displayName => _profile?.name ?? '사용자';

  void save(UserProfile profile) {
    _profile = profile;
    // 리포트(착석 기록)를 이 사람 것으로 바꾼다.
    SittingStats.instance.switchUser(recordKey);
    notifyListeners();
  }

  /// "나중에 입력할래요" 로 건너뛴 경우.
  void skip() {
    _profile = null;
    SittingStats.instance.switchUser(SittingStats.guestKey);
    notifyListeners();
  }

  void clear() {
    _profile = null;
    SittingStats.instance.switchUser(SittingStats.guestKey);
    notifyListeners();
  }

  /// 기기 안에서 사용자를 구분하는 키 — 이름 + 생년월일.
  /// 같은 이름·생일로 다시 로그인하면 이전 기록이 이어진다. 로그인 안 하면 guest.
  String get recordKey {
    final p = _profile;
    if (p == null) return SittingStats.guestKey;
    final birth = p.hasBirth
        ? '${p.birthYear}-${p.birthMonth}-${p.birthDay}'
        : 'nobirth';
    return 'user:${p.name.trim()}:$birth';
  }
}
