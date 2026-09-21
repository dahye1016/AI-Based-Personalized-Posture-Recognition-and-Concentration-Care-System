import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// 바른 자세 측정(캘리브레이션) — 15초 동안 사용자의 바른 자세를 측정하는 페이지.
/// 이 값이 나중에 개인 기준(바른자세 baseline)으로 쓰인다.
class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key});

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

enum _Phase { idle, measuring, done }

class _CalibrationScreenState extends State<CalibrationScreen> {
  static const _seconds = 15;
  _Phase _phase = _Phase.idle;
  int _remain = _seconds;
  Timer? _timer;

  void _start() {
    setState(() {
      _phase = _Phase.measuring;
      _remain = _seconds;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _remain--);
      if (_remain <= 0) {
        t.cancel();
        HapticFeedback.mediumImpact();
        setState(() => _phase = _Phase.done);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  double get _progress =>
      _phase == _Phase.done ? 1.0 : (_seconds - _remain) / _seconds;

  @override
  Widget build(BuildContext context) {
    final measuring = _phase == _Phase.measuring;
    final done = _phase == _Phase.done;

    return Scaffold(
      appBar: AppBar(leading: const BackButton(), title: const Text('바른 자세 측정')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.screen, 8, AppSpacing.screen, 24),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Text(
              done ? '측정이 완료됐어요!' : '바른 자세를 측정하겠습니다',
              style: AppText.screenTitle.copyWith(fontSize: 24),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              done
                  ? '이 자세를 기준으로 자세를 판정할게요.'
                  : '15초 동안 편하게 바른 자세로 앉아주세요.',
              style: AppText.body,
              textAlign: TextAlign.center,
            ),
            const Spacer(),

            // 원형 카운트다운
            SizedBox(
              width: 220,
              height: 220,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 220,
                    height: 220,
                    child: CircularProgressIndicator(
                      value: measuring || done ? _progress : 0,
                      strokeWidth: 14,
                      backgroundColor: AppColors.surfaceAlt,
                      valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                    ),
                  ),
                  if (done)
                    const Icon(Icons.check_circle,
                        size: 96, color: AppColors.primary)
                  else
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          measuring ? '$_remain' : '15',
                          style: const TextStyle(
                            fontSize: 64,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(measuring ? '초 남음' : '초', style: AppText.caption),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            PillBadge(
              measuring ? '측정 중…' : (done ? '측정 완료' : '대기 중'),
              bg: measuring ? AppColors.infoBg : AppColors.goodBg,
              fg: measuring ? AppColors.infoText : AppColors.goodText,
            ),

            const Spacer(),

            if (done)
              PrimaryButton(
                label: '완료',
                onPressed: () => Navigator.of(context).pop(),
              )
            else
              PrimaryButton(
                label: measuring ? '측정 중…' : '측정 시작',
                onPressed: measuring ? () {} : _start,
              ),
          ],
        ),
      ),
    );
  }
}
