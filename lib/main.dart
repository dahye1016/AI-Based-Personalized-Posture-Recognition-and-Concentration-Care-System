import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'services/ble_sensor_source.dart';
import 'services/sensor_source.dart';
import 'screens/home_screen.dart';
import 'screens/report_screen.dart';
import 'screens/challenge_screen.dart';
import 'screens/profile_screen.dart';

void main() => runApp(const PostureCareApp());

class PostureCareApp extends StatelessWidget {
  const PostureCareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PostureCare',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const RootNav(),
    );
  }
}

/// 하단 탭: 홈 / 리포트 / 챌린지 / 내정보
class RootNav extends StatefulWidget {
  const RootNav({super.key});

  @override
  State<RootNav> createState() => _RootNavState();
}

class _RootNavState extends State<RootNav> {
  int _index = 0;

  /// 데이터 입구. 실기기에서는 BLE, 그 외에는 가짜 소스로 자동 폴백한다.
  ///
  /// `--dart-define=USE_BLE=false` 로 실행하면 센서 없이 mock 으로 돌릴 수 있다.
  static const bool _useBle =
      bool.fromEnvironment('USE_BLE', defaultValue: true);

  late final SensorSource _source;

  @override
  void initState() {
    super.initState();
    if (_useBle) {
      final ble = BleSensorSource();
      _source = ble;
      // 연결 실패해도 앱은 그대로 뜬다. 프레임이 안 올 뿐이다.
      ble.connect();
    } else {
      _source = MockSensorSource();
    }
  }

  // NOTE: HomeScreen 도 자기 dispose 에서 source.dispose() 를 부른다.
  // StreamController.close() 는 두 번 불러도 안전해서 문제는 없지만,
  // 나중에 소유권을 한쪽으로 정리하는 게 좋다.
  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }

  late final List<Widget> _pages = [
    HomeScreen(source: _source),
    const ReportScreen(),
    const ChallengeScreen(),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '홈',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: '리포트',
          ),
          NavigationDestination(
            icon: Icon(Icons.emoji_events_outlined),
            selectedIcon: Icon(Icons.emoji_events),
            label: '챌린지',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '내정보',
          ),
        ],
      ),
    );
  }
}
