import 'package:flutter/material.dart';

/// ─────────────────────────────────────────────────────────────
/// PostureCare 디자인 시스템 — 배달의민족 스타일 (라이트/화이트)
///
/// 피그마 「한이음 자세케어 앱」과 1:1 대응한다.
///   https://www.figma.com/design/JUemX5BckPcampgyW51fys/한이음-자세케어-앱
///
/// 포인트 색을 초록(#16A47C)에서 배민 민트(#2AC1BC)로 바꾸고,
/// 제목·숫자에 배민 한나체를 쓴다. **클래스·상수 이름은 그대로 두었으므로
/// 화면 코드는 한 줄도 고칠 필요가 없다.** 색·글꼴은 이 파일에서만 관리한다.
/// ─────────────────────────────────────────────────────────────

/// 배민 한나체 패밀리명.
///
/// 폰트 파일이 등록돼 있지 않으면 시스템 기본 한글 폰트로 조용히 폴백된다.
/// (등록 방법은 이 파일 맨 아래 주석 참고. 파일 없이도 빌드는 깨지지 않는다.)
const String kDisplayFont = 'BMHANNA';

class AppColors {
  // 배경 / 표면
  static const bg = Color(0xFFFFFFFF); // 화면 배경 = 하얀색
  static const surface = Color(0xFFF7F8F9); // 카드 기본
  static const surfaceAlt = Color(0xFFEFF2F4); // 살짝 진한 카드
  static const border = Color(0xFFE5E9ED);

  // 포인트(배민 민트)
  static const primary = Color(0xFF2AC1BC);
  static const primaryDark = Color(0xFF1A9E9A);

  /// 민트 옅은 배경. 뱃지·선택 상태에 쓴다.
  static const primarySoft = Color(0xFFE9F9F8);

  /// 민트 중간톤. 비활성 막대·저압력 표시에 쓴다.
  static const primaryMid = Color(0xFFB8EBE8);

  // 텍스트
  static const textPrimary = Color(0xFF1A1A1A);
  static const textSecondary = Color(0xFF636C74);
  static const textTertiary = Color(0xFF8B95A1);

  // 상태 배너
  static const goodBg = Color(0xFFE9F9F8);
  static const goodText = Color(0xFF13857F);
  static const warnBg = Color(0xFFFFF2EA);
  static const warnText = Color(0xFFC24A18);
  static const warnIcon = Color(0xFFFF6B35);
  static const infoBg = Color(0xFFEEF1FB);
  static const infoText = Color(0xFF3B55B8);

  // 자세 분류별 색 (분포/차트 공통) — 피그마 리포트 도넛과 동일
  static const postureGood = Color(0xFF2AC1BC); // 정자세 = 민트
  static const postureLean = Color(0xFFFF6B35); // 앞으로 숙이기(거북목) = 주황
  static const postureCross = Color(0xFF7A51BD); // 다리 꼬기 = 보라
  static const postureTilt = Color(0xFFE4538D); // 좌우 기울기 = 핑크

  // 히트맵 압력 단계 (낮음 → 높음) — 민트 램프
  static const heatScale = <Color>[
    Color(0xFFEFF2F4), // 0 - 없음
    Color(0xFFDDF3F2), // 1
    Color(0xFFB8EBE8), // 2
    Color(0xFF7FDCD8), // 3
    Color(0xFF2AC1BC), // 4
    Color(0xFF17918D), // 5 - 최고
  ];

  static Color heat(double t) {
    // t: 0.0 ~ 1.0 → 단계 색
    if (t <= 0) return heatScale[0];
    final idx = (t * (heatScale.length - 1)).clamp(0, heatScale.length - 1);
    return heatScale[idx.round()];
  }
}

/// 공통 간격 / 라운드 — 피그마 규격에 맞춤
class AppSpacing {
  static const screen = 24.0; // 좌우 여백 (피그마 24)
  static const card = 16.0;
  static const radiusCard = 18.0;
  static const radiusChip = 12.0;

  /// 기본 버튼 라운드 (피그마 14)
  static const radiusButton = 14.0;

  /// 기본 버튼 높이 (피그마 56)
  static const buttonHeight = 56.0;
}

/// 텍스트 스타일 모음
///
/// 제목과 숫자는 한나체, 본문은 시스템 한글 폰트를 쓴다.
/// 배민 톤은 "제목만 큼직하게, 본문은 담백하게"가 핵심이다.
class AppText {
  static const screenTitle = TextStyle(
    fontFamily: kDisplayFont,
    fontSize: 24,
    color: AppColors.textPrimary,
  );
  static const sectionTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );
  static const cardTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );
  static const body = TextStyle(
    fontSize: 14,
    color: AppColors.textSecondary,
    height: 1.5,
  );
  static const caption = TextStyle(
    fontSize: 12,
    color: AppColors.textTertiary,
  );
  static const statNumber = TextStyle(
    fontFamily: kDisplayFont,
    fontSize: 24,
    color: AppColors.textPrimary,
  );

  /// 큰 헤드라인 (측정 안내 등). 신규 화면에서 쓴다.
  static const display = TextStyle(
    fontFamily: kDisplayFont,
    fontSize: 30,
    height: 1.4,
    color: AppColors.textPrimary,
  );

  /// 버튼 라벨.
  static const button = TextStyle(
    fontFamily: kDisplayFont,
    fontSize: 19,
    color: Colors.white,
  );
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: Brightness.light,
  ).copyWith(
    surface: AppColors.bg,
    primary: AppColors.primary,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    fontFamily: 'Pretendard', // 없으면 기본 폰트로 폴백됨
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: AppColors.textPrimary,
      centerTitle: false,
      titleTextStyle: AppText.screenTitle,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        minimumSize: const Size.fromHeight(AppSpacing.buttonHeight),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
        ),
        textStyle: AppText.button,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textTertiary,
        side: const BorderSide(color: AppColors.border),
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
        ),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.bg,
      indicatorColor: AppColors.primarySoft,
      elevation: 0,
      labelTextStyle: MaterialStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(MaterialState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(MaterialState.selected)
              ? AppColors.primary
              : AppColors.textTertiary,
        ),
      ),
    ),
    dividerColor: AppColors.border,
  );
}

// ─────────────────────────────────────────────────────────────
// 배민 한나체 등록 방법
//
// 1) 우아한형제들 배포 페이지에서 `BMHANNA_11yrs_ttf.ttf` 를 받는다.
// 2) `assets/fonts/` 에 넣는다.
// 3) pubspec.yaml 의 `flutter:` 아래에 다음을 추가한다.
//
//      fonts:
//        - family: BMHANNA
//          fonts:
//            - asset: assets/fonts/BMHANNA_11yrs_ttf.ttf
//
// ⚠ 파일을 넣기 전에 pubspec 에 먼저 선언하면 빌드가 깨진다
//   ("asset not found"). 파일을 넣은 뒤에 선언할 것.
//   선언 전까지는 시스템 기본 폰트로 폴백되며 빌드는 정상이다.
// ─────────────────────────────────────────────────────────────
