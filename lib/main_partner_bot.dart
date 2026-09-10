// 파트너 봇 — 2인 흐름을 혼자 끝까지 밟기 위한 상대역.
//
// 실행:
//   ./tools/env.sh staging
//   flutter run -t lib/main_partner_bot.dart --dart-define=GO_ENV=staging \
//     -d <두 번째 시뮬레이터>
//
// ## 왜 필요한가
//
// GoingOn의 핵심은 두 사람이 동시에 달리는 것이라, 초대·수락·준비·러닝·결과
// 제출이 **상대가 실재해야만** 밟힌다. 사람 둘과 기기 둘을 매번 모으는 건
// 현실적이지 않고, 그래서 이 경로들은 지금까지 "한 번 손으로 확인하고 끝"
// 이었다. 봇이 있으면 같은 흐름을 명령 한 줄로 몇 번이든 돌릴 수 있다.
//
// ## 규칙을 우회하지 않는다
//
// 봇은 Admin SDK가 아니라 **평범한 로그인 사용자**다. 그래서 firestore.rules를
// 실제로 밟고, 규칙이 틀리면 봇이 깨진다 — 깨지는 것이 목적이다. 관리자
// 권한으로 돌렸다면 "내 폰에선 됐는데 사용자 폰에선 권한 거부"가 그대로
// 재현되고, 그건 검증이 아니라 검증했다는 착각이다.
//
// 그리고 앱과 **같은 서비스 계층**(RunService·FriendService·AuthService)을
// 호출한다. 서버 API를 직접 때리는 봇은 앱이 실제로 하는 일을 검증하지 못한다.
//
// ## 연습실에서만 돈다
//
// 봇이 운영에 계정과 세션·러닝 기록을 만들면, 그걸 치우는 삭제 스크립트를
// 운영에 겨눈 채로 유지해야 한다. 조건 하나 틀리면 실사용자 기록이 날아가고
// 되돌릴 수 없다. 그래서 연습실이 아니면 **아무것도 하지 않고 멈춘다.**
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_env.dart';
import 'services/auth_service.dart';
import 'services/friend_service.dart';
import 'services/live_share.dart';
import 'services/run_service.dart';
import 'services/session_rules.dart';
import 'theme.dart';

/// 봇이 언제 무엇을 하는지. **난수를 쓰지 않는다** —
/// `demo_resonance.dart`와 같은 이유다. 흔들리면 어떤 실행에서는 보고 싶은
/// 갈래가 안 나오고, 그러면 "됐다/안 됐다"를 말할 수 없다.
class BotScenario {
  const BotScenario._();

  /// 로그인에 쓰는 고정 계정. 연습실에만 존재한다.
  static const email = 'partner-bot@goingon.test';
  static const password = 'goingon-staging-bot';

  /// 봇의 프로필. 사람이 목록에서 알아볼 수 있어야 한다.
  static const nickname = '지수(봇)';
  static const username = 'bot_jisoo';

  /// 페이스메이트 요청이 오면 이만큼 뒤에 수락한다. 0이 아닌 이유는
  /// "요청 중" 상태가 화면에 실제로 그려지는 걸 볼 수 있어야 하기 때문이다.
  static const acceptFriendAfter = Duration(seconds: 3);

  /// 초대(GO?)가 오면 이만큼 뒤에 수락한다.
  static const acceptSessionAfter = Duration(seconds: 4);

  /// 로비에 들어가고 이만큼 뒤에 준비완료를 누른다.
  static const readyAfter = Duration(seconds: 3);

  /// 둘 다 준비된 뒤 러닝 시작까지. 앱의 카운트다운(3초)과 맞춘다 —
  /// 봇만 먼저 출발하면 `startedAt`이 어느 쪽으로 찍히는지 볼 수 없다.
  static const countdown = Duration(seconds: 3);

  /// 러닝 길이. 짧게 두는 것이 이 도구의 핵심이다 — 30분을 기다리면
  /// 하루에 몇 번 못 돌린다.
  static const runFor = Duration(seconds: 90);

  /// live 갱신 간격.
  static const liveEvery = Duration(seconds: 3);

  /// 봇이 달리는 페이스(km당 초)와 케이던스 기준값.
  static const paceSecPerKm = 330;
  static const baseCadence = 170.0;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 설정은 GoogleService-Info.plist에서 온다 — 네이티브가 먼저 [DEFAULT]를
  // 만들어 두기 때문에 options를 넘기면 duplicate-app이 난다
  // (FirebaseEnv 주석 참조). 어디를 가리키는지는 _BotApp이 확인한다
  await Firebase.initializeApp();
  runApp(const _BotApp());
}

class _BotApp extends StatelessWidget {
  const _BotApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'GoingOn 파트너 봇',
        debugShowCheckedModeBanner: false,
        theme: GoTheme.light(),
        home: FirebaseEnv.isStaging &&
                Firebase.app().options.projectId == 'goingon-staging'
            ? const _BotScreen()
            : const _RefusedScreen(),
      );
}

/// 연습실이 아닐 때 뜨는 화면. 봇을 운영에서 돌리는 것은 사고이지
/// 선택지가 아니므로, 물어보지 않고 거부한다.
class _RefusedScreen extends StatelessWidget {
  const _RefusedScreen();

  @override
  Widget build(BuildContext context) {
    final actual = Firebase.app().options.projectId;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('봇은 연습실에서만 돕니다', style: GoTheme.serif(22)),
              const SizedBox(height: 14),
              Text(
                '지금 가리키는 곳: $actual\n'
                '봇이 만드는 계정과 기록이 운영에 남으면\n'
                '그걸 지우는 스크립트를 운영에 겨눠야 합니다.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, height: 1.6),
              ),
              const SizedBox(height: 20),
              const Text('./tools/env.sh staging',
                  style: TextStyle(fontSize: 13)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _BotScreen extends StatefulWidget {
  const _BotScreen();

  @override
  State<_BotScreen> createState() => _BotScreenState();
}

class _BotScreenState extends State<_BotScreen> {
  final _runs = RunService();
  final _friends = FriendService();
  final _log = <String>[];
  final _scroll = ScrollController();

  String _phase = '시작하는 중';
  String? _uid;

  /// 이미 손댄 것들. 스트림은 같은 문서를 여러 번 흘려보내므로,
  /// 이게 없으면 한 초대에 수락을 여러 번 던진다.
  final _handledSessions = <String>{};
  final _handledRequests = <String>{};

  StreamSubscription<dynamic>? _sessionsSub;
  StreamSubscription<dynamic>? _requestsSub;
  StreamSubscription<dynamic>? _currentSessionSub;
  Timer? _liveTimer;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _sessionsSub?.cancel();
    _requestsSub?.cancel();
    _currentSessionSub?.cancel();
    _liveTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  /// 시각은 직접 만든다. `TimeOfDay.format(context)`는 Localizations를 타는데,
  /// 첫 로그가 initState 중에 찍히므로 그때는 아직 준비되지 않았다
  /// (실제로 여기서 한 번 부팅이 통째로 실패했다).
  static String _stamp() {
    final n = DateTime.now();
    String p(int v) => v.toString().padLeft(2, '0');
    return '${p(n.hour)}:${p(n.minute)}:${p(n.second)}';
  }

  void _say(String line) {
    debugPrint('[bot] $line');
    if (!mounted) return;
    setState(() {
      _log.add('${_stamp()}  $line');
      if (_log.length > 200) _log.removeAt(0);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _setPhase(String p) {
    if (mounted) setState(() => _phase = p);
    _say('— $p');
  }

  Future<void> _boot() async {
    try {
      _setPhase('로그인하는 중');
      final uid = await _signIn();
      _uid = uid;
      _say('uid: $uid');

      _setPhase('프로필 확인 중');
      final ok = await AuthService()
          .ensureProfile(BotScenario.nickname, BotScenario.username);
      if (!ok) {
        _say('프로필을 만들지 못했습니다 (아이디 충돌?)');
        _setPhase('멈춤');
        return;
      }
      _say('${BotScenario.nickname} / @${BotScenario.username}');

      _watchFriendRequests(uid);
      _watchSessions(uid);
      _setPhase('기다리는 중');
    } catch (e, stack) {
      _say('부팅 실패: $e');
      debugPrintStack(stackTrace: stack);
      _setPhase('멈춤');
    }
  }

  /// 이메일/비밀번호로 들어간다. 계정이 없으면 만든다.
  ///
  /// Apple 로그인을 쓰지 않는 이유: 헤드리스로 띄울 수 없다. custom token도
  /// 되지만 연습실 서비스 계정 키를 하나 더 관리해야 하고, 규칙 입장에서는
  /// 어느 쪽이든 똑같은 `request.auth.uid`다 — 비밀 파일이 안 생기는 쪽을
  /// 골랐다. 이 제공자는 **연습실에만** 켜져 있다.
  Future<String> _signIn() async {
    final auth = FirebaseAuth.instance;
    try {
      final cred = await auth.signInWithEmailAndPassword(
          email: BotScenario.email, password: BotScenario.password);
      return cred.user!.uid;
    } on FirebaseAuthException catch (e) {
      if (e.code != 'user-not-found' && e.code != 'invalid-credential') rethrow;
      _say('계정이 없어 새로 만듭니다');
      final cred = await auth.createUserWithEmailAndPassword(
          email: BotScenario.email, password: BotScenario.password);
      return cred.user!.uid;
    }
  }

  // ── 페이스메이트 요청 ────────────────────────────────────────────────

  void _watchFriendRequests(String uid) {
    _requestsSub = _friends.incomingRequestsStream(uid).listen((requests) {
      for (final r in requests) {
        if (!_handledRequests.add(r.fromUid)) continue;
        _say('페이스메이트 요청: ${r.name} (@${r.username})');
        Future.delayed(BotScenario.acceptFriendAfter, () async {
          try {
            await _friends.acceptRequest(uid, r.fromUid);
            _say('요청 수락됨 → ${r.name}');
          } catch (e) {
            _say('요청 수락 실패: $e');
            _handledRequests.remove(r.fromUid);
          }
        });
      }
    }, onError: (e) => _say('요청 스트림 오류: $e'));
  }

  // ── 세션(GO?) ───────────────────────────────────────────────────────

  void _watchSessions(String uid) {
    _sessionsSub = _runs.incomingSessions(uid).listen((snap) {
      for (final doc in snap.docs) {
        final status = doc.data()['status'] as String?;
        if (status != SessionRules.invited) continue;
        if (!_handledSessions.add(doc.id)) continue;
        _say('초대 도착: ${doc.id}');
        _handleSession(doc.id, uid);
      }
    }, onError: (e) => _say('세션 스트림 오류: $e'));
  }

  Future<void> _handleSession(String sessionId, String uid) async {
    try {
      await Future<void>.delayed(BotScenario.acceptSessionAfter);
      _setPhase('초대 수락');
      await _runs.acceptSession(sessionId);

      await _runs.enterLobby(sessionId, uid);
      _say('로비 입장');

      await Future<void>.delayed(BotScenario.readyAfter);
      await _runs.setReady(sessionId, uid);
      _setPhase('준비 완료 — 상대를 기다림');

      _watchForStart(sessionId, uid);
    } catch (e) {
      _say('세션 처리 실패: $e');
      _handledSessions.remove(sessionId);
      _setPhase('기다리는 중');
    }
  }

  /// 둘 다 준비되면 앱과 같은 카운트다운 뒤에 `startRun`을 부른다.
  ///
  /// 앱도 양쪽이 각자 부르므로 **동시에 두 번 불리는 것이 정상**이다.
  /// `startedAt`은 먼저 찍힌 값을 유지해야 하는데, 그게 실제로 그런지는
  /// 이렇게 둘이 같이 부를 때만 확인된다.
  void _watchForStart(String sessionId, String uid) {
    var started = false;
    _currentSessionSub?.cancel();
    _currentSessionSub = _runs.sessionStream(sessionId).listen((doc) async {
      final data = doc.data();
      if (data == null) return;
      final status = data['status'] as String?;

      if (!started && SessionRules.bothReady(data)) {
        started = true;
        _setPhase('둘 다 준비 — 카운트다운');
        await Future<void>.delayed(BotScenario.countdown);
        try {
          await _runs.startRun(sessionId);
        } catch (e) {
          _say('startRun 실패: $e');
        }
      }

      if (status == SessionRules.running && _liveTimer == null) {
        _beginRun(sessionId, uid);
      }
    }, onError: (e) => _say('세션 구독 오류: $e'));
  }

  // ── 러닝 ────────────────────────────────────────────────────────────

  void _beginRun(String sessionId, String uid) {
    _setPhase('달리는 중 (${BotScenario.runFor.inSeconds}초)');
    final startedAt = DateTime.now();

    _liveTimer = Timer.periodic(BotScenario.liveEvery, (t) async {
      // 경과는 타이머 틱 누적이 아니라 타임스탬프 차이로 —
      // 앱과 같은 규칙이다 (iOS는 백그라운드에서 Timer를 멈춘다)
      final elapsed = DateTime.now().difference(startedAt);
      if (elapsed >= BotScenario.runFor) {
        t.cancel();
        _liveTimer = null;
        await _finish(sessionId, uid, elapsed);
        return;
      }

      final km = elapsed.inMilliseconds / 1000 / BotScenario.paceSecPerKm;
      try {
        await _runs.pushLive(
          sessionId,
          uid,
          LiveState(
            paceSecPerKm: BotScenario.paceSecPerKm,
            cadenceSpm: _cadenceAt(elapsed),
            km: km,
            at: DateTime.now(),
          ),
        );
      } catch (e) {
        _say('live 갱신 실패: $e');
      }
    });
  }

  /// 케이던스는 기준값 주위로 천천히 흔들린다. 공명 판정이 붙었다 떨어졌다
  /// 하는 걸 보려면 완전히 평평하면 안 된다 — 다만 난수가 아니라 시간의
  /// 함수라, 같은 초에는 언제나 같은 값이 나온다.
  double _cadenceAt(Duration elapsed) {
    final s = elapsed.inSeconds;
    final wave = (s % 40) / 40 * 2 - 1; // -1 → 1 톱니
    return BotScenario.baseCadence + wave * 6;
  }

  Future<void> _finish(String sessionId, String uid, Duration elapsed) async {
    _setPhase('결과 제출');
    final km = elapsed.inMilliseconds / 1000 / BotScenario.paceSecPerKm;
    try {
      await _runs.submitResult(
        sessionId,
        uid,
        seconds: elapsed.inSeconds,
        km: double.parse(km.toStringAsFixed(3)),
        kcal: (km * 62).round(),
      );
      _say('제출 완료: ${km.toStringAsFixed(2)}km / ${elapsed.inSeconds}초');
      _setPhase('기다리는 중');
    } catch (e) {
      _say('결과 제출 실패: $e');
      _setPhase('멈춤');
    }
    _currentSessionSub?.cancel();
    _currentSessionSub = null;
  }

  // ── 화면 ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final roles = GoRoles.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('파트너 봇', style: GoTheme.serif(24)),
              const SizedBox(height: 4),
              Text('연습실 · ${BotScenario.nickname}',
                  style: TextStyle(fontSize: 12, color: roles.textSecondary)),
              const SizedBox(height: 12),
              Text(_phase, style: GoTheme.serif(18)),
              if (_uid != null)
                Text(_uid!,
                    style: TextStyle(fontSize: 10, color: roles.textSecondary)),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(20),
              itemCount: _log.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(_log[i], style: const TextStyle(fontSize: 12)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
