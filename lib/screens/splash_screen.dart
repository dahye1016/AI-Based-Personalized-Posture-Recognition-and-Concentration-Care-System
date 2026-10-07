import 'dart:async';

import 'package:flutter/material.dart';

import '../services/ble_sensor_source.dart' show BleLinkState;
import '../theme/app_theme.dart';

/// 스플래시 — 피그마 「00 스플래시」.
///
/// 민트 전면 배경에 앱 아이콘과 이름, 그리고 로그인 버튼.
/// 방석 연결은 뒤에서 이미 시작돼 있고, 여기서는 상태만 알린다.
///
/// 하단 상태 문구:
///   - 처음 [minConnecting](3초) 동안은 점 3개가 깜빡이며 '의자와 연결중입니다...'
///   - 그 뒤 BLE 가 연결돼 있으면 점이 체크 표시로 바뀌고 '의자와 연동되었습니다'
///   - 아직 연결 전이면 연결될 때까지 깜빡임을 유지한다.
class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    required this.onLogin,
    required this.onSkip,
    this.linkState,
    this.initialLinkState,
  });

  final VoidCallback onLogin;
  final VoidCallback onSkip;

  /// 방석 BLE 링크 상태 스트림. 없으면(가짜 소스 등) 연결중 표시만 한다.
  final Stream<BleLinkState>? linkState;

  /// 화면이 뜨는 순간의 링크 상태 (이미 연결돼 있을 수 있다).
  final BleLinkState? initialLinkState;

  /// 연결이 빨라도 '연결중' 표시를 최소 이만큼은 보여준다.
  static const Duration minConnecting = Duration(seconds: 3);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  StreamSubscription<BleLinkState>? _sub;
  Timer? _minTimer;
  bool _bleConnected = false;
  bool _minElapsed = false;

  bool get _showConnected => _bleConnected && _minElapsed;

  @override
  void initState() {
    super.initState();
    _bleConnected = widget.initialLinkState == BleLinkState.connected;
    _sub = widget.linkState?.listen((s) {
      if (!mounted) return;
      setState(() => _bleConnected = s == BleLinkState.connected);
    });
    _minTimer = Timer(SplashScreen.minConnecting, () {
      if (mounted) setState(() => _minElapsed = true);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _minTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onLogin = widget.onLogin;
    final onSkip = widget.onSkip;
    final statusLabel =
        _showConnected ? '의자와 연동되었습니다' : '의자와 연결중입니다...';

    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Stack(
        children: [
          // 배경 장식
          Positioned(
            left: -140,
            top: -150,
            child: _Deco(size: 420),
          ),
          Positioned(
            right: -130,
            bottom: -160,
            child: _Deco(size: 320),
          ),

          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 3),

                // 앱 아이콘
                const AppIconMark(size: 104),
                const SizedBox(height: 22),

                // 앱 이름
                Text('posture-care',
                    style: AppText.display.copyWith(
                      fontSize: 40,
                      color: Colors.white,
                      letterSpacing: -0.6,
                    )),
                const SizedBox(height: 12),
                Container(
                  width: 28,
                  height: 3,
                  decoration: BoxDecoration(
                    // ignore: deprecated_member_use
                    color: Colors.white.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '건강한 자세 오래가는 집중력',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    // ignore: deprecated_member_use
                    color: Colors.white.withOpacity(0.92),
                  ),
                ),

                const Spacer(flex: 2),

                // 로그인
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.screen),
                  child: SizedBox(
                    height: AppSpacing.buttonHeight,
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: onLogin,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                              AppSpacing.radiusButton),
                        ),
                      ),
                      child: Text('로그인',
                          style: AppText.button
                              .copyWith(color: AppColors.primary)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: onSkip,
                  child: Text('계정 없이 둘러보기',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        // ignore: deprecated_member_use
                        color: Colors.white.withOpacity(0.85),
                      )),
                ),

                const SizedBox(height: 20),

                // 연결 상태
                SizedBox(
                  height: 20,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _showConnected
                        ? const Icon(Icons.check_circle_rounded,
                            key: ValueKey('ok'), size: 20, color: Colors.white)
                        : const _LoadingDots(key: ValueKey('dots')),
                  ),
                ),
                const SizedBox(height: 10),
                Text(statusLabel,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      // ignore: deprecated_member_use
                      color: Colors.white.withOpacity(0.9),
                    )),
                const SizedBox(height: 14),
                Text('2026 한이음 드림업',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      // ignore: deprecated_member_use
                      color: Colors.white.withOpacity(0.55),
                    )),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 앱 아이콘 — 의자에 바르게 앉은 사람.
///
/// 스플래시 외에 설정·프로필 등에서도 쓸 수 있게 따로 뺐다.
class AppIconMark extends StatelessWidget {
  const AppIconMark({super.key, this.size = 104});

  final double size;

  @override
  Widget build(BuildContext context) {
    // 원본 104pt 기준으로 그린 좌표를 size 에 맞춰 비례 배치한다.
    final k = size / 104;

    Widget part(double x, double y, double w, double h, double r,
        Color c, double opacity) {
      return Positioned(
        left: x * k,
        top: y * k,
        child: Opacity(
          opacity: opacity,
          child: Container(
            width: w * k,
            height: h * k,
            decoration: BoxDecoration(
              color: c,
              borderRadius: BorderRadius.circular(r * k),
            ),
          ),
        ),
      );
    }

    const deep = Color(0xFF168B87); // 의자
    const light = AppColors.primary; // 사람

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30 * k),
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // 의자
          part(64, 22, 10, 46, 5, deep, 1),
          part(32, 66, 42, 10, 5, deep, 1),
          part(34, 76, 7, 14, 3, deep, 0.55),
          part(65, 76, 7, 14, 3, deep, 0.55),
          // 사람
          part(45, 16, 18, 18, 9, light, 1),
          part(48, 34, 15, 24, 7, light, 1),
          part(30, 56, 32, 11, 5, light, 1),
          part(30, 64, 11, 22, 5, light, 0.85),
        ],
      ),
    );
  }
}

class _Deco extends StatelessWidget {
  const _Deco({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        // ignore: deprecated_member_use
        color: Colors.white.withOpacity(0.08),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _LoadingDots extends StatefulWidget {
  const _LoadingDots({super.key});

  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  // ignore: deprecated_member_use
                  color: Colors.white.withOpacity(_opacityFor(i)),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  double _opacityFor(int i) {
    // 0 → 1 을 도는 값에서 점마다 위상을 어긋나게 준다.
    final t = (_c.value + i / 3) % 1.0;
    return 0.3 + 0.7 * (1 - (t - 0.5).abs() * 2);
  }
}
