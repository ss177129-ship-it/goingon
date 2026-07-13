import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../services/auth_service.dart';
import '../theme.dart';
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

  /// 인증 성공 후 공통 분기 — 예전에 가입한 적 있으면(재로그인) 바로 홈,
  /// 신규면 닉네임 설정 화면으로 (제공자가 준 이름이 있으면 미리 채워줌)
  Future<void> _afterAuth(String? name) async {
    final profile = await AuthService().myProfile();
    if (!mounted) return;
    if (profile != null) {
      Navigator.pushAndRemoveUntil(context,
          MaterialPageRoute(builder: (_) => const RootScreen()), (_) => false);
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => NicknameScreen(prefill: name),
      ));
    }
  }

  Future<void> _continueWithApple() async {
    setState(() => _loading = true);
    try {
      final name = await AuthService().signInWithApple();
      if (!mounted) return;
      await _afterAuth(name);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Apple 로그인에 실패했어요. 다시 시도해 주세요.')),
      );
    }
  }

  Future<void> _continueWithGoogle() async {
    setState(() => _loading = true);
    try {
      final name = await AuthService().signInWithGoogle();
      if (!mounted) return;
      await _afterAuth(name);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Google 로그인에 실패했어요. 다시 시도해 주세요.')),
      );
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
              const Spacer(),
              // 브랜드 마크 — 두 원이 나란히 (나 lime, 너 coral)
              SizedBox(
                width: 74, height: 46,
                child: Stack(children: [
                  Positioned(
                    left: 3, top: 4,
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: GoColors.lime.withOpacity(.4),
                        border: Border.all(color: GoColors.limeDark, width: 2),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 3, top: 4,
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: GoColors.coral.withOpacity(.35),
                        border: Border.all(color: GoColors.coralDark, width: 2),
                      ),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              Text('goingon', style: GoTheme.serif(20, color: GoColors.dim)),
              const SizedBox(height: 18),
              Text('멀리 있어도,\n함께 달려요',
                  textAlign: TextAlign.center, style: GoTheme.serif(30)),
              const SizedBox(height: 8),
              const Text('소중한 사람과 발을 맞추는 곳',
                  style: TextStyle(fontSize: 13, color: GoColors.mid)),
              const Spacer(),
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
                    side: BorderSide(color: GoColors.ink.withOpacity(.15)),
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
