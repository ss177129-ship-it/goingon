import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/login_screen.dart';
import 'screens/nickname_screen.dart';
import 'screens/root_screen.dart';
import 'services/auth_service.dart';
import 'theme.dart';
import 'widgets/brand_mark.dart';

import 'firebase_options.dart';

const _kHasLaunchedBeforeKey = 'has_launched_before';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await GoogleSignIn.instance.initialize();
  runApp(const GoingOnApp());
}

class GoingOnApp extends StatelessWidget {
  const GoingOnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GoingOn',
      debugShowCheckedModeBanner: false,
      theme: GoTheme.light(),
      home: const SplashGate(),
    );
  }
}

/// 스플래시 (프로토타입 s-splash) → 로그인/홈으로
///
/// 최초 실행은 브랜드 각인을 위해 최소 2초 보여주고, 재실행은 인위적 대기 없이
/// (깜빡임 방지용 최소 300ms만 보장) authStateChanges 첫 이벤트가 오는 즉시 넘어감.
/// 탭하면 이 대기를 건너뛰고 바로 전환됨.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key});

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  final _skip = Completer<void>();
  Widget? _destination;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);
    _resolve();
  }

  Future<void> _resolve() async {
    final prefs = await SharedPreferences.getInstance();
    final isFirstLaunch = !(prefs.getBool(_kHasLaunchedBeforeKey) ?? false);
    final minShow =
        Duration(milliseconds: isFirstLaunch ? 2000 : 300);

    final authFuture = FirebaseAuth.instance.authStateChanges().first;
    final gated = Future.wait([authFuture, Future.delayed(minShow)])
        .then((results) => results[0] as User?);
    final skipped = _skip.future.then((_) => authFuture);

    final user = await Future.any([gated, skipped]);

    // 로그인은 됐지만(Apple 인증 완료) 프로필(닉네임/초대코드)이 아직
    // 없는 경우가 있음 — 예: 닉네임 입력 전에 앱이 죽었다가 재실행된 경우.
    // 그대로 홈으로 보내면 빈 프로필로 갇히므로, 그 경우엔 닉네임 화면으로 보냄
    var hasProfile = false;
    if (user != null) {
      hasProfile = await AuthService().myProfile() != null;
    }

    if (isFirstLaunch) {
      await prefs.setBool(_kHasLaunchedBeforeKey, true);
    }
    if (!mounted) return;
    setState(() {
      if (user == null) {
        _destination = const LoginScreen();
      } else if (!hasProfile) {
        _destination = const NicknameScreen();
      } else {
        _destination = const RootScreen();
      }
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      child: _destination != null
          ? KeyedSubtree(key: const ValueKey('dest'), child: _destination!)
          : GestureDetector(
              key: const ValueKey('splash'),
              onTap: () {
                if (!_skip.isCompleted) _skip.complete();
              },
              child: _splash(),
            ),
    );
  }

  Widget _splash() {
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // 브랜드 마크 — 숨쉬는 두 원
                // 네이티브 런치스크린(brand_mark.png)과 같은 단색 스타일 —
                // 앱이 켜지는 순간 그림이 안 바뀌어야 하나의 화면처럼 보여요
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) => BrandMark.pulsing(
                    leftScale: 1 + _pulse.value * .16,
                    rightScale: 1 + (1 - _pulse.value) * .16,
                  ),
                ),
                const SizedBox(height: 30),
                Text('goingon', style: GoTheme.serif(42)),
                const SizedBox(height: 20),
                Text('멀리 있어도, 함께',
                    style: GoTheme.serif(15, color: GoColors.mid)),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 46),
            child: Opacity(
              opacity: .75,
              child: const Text('화면을 누르면 시작해요',
                  style: TextStyle(
                      fontSize: 11, letterSpacing: .5, color: GoColors.dim)),
            ),
          ),
        ]),
      ),
    );
  }
}
