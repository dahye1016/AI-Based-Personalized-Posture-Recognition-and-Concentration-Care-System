import 'package:flutter/material.dart';

/// ─────────────────────────────────────────────────────────────
/// PostureCare 디자인 시스템 (라이트/화이트 테마)
/// 목업의 초록 포인트를 유지하되 배경을 화이트로 전환한 버전.
/// UI/UX 담당이 색·글꼴·간격을 이 한 파일에서 관리한다.
/// ─────────────────────────────────────────────────────────────
class AppColors {
  // 배경 / 표면
  static const bg = Color(0xFFFFFFFF); // 화면 배경 = 하얀색
  static const surface = Color(0xFFF5F7F8); // 카드 기본
  static const surfaceAlt = Color(0xFFEEF1F3); // 살짝 진한 카드
  static const border = Color(0xFFE7EBEE);

  // 포인트(초록)
  static const primary = Color(0xFF16A47C);
  static const primaryDark = Color(0xFF0E7A5B);

  // 텍스트
  static const textPrimary = Color(0xFF14181B);
  static const textSecondary = Color(0xFF636C74);
  static const textTertiary = Color(0xFF9AA2A9);

  // 상태 배너
  static const goodBg = Color(0xFFE6F6EF);
  static const goodText = Color(0xFF12805C);
  static const warnBg = Color(0xFFFFF3E2);
  static const warnText = Color(0xFFB4720C);
  static const warnIcon = Color(0xFFE9A23B);
  static const infoBg = Color(0xFFE9F1FE);
  static const infoText = Color(0xFF1D5FC4);

  // 자세 분류별 색 (분포/차트 공통)
  static const postureGood = Color(0xFF23A06B); // 정자세
  static const postureLean = Color(0xFFE7A33C); // 앞으로 숙이기
  static const postureCross = Color(0xFFE0674A); // 다리 꼬기
  static const postureTilt = Color(0xFF7C6FD6); // 좌우 기울기

  // 히트맵 압력 단계 (낮음 → 높음)
  static const heatScale = <Color>[
    Color(0xFFEDF0F2), // 0 - 없음
    Color(0xFFD3EEE0), // 1
    Color(0xFF9FD8BE), // 2
    Color(0xFF57BE95), // 3
    Color(0xFF1E9E74), // 4
    Color(0xFF127A57), // 5 - 최고
  ];

  static Color heat(double t) {
    // t: 0.0 ~ 1.0 → 단계 색
    if (t <= 0) return heatScale[0];
    final idx = (t * (heatScale.length - 1)).clamp(0, heatScale.length - 1);
    return heatScale[idx.round()];
  }
}

/// 공통 간격 / 라운드
class AppSpacing {
  static const screen = 20.0;
  static const card = 16.0;
  static const radiusCard = 20.0;
  static const radiusChip = 12.0;
}

/// 텍스트 스타일 모음
class AppText {
  static const screenTitle = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
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
    height: 1.4,
  );
  static const caption = TextStyle(
    fontSize: 12,
    color: AppColors.textTertiary,
  );
  static const statNumber = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
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
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.bg,
      indicatorColor: AppColors.goodBg,
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
