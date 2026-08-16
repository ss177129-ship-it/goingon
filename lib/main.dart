import 'dart:async';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/login_screen.dart';
import 'screens/nickname_screen.dart';
import 'screens/root_screen.dart';
import 'screens/update_required_screen.dart';
import 'services/app_version_gate.dart';
import 'services/auth_service.dart';
import 'theme.dart';
import 'widgets/brand_mark.dart';

import 'firebase_options.dart';

const _kHasLaunchedBeforeKey = 'has_launched_before';

/// Crashlytics로 크래시/미처리 에러를 전부 보냄 — Flutter 프레임워크 에러는
/// FlutterError.onError, 그 밖의 비동기 에러는 PlatformDispatcher.onError로
/// 잡고, 혹시 둘 다 빠져나가는 게 있으면 runZonedGuarded가 마지막으로 잡음
void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };

    await GoogleSignIn.instance.initialize();
    runApp(const GoingOnApp());
  }, (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  });
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
  bool _connectionError = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);
    _resolve();
  }

  Future<void> _resolve() async {
    if (_connectionError && mounted) setState(() => _connectionError = false);
    final prefs = await SharedPreferences.getInstance();
    final isFirstLaunch = !(prefs.getBool(_kHasLaunchedBeforeKey) ?? false);
    final minShow =
        Duration(milliseconds: isFirstLaunch ? 2000 : 300);

    // 낡은 빌드는 여기서 멈춘다. 확인에 실패하면 통과시키므로
    // (AppVersionGate 주석 참조) 오프라인에서 앱이 갇히지 않는다
    if (await AppVersionGate.shouldBlock()) {
      if (!mounted) return;
      setState(() => _destination = UpdateRequiredScreen(onPassed: _resolve));
      return;
    }

    User? user;
    var hasProfile = false;
    String? existingName;
    try {
      final authFuture = FirebaseAuth.instance
          .authStateChanges()
          .first
          .timeout(const Duration(seconds: 10));
      final gated = Future.wait([authFuture, Future.delayed(minShow)])
          .then((results) => results[0] as User?);
      final skipped = _skip.future.then((_) => authFuture);

      user = await Future.any([gated, skipped]);

      // 로그인은 됐지만 프로필이 아직 **완성되지 않은** 경우가 있다:
      // 닉네임 입력 전에 앱이 죽었거나, 아이디 항목이 생기기 전에 만들어진
      // 계정이거나. 문서 존재만 보면 아이디 없는 계정이 그대로 홈에 들어가고,
      // 그 사람은 검색으로 영영 안 찾아진다 — 완성 여부로 판정한다
      if (user != null) {
        final profile = await AuthService()
            .myProfile()
            .timeout(const Duration(seconds: 10));
        hasProfile = AuthService.isProfileComplete(profile);
        existingName = (profile?['name'] as String?)?.trim();
      }
    } catch (e, stack) {
      // 콜드스타트 중 네트워크/Firestore 문제 — 무한 대기 대신 재시도 화면으로
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (!mounted) return;
      setState(() => _connectionError = true);
      return;
    }

    if (isFirstLaunch) {
      await prefs.setBool(_kHasLaunchedBeforeKey, true);
    }
    if (!mounted) return;
    setState(() {
      if (user == null) {
        _destination = const LoginScreen();
      } else if (!hasProfile) {
        // 이름이 이미 있으면 다시 묻지 않게 채워서 보낸다
        _destination = NicknameScreen(prefill: existingName);
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
    if (_connectionError) return _connectionErrorScreen();
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

  Widget _connectionErrorScreen() {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('연결이 원활하지 않아요', style: GoTheme.serif(24)),
              const SizedBox(height: 10),
              const Text('네트워크 상태를 확인하고 다시 시도해 주세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: GoColors.mid)),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: GoColors.ink,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _resolve,
                  child: Text('다시 시도',
                      style: GoTheme.serif(18, color: GoColors.paper)),
                ),
              ),
            ]),
          ),
        ),
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
