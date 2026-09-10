import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../firebase_env.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/go_button.dart';
import '../widgets/brand_mark.dart';
import '../widgets/goingon_wordmark.dart';
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

  /// 연습실 전용 테스트 로그인.
  ///
  /// 왜 필요한가: 2인 흐름을 검증하려면 봇과 마주 볼 사람이 하나 필요한데,
  /// Apple 로그인은 시뮬레이터에 iCloud 계정이 들어가 있어야 동작한다.
  /// 그 준비 때문에 검증 한 번의 비용이 올라가면 결국 검증을 덜 하게 된다.
  ///
  /// **릴리즈에는 들어가지 않는다.** `FirebaseEnv.isStaging`은 컴파일 시점
  /// 상수라 플래그 없이 빌드하면 false로 굳고, 이 분기와 아래 버튼이
  /// 통째로 제거된다. 게다가 이메일/비밀번호 제공자 자체가 연습실에만
  /// 켜져 있어서, 설령 코드가 남아도 운영에서는 로그인이 거부된다 —
  /// 두 겹이다.
  Future<void> _continueAsTester() async {
    setState(() => _loading = true);
    try {
      final auth = FirebaseAuth.instance;
      const email = 'tester@goingon.test';
      const password = 'goingon-staging-tester';
      try {
        await auth.signInWithEmailAndPassword(email: email, password: password);
      } on FirebaseAuthException catch (e) {
        if (e.code != 'user-not-found' && e.code != 'invalid-credential') {
          rethrow;
        }
        await auth.createUserWithEmailAndPassword(
            email: email, password: password);
      }
      if (!mounted) return;
      await _afterAuth('테스터');
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (!mounted) return;
      setState(() => _loading = false);
      GoToast.error(context, '테스트 로그인 실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final roles = GoRoles.of(context);
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
                    const GoingOnWordmark(height: 26),
                    const SizedBox(height: 18),
                    Text('멀리 있어도,\n함께 달려요',
                        textAlign: TextAlign.center, style: GoText.title),
                    const SizedBox(height: 8),
                    Text('소중한 사람과 발을 맞추는 곳',
                        style: TextStyle(fontSize: 13, color: roles.textSecondary)),
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
              const SizedBox(height: GoSpace.m),
              GoButton('Google로 계속하기',
                  kind: GoButtonKind.secondary,
                  enabled: !_loading,
                  onTap: _continueWithGoogle),
              // 연습실에서만 그린다 — 릴리즈 빌드에서는 상수 false라
              // 이 가지가 통째로 사라진다 (_continueAsTester 주석 참조)
              if (FirebaseEnv.isStaging) ...[
                const SizedBox(height: GoSpace.m),
                GoButton('테스터로 계속하기 (연습실)',
                    kind: GoButtonKind.secondary,
                    enabled: !_loading,
                    onTap: _continueAsTester),
              ],
              // **이용약관·개인정보처리방침 고지를 뺐다**(2026-09-01).
              //
              // 예전에는 "계속하면 이용약관과 개인정보처리방침에 동의하는
              // 것으로 간주돼요"라고 적혀 있었는데, **그 두 문서가 존재하지
              // 않는다.** 링크도 없었다. 없는 문서에 동의를 받는 것은 누락이
              // 아니라 사실과 다른 고지이고, 그대로 심사에 내면 리젝 사유다.
              //
              // 문서를 만들고 링크를 붙일 때 이 자리에 다시 넣는다 —
              // 그때는 **누를 수 있는 링크**여야 한다(TODO 심사 준비).
              const SizedBox(height: GoSpace.section),
            ],
          ),
        ),
      ),
    );
  }
}
