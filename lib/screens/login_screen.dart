import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../services/auth_service.dart';
import '../theme.dart';
import 'root_screen.dart';

/// 온보딩: Apple로 계속하거나, 닉네임 하나만 받고 바로 시작 (마찰 0 전략)
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _controller = TextEditingController();
  bool _loading = false;

  void _goHome() {
    Navigator.pushAndRemoveUntil(context,
        MaterialPageRoute(builder: (_) => const RootScreen()), (_) => false);
  }

  Future<void> _start() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    setState(() => _loading = true);
    try {
      await AuthService().signInAnonymously(name);
      if (!mounted) return;
      _goHome();
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('연결에 실패했어요. 인터넷을 확인해 주세요.')),
        );
      }
    }
  }

  Future<void> _continueWithApple() async {
    setState(() => _loading = true);
    try {
      final name = await AuthService().signInWithApple();
      if (!mounted) return;
      if (name != null) {
        _goHome();
        return;
      }
      // 이름을 못 받았어요 — 예전에 가입한 적 있는 재로그인인지 확인
      final profile = await AuthService().myProfile();
      if (!mounted) return;
      if (profile != null) {
        _goHome();
      } else {
        // 진짜 신규인데 이름이 안 왔어요 — 닉네임 입력으로 자연스럽게 이어짐
        setState(() => _loading = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Apple 로그인에 실패했어요. 다시 시도해 주세요.')),
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
              const SizedBox(height: 36),
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
              const SizedBox(height: 18),
              Row(children: [
                Expanded(child: Divider(color: GoColors.line)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text('또는',
                      style: TextStyle(fontSize: 11, color: GoColors.dim)),
                ),
                Expanded(child: Divider(color: GoColors.line)),
              ]),
              const SizedBox(height: 18),
              TextField(
                controller: _controller,
                textAlign: TextAlign.center,
                maxLength: 10,
                decoration: InputDecoration(
                  hintText: '뭐라고 부르면 될까요?',
                  counterText: '',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: GoColors.line),
                  ),
                ),
                onSubmitted: (_) => _start(),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: GoColors.ink,
                    padding: const EdgeInsets.symmetric(vertical: 17),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _loading ? null : _start,
                  child: _loading
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text('시작하기',
                          style: GoTheme.serif(19, color: GoColors.paper)),
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
