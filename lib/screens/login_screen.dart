import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/user_profile.dart';
import '../services/profile_store.dart';
import '../theme/app_theme.dart';
import '../widgets/bm.dart';

/// 로그인(프로필 입력) — 피그마 「00b 로그인 · 프로필 입력」.
///
/// 이름 / 생년월일 / 성별만 받는다. 비밀번호가 없으므로 계정 복구는 안 된다.
/// 저장은 [ProfileStore] 로 가고, 지금은 메모리에만 남는다.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onDone, this.onSkip});

  final ValueChanged<UserProfile> onDone;
  final VoidCallback? onSkip;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _name = TextEditingController();
  final _year = TextEditingController();
  final _month = TextEditingController();
  final _day = TextEditingController();

  Gender _gender = Gender.unspecified;

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _year, _month, _day]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _year, _month, _day]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _canSubmit => _name.text.trim().isNotEmpty;

  /// 생년월일은 선택 입력이다. 셋 다 채워지고 값이 말이 될 때만 쓴다.
  bool get _birthValid {
    final y = int.tryParse(_year.text);
    final m = int.tryParse(_month.text);
    final d = int.tryParse(_day.text);
    if (y == null || m == null || d == null) return false;
    final now = DateTime.now().year;
    return y >= 1900 && y <= now && m >= 1 && m <= 12 && d >= 1 && d <= 31;
  }

  void _submit() {
    final profile = UserProfile(
      name: _name.text.trim(),
      birthYear: _birthValid ? int.parse(_year.text) : null,
      birthMonth: _birthValid ? int.parse(_month.text) : null,
      birthDay: _birthValid ? int.parse(_day.text) : null,
      gender: _gender,
    );
    ProfileStore.instance.save(profile);
    widget.onDone(profile);
  }

  @override
  Widget build(BuildContext context) {
    final birthTyped = _year.text.isNotEmpty ||
        _month.text.isNotEmpty ||
        _day.text.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: BmScreen(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 헤드라인
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen, 40, AppSpacing.screen, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('처음 오셨네요',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      )),
                  const SizedBox(height: 10),
                  Text('어떻게 불러드릴까요?', style: AppText.display),
                  const SizedBox(height: 10),
                  const Text('자세 기록을 계정별로 저장하려면 이 정보가 필요해요.',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        color: AppColors.textSecondary,
                      )),
                ],
              ),
            ),

            // 입력 폼
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screen),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _FieldLabel('이름'),
                  const SizedBox(height: 8),
                  _TextBox(
                    controller: _name,
                    hint: '예) 정아로',
                    maxLength: 20,
                  ),
                  const SizedBox(height: 22),

                  _FieldLabel('생년월일'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: _TextBox(
                          controller: _year,
                          hint: '2003',
                          suffix: '년',
                          number: true,
                          maxLength: 4,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _TextBox(
                          controller: _month,
                          hint: '05',
                          suffix: '월',
                          number: true,
                          maxLength: 2,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _TextBox(
                          controller: _day,
                          hint: '14',
                          suffix: '일',
                          number: true,
                          maxLength: 2,
                        ),
                      ),
                    ],
                  ),
                  if (birthTyped && !_birthValid) ...[
                    const SizedBox(height: 8),
                    const Text('날짜를 다시 확인해 주세요',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.warnIcon,
                        )),
                  ],
                  const SizedBox(height: 22),

                  _FieldLabel('성별'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final g in Gender.values) ...[
                        if (g != Gender.values.first) const SizedBox(width: 8),
                        Expanded(
                          child: _GenderChip(
                            label: g.label,
                            selected: _gender == g,
                            onTap: () => setState(() => _gender = g),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // 안내
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen, 22, AppSpacing.screen, 0),
              child: BmSoftCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lock_outline_rounded,
                        size: 16, color: AppColors.textTertiary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '나이와 성별은 체형 차이를 감안해 자세를 판단하는 데만 쓰여요. '
                        '다른 곳에 공유하지 않습니다.',
                        style: AppText.caption.copyWith(height: 1.6),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const Spacer(),

            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen, 12, AppSpacing.screen, 12),
              child: Column(
                children: [
                  BmPrimaryButton(
                    label: '시작하기',
                    onPressed: _canSubmit ? _submit : null,
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () {
                      ProfileStore.instance.skip();
                      (widget.onSkip ?? () {})();
                    },
                    child: const Text('나중에 입력할래요',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textTertiary,
                        )),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ));
}

class _TextBox extends StatelessWidget {
  const _TextBox({
    required this.controller,
    required this.hint,
    this.suffix,
    this.number = false,
    this.maxLength,
  });

  final TextEditingController controller;
  final String hint;
  final String? suffix;
  final bool number;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: number ? TextInputType.number : TextInputType.name,
      inputFormatters: [
        if (number) FilteringTextInputFormatter.digitsOnly,
        if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
      ],
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      ),
      cursorColor: AppColors.primary,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Color(0xFFB8C0C7),
        ),
        suffixText: suffix,
        suffixStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.textTertiary,
        ),
        counterText: '',
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }
}

class _GenderChip extends StatelessWidget {
  const _GenderChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySoft : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: selected
              ? Border.all(color: AppColors.primary, width: 1.5)
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.primary : AppColors.textTertiary,
          ),
        ),
      ),
    );
  }
}
