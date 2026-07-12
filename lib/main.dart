import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/login_screen.dart';
import 'screens/root_screen.dart';
import 'theme.dart';

import 'firebase_options.dart';

const _kHasLaunchedBeforeKey = 'has_launched_before';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
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

    if (isFirstLaunch) {
      await prefs.setBool(_kHasLaunchedBeforeKey, true);
    }
    if (!mounted) return;
    setState(() {
      _destination = user != null ? const RootScreen() : const LoginScreen();
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
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) {
                    final s = 1 + _pulse.value * .09;
                    return SizedBox(
                      width: 88, height: 54,
                      child: Stack(children: [
                        Positioned(
                          left: 4, top: 2,
                          child: Transform.scale(
                            scale: s,
                            child: Container(
                              width: 50, height: 50,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  center: const Alignment(.24, 0),
                                  colors: [
                                    GoColors.lime.withOpacity(.6),
                                    GoColors.lime.withOpacity(.12),
                                  ],
                                ),
                                border: Border.all(
                                    color: GoColors.limeDark, width: 2),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 4, top: 2,
                          child: Transform.scale(
                            scale: 1 + (1 - _pulse.value) * .09,
                            child: Container(
                              width: 50, height: 50,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  center: const Alignment(-.24, 0),
                                  colors: [
                                    GoColors.coral.withOpacity(.5),
                                    GoColors.coral.withOpacity(.1),
                                  ],
                                ),
                                border: Border.all(
                                    color: GoColors.coralDark, width: 2),
                              ),
                            ),
                          ),
                        ),
                      ]),
                    );
                  },
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
