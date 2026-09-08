import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';

import '../services/active_run_guard.dart';
import '../services/auth_service.dart';
import '../services/friend_service.dart';
import '../services/run_service.dart';
import '../theme.dart';
import '../widgets/go_group.dart';
import '../widgets/go_icon_button.dart';
import '../widgets/pressable.dart';
import '../widgets/go_button.dart';
import '../widgets/friend_search_sheet.dart';
import '../widgets/go_dialog.dart';
import '../widgets/go_toast.dart';
import '../widgets/go_value_switch.dart';
import '../widgets/goingon_wordmark.dart';
import '../widgets/initial_avatar.dart';
import 'lobby_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _auth = AuthService();
  final _friends = FriendService();
  final _runs = RunService();
  StreamSubscription? _incomingSub;
  final Set<String> _handledSessions = {};
  int _openSheets = 0;
  bool get _sheetShowing => _openSheets > 0;
  Map<String, dynamic>? _me;
  int _incomingRetries = 0;
  bool _incomingBroken = false;

  // 친구 목록은 StreamBuilder 대신 직접 구독함 — 일시적인 오류로 목록이
  // 빈 상태로 깜빡이거나, 스트림이 끊긴 걸 사용자가 모른 채 "친구 없음"
  // 화면에 갇히는 일을 막기 위해 마지막 성공 목록을 들고 있어야 해서
  StreamSubscription? _friendsSub;
  List<Map<String, dynamic>> _friendList = const [];
  bool _friendsError = false;
  int _friendsRetries = 0;

  /// 첫 응답이 오기 전과 "친구가 없다"는 구분되어야 한다. 둘을 같은 빈
  /// 목록으로 두면, 앱을 켤 때마다 페이스메이트가 있는 사람에게도 "아직
  /// 페이스메이트가 없어요"가 한 프레임 스쳐 지나간다
  bool _friendsLoaded = false;

  // 나에게 온 친구 요청. 푸시가 없어서 앱을 열어야 보이므로, 홈 최상단에
  // 눈에 띄게 둠 — 놓치면 상대는 무한정 기다리게 됨
  StreamSubscription? _requestsSub;
  List<FriendRequest> _requests = const [];

  /// GO? 요청 감지가 몇 번까지 자동 재시도할지. 인덱스 누락처럼 시간이
  /// 지나도 낫지 않는 문제일 때 조용히 무한 재구독하는 대신 사용자에게 알림
  static const _kMaxIncomingRetries = 5;

  @override
  void initState() {
    super.initState();
    _load();
    _listenIncoming();
    _listenFriends();
    _listenRequests();
  }

  void _listenRequests() {
    _requestsSub?.cancel();
    _requestsSub = _friends.incomingRequestsStream(_auth.uid).listen((list) {
      if (mounted) setState(() => _requests = list);
    }, onError: (e, stack) {
      // 요청 목록이 없어도 앱의 나머지는 동작하므로 배너까지 띄우지는 않음
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
    });
  }

  void _listenFriends() {
    _friendsSub?.cancel();
    _friendsSub = _friends.friendsStream(_auth.uid).listen((list) {
      if (!mounted) return;
      setState(() {
        _friendList = list;
        _friendsLoaded = true;
        _friendsError = false;
        _friendsRetries = 0;
      });
    }, onError: (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (!mounted) return;
      setState(() => _friendsError = true);
      if (_friendsRetries >= _kMaxIncomingRetries) return;
      _friendsRetries++;
      Future.delayed(Duration(seconds: 3 * _friendsRetries), () {
        if (mounted) _listenFriends();
      });
    });
  }

  Future<void> _load() async {
    try {
      final p = await _auth.myProfile();
      if (mounted) setState(() => _me = p);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (mounted) {
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) _load();
        });
      }
    }
  }

  /// 친구가 GO?를 보내면 여기서 감지 → 수락 시트
  void _listenIncoming() {
    _incomingSub?.cancel();
    _incomingSub = _runs.incomingSessions(_auth.uid).listen((snap) async {
      // 한 번이라도 정상 수신되면 재시도 카운터를 되돌림
      if (_incomingRetries != 0 || _incomingBroken) {
        _incomingRetries = 0;
        if (mounted && _incomingBroken) setState(() => _incomingBroken = false);
      }
      for (final doc in snap.docs) {
        if (_handledSessions.contains(doc.id)) continue;
        // 오래 응답 없는 요청은 뒤늦게 수락 시트로 띄우는 대신 정리함
        // (createdAt이 아직 null이면 serverTimestamp 반영 전이므로 무시하지 않음)
        final createdAt = doc.data()['createdAt'] as Timestamp?;
        if (createdAt != null &&
            DateTime.now().difference(createdAt.toDate()) > kRequestTtl) {
          _runs.cancelSession(doc.id);
          continue;
        }
        // 이미 다른 요청 시트가 떠 있거나 로비/러닝이 진행 중이면 겹쳐
        // 띄우지 않고 넘어감 — handledSessions에 넣지 않으므로 나중에
        // 자유로워지면 다음 스냅샷에서 다시 시도됨
        if (_sheetShowing || ActiveRunGuard.active) continue;
        _handledSessions.add(doc.id);
        final hostId = doc.data()['hostId'] as String;
        final host = await FirebaseFirestore.instance
            .collection('users').doc(hostId).get();
        final hostName = _displayName(host.data()?['name']);
        if (!mounted) return;
        _showGoRequest(doc.id, hostName, host.data()?['photoUrl'] as String?);
      }
    }, onError: (e, stack) {
      // 권한/네트워크 문제로 감지가 끊기면 잠시 뒤 재구독하되, 인덱스 누락처럼
      // 기다린다고 낫지 않는 문제일 때 무한 루프에 빠지지 않도록 횟수를 제한하고
      // 사용자에게 알림 — 예전에는 조용히 재시도만 반복해서 GO? 요청을 영영
      // 못 받으면서도 화면에는 아무 표시가 없었음
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (_incomingRetries >= _kMaxIncomingRetries) {
        if (mounted) setState(() => _incomingBroken = true);
        return;
      }
      _incomingRetries++;
      Future.delayed(Duration(seconds: 3 * _incomingRetries), () {
        if (mounted) _listenIncoming();
      });
    });
  }

  /// 이름이 비어 있거나 없는 계정 때문에 첫 글자 접근이 터지지 않도록
  static String _displayName(Object? name) {
    final s = name is String ? name.trim() : '';
    return s.isEmpty ? '페이스메이트' : s;
  }

  void _showGoRequest(String sessionId, String hostName, String? hostPhotoUrl) {
    _openSheets++;
    final roles = GoRoles.of(context);
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      backgroundColor: roles.surfaceHigh,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // 상태 태그(statusRunning): 코랄 면 + 잉크 글자, 테두리 없음
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: roles.statusRunning.bg,
              borderRadius: BorderRadius.circular(GoRadius.sm),
            ),
            child: Text('함께 달리기 요청',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                    color: roles.statusRunning.fg, letterSpacing: 1.2)),
          ),
          const SizedBox(height: 18),
          InitialAvatar(
            letter: hostName[0],
            size: 88,
            fontSize: 36,
            borderColor: roles.partner,
            photoUrl: hostPhotoUrl,
          ),
          const SizedBox(height: 16),
          Text('$hostName님이\n같이 달리자고 해요',
              textAlign: TextAlign.center, style: GoText.title),
          const SizedBox(height: GoSpace.section),
          GoButton('수락하고 함께 달리기', onTap: () {
            Navigator.pop(ctx);
            Navigator.push(context, MaterialPageRoute(
              builder: (_) => LobbyScreen(
                  sessionId: sessionId, partnerName: hostName),
            ));
          }),
          const SizedBox(height: GoSpace.s),
          GoButton('나중에',
              kind: GoButtonKind.text,
              size: GoButtonSize.md,
              onTap: () {
                Navigator.pop(ctx);
                _showDeclineOptions(sessionId);
              }),
        ]),
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _openSheets--);
    });
  }

  /// "나중에" 선택 시 침묵 대신 한 줄 답장을 고르게 함
  void _showDeclineOptions(String sessionId) {
    _openSheets++;
    const options = ['지금은 어려워요', '30분 뒤 어때요?', '오늘은 쉬고 싶어요'];
    showModalBottomSheet(
      context: context,
      backgroundColor: GoRoles.of(context).surfaceHigh,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(GoSpace.sheet, GoSpace.xl, GoSpace.sheet, GoSpace.sheetBottom),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('어떻게 전할까요?', style: GoText.heading),
              const SizedBox(height: 16),
              ...options.map((o) => Padding(
                    padding: const EdgeInsets.only(bottom: GoSpace.s),
                    child: GoButton(o,
                        kind: GoButtonKind.secondary,
                        onTap: () {
                          _runs.declineSession(sessionId, o);
                          Navigator.pop(ctx);
                        }),
                  )),
            ]),
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _openSheets--);
    });
  }

  /// GO?를 보내는 중인 상대의 uid. 세션 생성은 왕복이 있어서 그 사이
  /// 버튼이 그대로면 사람들은 반응이 없다고 생각해 한 번 더 누르고,
  /// 그러면 같은 상대에게 세션이 두 개 만들어진다 — 상대 화면에는 수락
  /// 시트가 두 번 뜨고, 하나는 영영 주인 없이 남는다
  String? _sendingTo;

  Future<void> _sendGo(String friendUid, String friendName) async {
    if (_sendingTo != null) return; // 연타·다른 행 동시 탭 모두 여기서 막힌다
    setState(() => _sendingTo = friendUid);
    try {
      final sessionId = await _runs.createSession(_auth.uid, friendUid);
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(
        builder: (_) =>
            LobbyScreen(sessionId: sessionId, partnerName: friendName),
      ));
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (!mounted) return;
      GoToast.error(context, '요청을 보내지 못했어요. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _sendingTo = null);
    }
  }

  @override
  void dispose() {
    _incomingSub?.cancel();
    _friendsSub?.cancel();
    _requestsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final friends = _friendList;
    final roles = GoRoles.of(context);
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // ── 상단 워드마크 + 친구 찾기 ──
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 10, 12, 6),
          child: Row(children: [
            const GoingOnWordmark(height: 18),
            const Spacer(),
            GoIconButton(
              icon: Icons.search,
              color: roles.textSecondary,
              onTap: () => showFriendSearchSheet(context),
              tooltip: '페이스메이트 찾기',
            ),
          ]),
        ),
        // ── 연결 문제 안내 ──
        if (_incomingBroken || _friendsError) _connectionNotice(),
        // ── 나에게 온 친구 요청 ──
        if (_requests.isNotEmpty) ..._requestSection(),
        // ── 내 프로필 카드 ──
        _profileCard(friends.length),
        // ── 같이 뛰는 사람들 ──
        const Padding(
          padding: EdgeInsets.fromLTRB(22, 18, 22, 8),
          child: Text('페이스메이트', style: GoText.label),
        ),
        // 아직 첫 응답 전 → 목록 자리를 뼈대로 잡아둔다. "없다"고 말하지
        // 않는 이유는, 잠시 뒤 나타날 것을 없다고 했다가 뒤집으면 화면이
        // 튀고 사용자는 방금 본 것을 의심하게 되기 때문
        // 뼈대 → 목록은 교차로 넘어간다. 뚝 바뀌면 "방금 그건 뭐였지"가 남는다
        GoValueSwitch(
          value: !_friendsLoaded
              ? 'skeleton'
              : friends.isEmpty
                  ? 'empty'
                  : 'list',
          alignment: Alignment.topCenter,
          child: !_friendsLoaded
              ? _friendListSkeleton()
              : friends.isEmpty
                  ? _noFriendsYet()
                  : GoGroup(
                      margin: const EdgeInsets.symmetric(horizontal: 22),
                      dividerInset: GoSpace.card + 44 + GoSpace.m,
                      rows: friends.map(_friendRow).toList(),
                    ),
        ),
        // 친구가 없어도 전체 흐름을 체험할 수 있는 통로. 심사관이 로비·러닝·
        // 완료 화면을 볼 유일한 방법이라 반드시 눈에 띄는 곳에 있어야 함
        if (_friendsLoaded && friends.isEmpty) _demoLink(),
        const SizedBox(height: GoSpace.m),
      ],
    );
  }

  /// 목록이 들어올 자리. 값 대신 회색 면만 두어 높이를 미리 차지한다
  Widget _friendListSkeleton() {
    final roles = GoRoles.of(context);
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: roles.line,
            borderRadius: BorderRadius.circular(h / 2),
          ),
        );
    return GoGroup(
      margin: const EdgeInsets.symmetric(horizontal: 22),
      dividerInset: GoSpace.card + 44 + GoSpace.m,
      rows: List.generate(
        2,
        (_) => GoGroupRow(
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: roles.line, shape: BoxShape.circle),
            ),
            const SizedBox(width: GoSpace.m),
            Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [bar(96, 12), const SizedBox(height: 6), bar(64, 10)]),
          ]),
        ),
      ),
    );
  }

  Widget _demoLink() {
    return Center(
      child: GoButton('혼자서 먼저 체험해보기',
          kind: GoButtonKind.text,
          size: GoButtonSize.md,
          icon: Icons.arrow_forward,
          iconTrailing: true,
          onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const LobbyScreen(
                      sessionId: 'demo', partnerName: '지수', demo: true),
                ),
              )),
    );
  }

  /// 나에게 온 친구 요청 — 프로필 카드보다 위에 둠. 푸시가 없어서 앱을
  /// 열었을 때 보이는 게 전부이고, 놓치면 상대는 무한정 기다리게 됨
  List<Widget> _requestSection() {
    return [
      const Padding(
        padding: EdgeInsets.fromLTRB(22, 14, 22, 8),
        child: Text('나에게 온 요청', style: GoText.label),
      ),
      ..._requests.map(_requestRow),
    ];
  }

  Widget _requestRow(FriendRequest r) {
    final name = _displayName(r.name);
    final roles = GoRoles.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(22, 0, 22, 8),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: roles.surface,
        borderRadius: BorderRadius.circular(GoRadius.md),
        boxShadow: GoShadow.card,
      ),
      child: Column(children: [
        Row(children: [
          InitialAvatar(
            letter: name[0],
            size: 40,
            fontSize: 17,
            borderColor: roles.partner,
            photoUrl: r.photoUrl,
          ),
          const SizedBox(width: GoSpace.m),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$name님이 함께 달리고 싶어해요',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: roles.textPrimary)),
                  if (r.username.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text('@${r.username}',
                        style: TextStyle(
                            fontSize: 12, color: roles.textSecondary)),
                  ],
                ]),
          ),
        ]),
        const SizedBox(height: GoSpace.m),
        Row(children: [
          Expanded(
            child: GoButton('거절',
                kind: GoButtonKind.secondary,
                size: GoButtonSize.md,
                onTap: () => _respondToRequest(r, accept: false)),
          ),
          const SizedBox(width: GoSpace.s),
          Expanded(
            flex: 2,
            // 홈의 주 색은 GO? 하나. 수락은 "연결을 완성한다"이므로 complete
            child: GoButton('수락하고 연결',
                kind: GoButtonKind.complete,
                size: GoButtonSize.md,
                onTap: () => _respondToRequest(r, accept: true)),
          ),
        ]),
      ]),
    );
  }

  Future<void> _respondToRequest(FriendRequest r, {required bool accept}) async {
    try {
      if (accept) {
        await _friends.acceptRequest(_auth.uid, r.fromUid);
      } else {
        // 거절은 조용히 — 상대에게 알리지 않음
        await _friends.declineRequest(_auth.uid, r.fromUid);
      }
      if (!mounted || !accept) return;
      GoToast.show(context, '${_displayName(r.name)}님과 연결됐어요!');
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (!mounted) return;
      GoToast.error(context, '처리하지 못했어요. 다시 시도해 주세요.');
    }
  }

  /// 요청 감지나 친구 목록 구독이 끊겼을 때 — 조용히 실패하지 않고 알림.
  /// 여기 걸리면 대개 Firestore 인덱스 미배포나 보안 규칙 문제임
  Widget _connectionNotice() {
    final roles = GoRoles.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(22, 6, 22, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: roles.surface,
        borderRadius: BorderRadius.circular(GoRadius.md),
        boxShadow: GoShadow.card,
      ),
      child: Row(children: [
        Icon(Icons.wifi_off, size: 18, color: roles.attention),
        const SizedBox(width: GoSpace.m),
        Expanded(
          child: Text(
            _incomingBroken
                ? '지금은 함께 달리기 요청을 받지 못하고 있어요.'
                : '페이스메이트 목록을 불러오지 못했어요.',
            style: TextStyle(
                fontSize: 12, height: 1.4, color: roles.textPrimary.withValues(alpha: .7)),
          ),
        ),
        GoButton('다시 시도',
            kind: GoButtonKind.text,
            size: GoButtonSize.md,
            onTap: () {
              setState(() {
                _incomingRetries = 0;
                _friendsRetries = 0;
                _incomingBroken = false;
                _friendsError = false;
              });
              _listenIncoming();
              _listenFriends();
              _load();
            }),
      ]),
    );
  }

  /// 내 프로필 카드 — 프로토타입의 흰 카드 + 3분할 스탯
  Widget _profileCard(int friendCount) {
    // 프로필이 아직 안 왔을 때 0.0km·0회를 보여주면, 실제로 기록이 있는
    // 사람에게 잠깐 "아무것도 안 했다"고 말하는 셈이 된다. 값 대신 —
    final loaded = _me != null;
    final myName = _me?['name'] ?? '';
    final now = DateTime.now();
    final monthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final monthKm = (_me?['monthKey'] == monthKey)
        ? ((_me?['monthKm'] ?? 0) as num).toDouble()
        : 0.0;
    final totalRuns = (_me?['totalRuns'] ?? 0) as num;
    final roles = GoRoles.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(22, 6, 22, 0),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
        color: roles.surface,
        borderRadius: BorderRadius.circular(GoRadius.md),
        boxShadow: GoShadow.card,
      ),
      child: Column(children: [
        InitialAvatar(
          letter: myName.isEmpty ? '' : myName[0],
          size: 60,
          fontSize: 26,
          borderColor: roles.self,
          emptyIcon: Icons.person_outline,
          photoUrl: _me?['photoUrl'] as String?,
        ),
        const SizedBox(height: 8),
        Text(myName, style: GoText.heading),
        const SizedBox(height: 3),
        GoValueSwitch(
          value: loaded,
          child: Text(loaded ? '함께 달릴 준비 완료' : '불러오는 중',
              style: TextStyle(
                  fontSize: 12,
                  color: loaded ? roles.positive : roles.textSecondary)),
        ),
        const SizedBox(height: 14),
        Container(height: 1, color: roles.lineStrong),
        const SizedBox(height: GoSpace.m),
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _stat(loaded ? monthKm.toStringAsFixed(1) : '—',
                loaded ? 'km' : '', '이번 달'),
            _statDivider(),
            _stat(loaded ? '$totalRuns' : '—', '', '함께 달림'),
            _statDivider(),
            _stat(_friendsLoaded ? '$friendCount' : '—',
                _friendsLoaded ? '명' : '', '함께하는 사람'),
          ]),
        ),
      ]),
    );
  }

  Widget _stat(String v, String unit, String label) {
    final roles = GoRoles.of(context);
    return Expanded(
      child: Column(children: [
        // 값이 오면(— → 3.2) 그리고 러닝 뒤 늘어나면 살짝 떠오르며 바뀐다
        GoValueSwitch(
          value: '$v$unit',
          child: Text.rich(TextSpan(children: [
            TextSpan(text: v, style: GoTheme.serif(19)),
            TextSpan(
                text: unit,
                style: TextStyle(fontSize: 12, color: roles.textSecondary)),
          ])),
        ),
        const SizedBox(height: 2),
        Text(label, style: GoText.label),
      ]),
    );
  }

  Widget _statDivider() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Container(width: 1, color: GoRoles.of(context).lineStrong),
      );

  /// 친구 행 — 프로토타입의 friend-row (아바타 + 이름 + GO?)
  /// 길게 누르면 연결 끊기 / 차단 메뉴
  GoGroupRow _friendRow(Map<String, dynamic> f) {
    final name = _displayName(f['name']);
    final uid = f['uid'] as String;
    final roles = GoRoles.of(context);
    // 그룹 안의 행 하나. 상대 역할색(partner)은 아바타 링에만
    return GoGroupRow(
      // 길게 누르기는 지름길로 남기되, 그것'만'으로는 아무도 못 찾는다.
      // 차단·신고는 App Store 가이드라인 1.2가 요구하는 수단이라 화면에
      // 보이는 입구가 반드시 있어야 한다
      onLongPress: () => _showFriendActions(uid, name),
      child: Row(children: [
          InitialAvatar(
            letter: name[0],
            size: 44,
            fontSize: 18,
            borderColor: roles.partner,
            borderWidth: 1.5,
            photoUrl: f['photoUrl'] as String?,
          ),
          const SizedBox(width: GoSpace.m),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: roles.textPrimary)),
                  const SizedBox(height: 1),
                  Text('멀리 있어도, 함께',
                      style: TextStyle(fontSize: 12, color: roles.textSecondary)),
                ]),
          ),
          Pressable(
            onTap: () => _showFriendActions(uid, name),
            child: Padding(
              // 아이콘 18 + 상하좌우 13 = 44pt 터치 표적
              padding: const EdgeInsets.all(13),
              child: Icon(Icons.more_horiz, size: 18, color: roles.textSecondary),
            ),
          ),
          const SizedBox(width: 2),
          GoButton('GO?',
              kind: GoButtonKind.primary,
              size: GoButtonSize.md,
              serifLabel: true,
              loading: _sendingTo == uid,
              // 다른 행을 보내는 중이면 이 행도 눌리지 않는다 — 두 사람에게
              // 동시에 GO?를 보내면 어느 로비로 들어갈지가 경합이 된다
              enabled: _sendingTo == null || _sendingTo == uid,
              onTap: () => _sendGo(uid, name)),
        ]),
    );
  }

  /// 연결 끊기 / 차단 선택. 둘의 차이가 분명해야 해서 설명을 함께 보여줌 —
  /// 끊기는 상대가 다시 요청을 보낼 수 있고, 차단은 그것까지 막음
  void _showFriendActions(String uid, String name) {
    showModalBottomSheet(
      context: context,
      backgroundColor: GoRoles.of(context).surfaceHigh,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(GoSpace.sheet, GoSpace.xl, GoSpace.sheet, GoSpace.sheetBottom),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(name, style: GoText.heading),
              const SizedBox(height: 16),
              _actionTile(
                label: '연결 끊기',
                note: '서로의 목록에서 사라져요. 상대가 다시 요청을 보낼 수는 있어요.',
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmRemoveFriend(uid, name);
                },
              ),
              const SizedBox(height: 8),
              _actionTile(
                label: '차단하기',
                note: '연결이 끊기고, 상대는 나를 검색하거나 요청을 보낼 수 없게 돼요.',
                destructive: true,
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmBlock(uid, name);
                },
              ),
            ]),
      ),
    );
  }

  Widget _actionTile({
    required String label,
    required String note,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    // 두 줄(라벨+설명) 타일이라 GoButton(한 줄 라벨)이 아니라 Pressable
    final roles = GoRoles.of(context);
    return Pressable(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: GoSpace.l),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(GoRadius.sm),
        ),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: destructive ? roles.attention : roles.textPrimary)),
        const SizedBox(height: 2),
        Text(note,
            style: TextStyle(
                fontSize: 12, height: 1.4, color: roles.textSecondary)),
      ]),
      ),
    );
  }

  Future<void> _confirmRemoveFriend(String uid, String name) async {
    final confirmed = await GoDialog.confirm(
      context,
      title: '$name님과의 연결을 끊을까요?',
      body: '서로의 목록에서 사라지고, 더 이상 함께 달리기 요청을 주고받을 수 없어요.\n'
          '지금까지 함께 달린 기록은 그대로 남아요.',
      confirmLabel: '연결 끊기',
      destructive: true,
    );
    if (confirmed != true) return;
    await _runFriendAction(
      () => _friends.removeFriend(_auth.uid, uid),
      failMessage: '연결을 끊지 못했어요. 다시 시도해 주세요.',
    );
  }

  Future<void> _confirmBlock(String uid, String name) async {
    final confirmed = await GoDialog.confirm(
      context,
      title: '$name님을 차단할까요?',
      body: '연결이 끊기고, 오가던 요청도 사라져요.\n'
          '상대는 나를 검색하거나 요청을 보낼 수 없게 돼요.\n'
          '설정에서 언제든 해제할 수 있어요.',
      confirmLabel: '차단하기',
      destructive: true,
    );
    if (confirmed != true) return;
    await _runFriendAction(
      () => _friends.blockUser(_auth.uid, uid),
      failMessage: '차단하지 못했어요. 다시 시도해 주세요.',
      successMessage: '$name님을 차단했어요.',
    );
  }

  Future<void> _runFriendAction(Future<void> Function() action,
      {required String failMessage, String? successMessage}) async {
    try {
      await action();
      if (!mounted || successMessage == null) return;
      GoToast.show(context, successMessage);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (!mounted) return;
      GoToast.error(context, failMessage);
    }
  }

  /// 친구가 아직 없을 때
  Widget _noFriendsYet() {
    final roles = GoRoles.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 22),
      padding: const EdgeInsets.symmetric(vertical: GoSpace.xl, horizontal: GoSpace.hero),
      decoration: BoxDecoration(
        color: roles.surface,
        borderRadius: BorderRadius.circular(GoRadius.md),
        boxShadow: GoShadow.card,
      ),
      child: Column(children: [
        Text('아직 페이스메이트가 없어요',
            style: GoText.heading.copyWith(color: roles.textSecondary)),
        const SizedBox(height: 6),
        Text('한 명만 있으면 고잉온이 시작돼요.',
            style: TextStyle(fontSize: 12, color: roles.textSecondary)),
      ]),
    );
  }
}
