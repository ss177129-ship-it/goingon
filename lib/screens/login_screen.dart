import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/brand_mark.dart';
import '../widgets/go_toast.dart';
import 'nickname_screen.dart';
import 'root_screen.dart';

/// 온보딩: 로그인 방법을 고르는 화면. 인증에 성공하면 항상 닉네임 설정
/// 화면(NicknameScreen)을 거쳐 홈으로 이동 — 익명 로그인은 없음.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _loading = false;

  /// 인증 성공 후 공통 분기 — 프로필이 **완성돼 있으면** 홈, 아니면 프로필
  /// 화면으로.
  ///
  /// 문서 존재만 보면 안 된다: 아이디 항목이 생기기 전에 만들어진 계정은
  /// 문서는 있지만 아이디가 없어서, 그대로 홈에 들어가면 아무도 그 사람을
  /// 검색으로 찾을 수 없다. 이름은 이미 있는 것을 채워 보내 다시 묻지 않는다
  Future<void> _afterAuth(String? name) async {
    final profile =
        await AuthService().myProfile().timeout(const Duration(seconds: 10));
    if (!mounted) return;
    if (AuthService.isProfileComplete(profile)) {
      Navigator.pushAndRemoveUntil(context,
          MaterialPageRoute(builder: (_) => const RootScreen()), (_) => false);
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) =>
            NicknameScreen(prefill: (profile?['name'] as String?) ?? name),
      ));
    }
  }

  Future<void> _continueWithApple() async {
    setState(() => _loading = true);
    try {
      final name = await AuthService().signInWithApple();
      if (!mounted) return;
      await _afterAuth(name);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (!mounted) return;
      setState(() => _loading = false);
      GoToast.error(context, 'Apple 로그인에 실패했어요. 다시 시도해 주세요.');
    }
  }

  Future<void> _continueWithGoogle() async {
    setState(() => _loading = true);
    try {
      final name = await AuthService().signInWithGoogle();
      if (!mounted) return;
      await _afterAuth(name);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (!mounted) return;
      setState(() => _loading = false);
      GoToast.error(context, 'Google 로그인에 실패했어요. 다시 시도해 주세요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              // 브랜드 영역 — 프로토타입의 .login-top(flex:1, 가운데 정렬)과
              // 동일하게 남은 공간을 하나의 블록으로 채움
              Expanded(
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    BrandMark.standard(),
                    const SizedBox(height: 16),
                    Text('goingon', style: GoTheme.serif(20, color: GoColors.dim)),
                    const SizedBox(height: 18),
                    Text('멀리 있어도,\n함께 달려요',
                        textAlign: TextAlign.center, style: GoTheme.serif(30)),
                    const SizedBox(height: 8),
                    const Text('소중한 사람과 발을 맞추는 곳',
                        style: TextStyle(fontSize: 13, color: GoColors.mid)),
                  ]),
                ),
              ),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: SignInWithAppleButton(
                  onPressed: _loading ? () {} : _continueWithApple,
                  style: SignInWithAppleButtonStyle.black,
                  borderRadius: BorderRadius.circular(16),
                  text: 'Apple로 계속하기',
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    side: BorderSide(color: GoColors.ink.withValues(alpha: .15)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _loading ? null : _continueWithGoogle,
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Text('G',
                        style: TextStyle(fontWeight: FontWeight.w700,
                            fontSize: 16, color: Color(0xFF4285F4))),
                    const SizedBox(width: 9),
                    Text('Google로 계속하기',
                        style: TextStyle(fontSize: 15,
                            fontWeight: FontWeight.w600, color: GoColors.ink)),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              const Text('계속하면 이용약관과 개인정보처리방침에 동의하는 것으로 간주돼요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, color: GoColors.dim)),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
