import 'package:flutter/material.dart';

import 'screens/calibration_screen.dart';
import 'screens/challenge_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/report_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/stretch_screen.dart';
import 'services/api_service.dart';
import 'services/ble_service.dart';
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
/// 정자세 측정 단계에서만 쓰는 [BleService] 를 여기서 만들고,
/// 메인으로 넘어갈 때 끊는다. 실시간 화면([HomeScreen])은 자기 BleService 를
/// 따로 갖고 있어서, 두 연결이 같은 방석을 두고 경합하지 않게 하기 위함.
/// BLE 가 없는 환경(시뮬레이터)에서는 측정 단계에 데이터가 들어오지 않는다.
class AppFlow extends StatefulWidget {
  const AppFlow({super.key});

  @override
  State<AppFlow> createState() => _AppFlowState();
}

enum _Phase { splash, login, onboarding, calibration, main }

class _AppFlowState extends State<AppFlow> {
  /// 정자세 측정용 연결. 메인 진입 시 해제되어 null 이 된다.
  BleService? _calibBle;
  _Phase _phase = _Phase.splash;

  @override
  void dispose() {
    _releaseCalibBle();
    super.dispose();
  }

  void _releaseCalibBle() {
    final ble = _calibBle;
    _calibBle = null;
    ble?.dispose();
  }

  void _go(_Phase next) {
    if (next == _Phase.calibration && _calibBle == null) {
      _calibBle = BleService()..connect();
    } else if (next == _Phase.main) {
      _releaseCalibBle();
    }
    setState(() => _phase = next);
  }

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
          ble: _calibBle!,
          onDone: (_) => _go(_Phase.main),
        ),
      _Phase.main => const RootNav(),
    };
  }
}

/// 하단 탭 — 피그마 TabBar 컴포넌트와 동일하게 4개.
/// 실시간 / 리포트 / 챌린지 / 스트레칭
class RootNav extends StatefulWidget {
  const RootNav({super.key});

  @override
  State<RootNav> createState() => _RootNavState();
}

class _RootNavState extends State<RootNav> {
  final ApiService _api = ApiService();
  int _index = 0;

  late final List<Widget> _pages = [
    HomeScreen(api: _api),
    const ReportScreen(),
    const ChallengeScreen(),
    const StretchScreen(),
  ];

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

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
