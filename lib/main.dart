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
import 'widgets/splash_motion/goingon_brand_motion.dart';

import 'firebase_env.dart';
import 'services/hidden_invites.dart';

const _kHasLaunchedBeforeKey = 'has_launched_before';

/// Crashlytics로 크래시/미처리 에러를 전부 보냄 — Flutter 프레임워크 에러는
/// FlutterError.onError, 그 밖의 비동기 에러는 PlatformDispatcher.onError로
/// 잡고, 혹시 둘 다 빠져나가는 게 있으면 runZonedGuarded가 마지막으로 잡음
void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    // 설정은 GoogleService-Info.plist에서 온다. 네이티브가 main()보다 먼저
    // [DEFAULT] 앱을 만들어 두기 때문에, 여기서 다른 options를 넘기면
    // duplicate-app이 나고 그 예외가 runApp()을 막아 런치 스크린인 채로
    // 멈춘다 (FirebaseEnv 주석 참조). 그래서 options 없이 초기화하고,
    // 그게 의도한 프로젝트인지만 확인한다
    await Firebase.initializeApp();
    try {
      FirebaseEnv.verify();
    } on EnvMismatch catch (e) {
      // 어긋난 채로 계속 가면 개발 빌드나 봇이 운영 데이터를 건드리게 된다.
      // 화면만 봐서는 알 수 없는 종류라 여기서 멈추고 사람에게 말한다
      runApp(_EnvMismatchApp(e));
      return;
    }

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };

    await GoogleSignIn.instance.initialize();
    // 내가 치운 지난 제안 목록 — 화면이 그려지기 전에 읽어야 치운 것이
    // 한 프레임 스쳐 지나가지 않는다. 실패해도 앱은 돌아간다
    await HiddenInvites.instance.load();
    runApp(const GoingOnApp());
  }, (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  });
}

/// plist와 `GO_ENV`가 어긋났을 때 대신 뜨는 화면.
///
/// 앱을 그냥 죽이지 않는 이유: 예외가 runApp()을 막으면 런치 스크린인 채로
/// 멈춰서 "왜 안 뜨지"만 남는다. 실제로 그 상태를 한 번 진단하느라 시간을
/// 썼다. 필요한 것은 무엇이 어긋났고 무엇을 치면 되는지다.
class _EnvMismatchApp extends StatelessWidget {
  const _EnvMismatchApp(this.error);

  final EnvMismatch error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: GoTheme.light(),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('환경이 어긋났어요', style: GoTheme.serif(24)),
                const SizedBox(height: 14),
                Text(
                  'GO_ENV=${error.flag} 는 ${error.expected} 를 기대했는데\n'
                  'plist는 ${error.actual} 를 가리키고 있습니다.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 20),
                // 폰트는 지정하지 않는다 — 번들에 없는 패밀리(monospace 등)를
                // 부르면 이 환경에서는 폴백이 없어 두부가 된다
                Text(error.remedy, style: const TextStyle(fontSize: 13)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
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
/// 브랜드 모션(2.7s)이 **끝까지 재생된 뒤에** 넘어간다 — 도중에 끊기면 로고가
/// 반쯤 그려진 채 사라져 뭘 봤는지 모른다(2026-09-08 실기기 확인). 인증·프로필
/// 조회는 모션과 나란히 진행하고, 둘 다 끝나야 전환한다. 모션이 먼저 끝났는데
/// 아직 로딩 중이면 처음부터 다시 틀지 않고 두 링만 돌며 "기다리는 중"을 말한다.
/// 탭하면 이 대기를 건너뛰고 바로 전환된다 — 안내 문구는 화면에 두지 않는다
/// (2026-09-08). 브랜드 모션만 남기기로 했고, 탭은 아는 사람을 위한 지름길이다.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key});

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  final _skip = Completer<void>();

  /// 브랜드 모션이 끝난 시점. 동작 줄이기가 켜져 있으면 첫 프레임에 완료된다
  var _introDone = Completer<void>();
  Widget? _destination;
  bool _connectionError = false;

  void _onIntroComplete() {
    if (!_introDone.isCompleted) _introDone.complete();
  }

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    if (_connectionError && mounted) {
      // 재시도면 스플래시가 다시 마운트돼 모션도 처음부터 — 완료 시점도 새로
      _introDone = Completer<void>();
      setState(() => _connectionError = false);
    }
    final prefs = await SharedPreferences.getInstance();
    final isFirstLaunch = !(prefs.getBool(_kHasLaunchedBeforeKey) ?? false);

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
      // 인증 → 프로필 조회를 하나의 일로 묶어 모션과 **나란히** 돌린다.
      // 예전엔 인증만 기다린 뒤 프로필을 따로 읽어서, 모션이 끝나고도
      // 한 번 더 기다리는 구간이 생겼다
      final loaded = () async {
        final u = await FirebaseAuth.instance
            .authStateChanges()
            .first
            .timeout(const Duration(seconds: 10));
        // 로그인은 됐지만 프로필이 아직 **완성되지 않은** 경우가 있다:
        // 닉네임 입력 전에 앱이 죽었거나, 아이디 항목이 생기기 전에 만들어진
        // 계정이거나. 문서 존재만 보면 아이디 없는 계정이 그대로 홈에 들어가고,
        // 그 사람은 검색으로 영영 안 찾아진다 — 완성 여부로 판정한다
        if (u != null) {
          final profile = await AuthService()
              .myProfile()
              .timeout(const Duration(seconds: 10));
          hasProfile = AuthService.isProfileComplete(profile);
          existingName = (profile?['name'] as String?)?.trim();
        }
        return u;
      }();
      // 모션이 끝나야 넘어간다. 탭하면 모션은 기다리지 않는다
      final gated = Future.wait([loaded, _introDone.future])
          .then((results) => results[0] as User?);
      final skipped = _skip.future.then((_) => loaded);
      user = await Future.any([gated, skipped]);
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
    final roles = GoRoles.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('연결이 원활하지 않아요', style: GoTheme.serif(24)),
              const SizedBox(height: 10),
              Text('네트워크 상태를 확인하고 다시 시도해 주세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: roles.textSecondary)),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: roles.dark.bg,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _resolve,
                  child: Text('다시 시도',
                      style: GoTheme.serif(18, color: roles.dark.fg)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _splash() {
    // 브랜드 모션 하나만 둔다 — 심볼 드로잉 → 손글씨 워드마크 → o 점프(2.7s).
    // 인트로가 끝나고도 로딩 중이면 두 링만 돌며 "기다리는 중"을 알린다.
    // 타이밍은 SplashTimeline(goingon_brand_motion.dart)에서만 바꾼다.
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: GoingOnBrandMotion(onIntroComplete: _onIntroComplete),
        ),
      ),
    );
  }
}
