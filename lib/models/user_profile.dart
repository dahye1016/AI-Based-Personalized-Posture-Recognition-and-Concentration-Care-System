/// 사용자 프로필 — 계정별로 자세 기록을 저장하기 위한 최소 정보.
///
/// 비밀번호가 없으므로 "로그인"이라기보다 프로필 등록에 가깝다.
/// 기기를 바꾸면 같은 계정으로 돌아올 수 없다. 인증이 필요해지면
/// 이 모델에 식별자(email 등)를 더하고 서버 쪽 auth 를 붙여야 한다.
class UserProfile {
  const UserProfile({
    required this.name,
    this.birthYear,
    this.birthMonth,
    this.birthDay,
    this.gender = Gender.unspecified,
  });

  final String name;

  final int? birthYear;
  final int? birthMonth;
  final int? birthDay;

  final Gender gender;

  bool get hasBirth =>
      birthYear != null && birthMonth != null && birthDay != null;

  /// "2003. 05. 14"
  String get birthLabel {
    if (!hasBirth) return '입력 안 함';
    final m = birthMonth!.toString().padLeft(2, '0');
    final d = birthDay!.toString().padLeft(2, '0');
    return '$birthYear. $m. $d';
  }

  /// 만 나이. 생년월일이 없으면 null.
  int? ageAt(DateTime now) {
    if (!hasBirth) return null;
    var age = now.year - birthYear!;
    final beforeBirthday = now.month < birthMonth! ||
        (now.month == birthMonth! && now.day < birthDay!);
    if (beforeBirthday) age--;
    return age;
  }

  /// 서버로 보낼 형태. `POST /users` 가 생기면 그대로 쓴다.
  Map<String, dynamic> toJson() => {
        'name': name,
        if (hasBirth)
          'birth_date': '$birthYear-'
              '${birthMonth!.toString().padLeft(2, '0')}-'
              '${birthDay!.toString().padLeft(2, '0')}',
        'gender': gender.code,
      };
}

enum Gender {
  female('female', '여성'),
  male('male', '남성'),
  unspecified('unspecified', '선택 안 함');

  const Gender(this.code, this.label);

  /// 서버 전송용 값
  final String code;

  /// 화면 표시용 값
  final String label;
}
