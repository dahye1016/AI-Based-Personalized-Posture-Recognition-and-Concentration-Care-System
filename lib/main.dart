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
/// 센서 연결([BleService])은 여기서 하나만 만들어 정자세 측정과 실시간 화면이
/// 함께 쓴다. 좌석(PoseLab-Seat)·등받이(PoseLab-Back)는 이름으로 구분해 연결된다.
/// BLE 가 없는 환경(시뮬레이터)에서는 측정 단계에 데이터가 들어오지 않는다.
class AppFlow extends StatefulWidget {
  const AppFlow({super.key});

  @override
  State<AppFlow> createState() => _AppFlowState();
}

enum _Phase { splash, login, onboarding, calibration, main }

class _AppFlowState extends State<AppFlow> {
  /// 앱 전체에서 하나만 쓰는 센서 연결 (좌석 PoseLab-Seat + 등받이 PoseLab-Back).
  /// 정자세 측정에서 연결을 시작하고, 메인(실시간 화면)이 그대로 이어 쓴다.
  /// 화면마다 따로 연결하면 스캔·연결이 서로 끊는 문제가 있어 하나로 합쳤다.
  BleService? _ble;
  _Phase _phase = _Phase.splash;

  @override
  void dispose() {
    _ble?.dispose();
    super.dispose();
  }

  void _go(_Phase next) {
    if ((next == _Phase.calibration || next == _Phase.main) && _ble == null) {
      _ble = BleService()..connect();
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
          ble: _ble!,
          onDone: (_) => _go(_Phase.main),
        ),
      _Phase.main => RootNav(ble: _ble),
    };
  }
}

/// 하단 탭 — 피그마 TabBar 컴포넌트와 동일하게 4개.
/// 실시간 / 리포트 / 챌린지 / 스트레칭
class RootNav extends StatefulWidget {
  const RootNav({super.key, this.ble});

  /// 앱이 들고 있는 센서 연결. 없으면(테스트 등) 실시간 화면이 직접 만든다.
  final BleService? ble;

  @override
  State<RootNav> createState() => _RootNavState();
}

class _RootNavState extends State<RootNav> {
  final ApiService _api = ApiService();
  int _index = 0;

  late final List<Widget> _pages = [
    HomeScreen(api: _api, ble: widget.ble),
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
