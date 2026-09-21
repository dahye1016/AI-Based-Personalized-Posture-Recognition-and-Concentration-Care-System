import 'package:flutter/material.dart';

import 'screens/calibration_screen.dart';
import 'screens/challenge_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/report_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/stretch_screen.dart';
import 'services/fallback_sensor_source.dart';
import 'services/sensor_source.dart';
import 'theme/app_theme.dart';

void main() => runApp(const PostureCareApp());

class PostureCareApp extends StatelessWidget {
  const PostureCareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PostureCare',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const AppFlow(),
    );
  }
}

/// 앱 진입 흐름 — 스플래시 → 로그인 → 온보딩 → 정자세 측정 → 메인 탭.
///
/// 데이터 입구([SensorSource])를 여기서 한 번만 만들어 아래로 내려준다.
///
/// 기본은 **진짜 BLE 만** 쓴다. 방석에 못 붙으면 데이터가 아예 안 흐르고,
/// 실패 지점은 콘솔의 `[BLE]` / `[SOURCE]` 로그에 그대로 남는다.
/// (가짜 데이터가 몰래 흘러서 "연동된 것처럼" 보이는 걸 막기 위함)
///
/// ```bash
/// flutter run                                    # 진짜 BLE 만 (기본)
/// flutter run --dart-define=MOCK_FALLBACK=true   # 방석 못 찾으면 가짜로 폴백
/// flutter run --dart-define=USE_BLE=false        # 처음부터 가짜만 (시뮬레이터용)
/// ```
class AppFlow extends StatefulWidget {
  const AppFlow({super.key});

  @override
  State<AppFlow> createState() => _AppFlowState();
}

enum _Phase { splash, login, onboarding, calibration, main }

class _AppFlowState extends State<AppFlow> {
  static const bool _useBle =
      bool.fromEnvironment('USE_BLE', defaultValue: true);

  late final SensorSource _source;
  _Phase _phase = _Phase.splash;

  @override
  void initState() {
    super.initState();
    if (_useBle) {
      // 방석에 붙는다. 가짜 소스 폴백은 기본으로 꺼져 있고,
      // --dart-define=MOCK_FALLBACK=true 일 때만 켜진다.
      final s = FallbackSensorSource();
      _source = s;
      s.start();
    } else {
      _source = MockSensorSource();
    }
  }

  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }

  void _go(_Phase next) => setState(() => _phase = next);

  @override
  Widget build(BuildContext context) {
    return switch (_phase) {
      _Phase.splash => SplashScreen(
          onLogin: () => _go(_Phase.login),
          onSkip: () => _go(_Phase.onboarding),
        ),
      _Phase.login => LoginScreen(
          onDone: (_) => _go(_Phase.onboarding),
          onSkip: () => _go(_Phase.onboarding),
        ),
      _Phase.onboarding => OnboardingScreen(
          onStart: () => _go(_Phase.calibration),
        ),
      _Phase.calibration => CalibrationScreen(
          source: _source,
          onDone: (_) => _go(_Phase.main),
        ),
      _Phase.main => RootNav(source: _source),
    };
  }
}

/// 하단 탭 — 피그마 TabBar 컴포넌트와 동일하게 4개.
/// 실시간 / 리포트 / 챌린지 / 스트레칭
class RootNav extends StatefulWidget {
  const RootNav({super.key, this.source});

  final SensorSource? source;

  @override
  State<RootNav> createState() => _RootNavState();
}

class _RootNavState extends State<RootNav> {
  int _index = 0;

  late final List<Widget> _pages = [
    HomeScreen(
      source: widget.source,
      // 정자세 카드의 '오늘 리포트 보기' → 리포트 탭으로 전환
      onOpenReport: () => setState(() => _index = 1),
    ),
    const ReportScreen(),
    const ChallengeScreen(),
    const StretchScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.circle_outlined),
            selectedIcon: Icon(Icons.circle),
            label: '실시간',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: '리포트',
          ),
          NavigationDestination(
            icon: Icon(Icons.star_outline_rounded),
            selectedIcon: Icon(Icons.star_rounded),
            label: '챌린지',
          ),
          NavigationDestination(
            icon: Icon(Icons.self_improvement_outlined),
            selectedIcon: Icon(Icons.self_improvement),
            label: '스트레칭',
          ),
        ],
      ),
    );
  }
}
