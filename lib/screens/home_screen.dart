import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';

import '../services/active_run_guard.dart';
import '../services/auth_service.dart';
import '../services/friend_service.dart';
import '../services/hidden_invites.dart';
import '../services/invite.dart';
import '../services/invite_service.dart';
import '../services/run_service.dart';
import '../services/session_rules.dart';
import '../theme.dart';
import '../widgets/go_icon_button.dart';
import '../widgets/go_button.dart';
import '../widgets/friend_search_sheet.dart';
import '../widgets/go_dialog.dart';
import '../widgets/go_toast.dart';
import '../widgets/go_value_switch.dart';
import '../widgets/wordmark_header.dart';
import '../widgets/go_avatar.dart';
import '../widgets/pacemate_card.dart';
import '../widgets/friend_profile_sheet.dart';
import 'lobby_screen.dart';
import 'thread_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _auth = AuthService();
  final _friends = FriendService();
  final _runs = RunService();
  final _invites = InviteService();
  final _hidden = HiddenInvites.instance;

  /// 지금 오가는 제안 전부 — 홈 카드가 사람마다 자기 것을 골라 쓴다
  StreamSubscription? _invitesSub;
  List<Invite> _inviteList = const [];

  /// 이미 접기를 시도한 세션 — 스트림이 다시 울릴 때마다 같은 쓰기를
  /// 되풀이하지 않는다
  final Set<String> _merging = {};
  StreamSubscription? _incomingSub;

  /// 이미 알린 요청 — 스냅샷이 다시 울릴 때마다 같은 토스트를 되풀이하지
  /// 않는다. 첫 스냅샷은 알리지 않고 채우기만 한다([_announcedPrimed])
  final Set<String> _announced = {};
  bool _announcedPrimed = false;
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

  /// GO? 요청 감지가 몇 번까지 자동 재시도할지. 인덱스 누락처럼 시간이
  /// 지나도 낫지 않는 문제일 때 조용히 무한 재구독하는 대신 사용자에게 알림
  static const _kMaxIncomingRetries = 5;

  @override
  void initState() {
    super.initState();
    _load();
    _listenIncoming();
    _listenFriends();
    _listenInvites();
    // '제안' 탭에서 치운 결과가 홈 카드에 남아 있으면 안 된다 — 같은 것을
    // 보는 두 화면이 다른 말을 하는 자리가 또 생긴다
    _hidden.addListener(_onHiddenChanged);
  }

  void _onHiddenChanged() {
    if (mounted) setState(() {});
  }

  void _listenInvites() {
    _invitesSub?.cancel();
    _invitesSub = _invites.stream(_auth.uid).listen((list) {
      if (mounted) setState(() => _inviteList = list);
      _resolveCollisions(list);
    }, onError: (e, stack) {
      // 제안이 안 보여도 앱의 나머지는 동작한다
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
  /// 나에게 온 요청 감시.
  ///
  /// **여기서 화면을 막지 않는다**(2026-09-09). 전에는 요청이 오는 즉시
  /// `isDismissible: false`인 시트를 띄웠다 — 답하기 전까지 앱의 무엇도
  /// 할 수 없었고, 답하려고 상대가 누구인지 확인하러 갈 수조차 없었다.
  /// 지금 이 스트림이 하는 일은 두 가지뿐이다: 시간이 다 된 요청 정리,
  /// 그리고 새로 온 것을 **가리기만 하는** 토스트. 답하는 자리는 '제안'
  /// 탭과 홈 카드다
  void _listenIncoming() {
    _incomingSub?.cancel();
    _incomingSub = _runs.incomingSessions(_auth.uid).listen((snap) async {
      // 한 번이라도 정상 수신되면 재시도 카운터를 되돌림
      if (_incomingRetries != 0 || _incomingBroken) {
        _incomingRetries = 0;
        if (mounted && _incomingBroken) setState(() => _incomingBroken = false);
      }
      for (final doc in snap.docs) {
        // 스트림이 시간으로 잘린 뒤로는 이미 수락·거절한 것까지 실려 온다
        if (doc.data()['status'] != SessionRules.invited) continue;
        // 시간이 다 된 요청은 정리한다
        // (createdAt이 아직 null이면 serverTimestamp 반영 전이므로 무시하지 않음)
        final createdAt = doc.data()['createdAt'] as Timestamp?;
        if (createdAt != null &&
            DateTime.now().difference(createdAt.toDate()) > kRequestTtl) {
          _runs.expireSession(doc.id);
          continue;
        }
        if (_announced.contains(doc.id)) continue;
        _announced.add(doc.id);
        // 앱을 켠 채로 받았을 때만 알린다. 처음 목록이 통째로 도착할 때는
        // 이미 알고 있던 것까지 줄줄이 뜨므로 건너뛴다
        if (!_announcedPrimed) continue;
        // 러닝 중에는 알리지 않는다 — 달리는 사람에게 다른 사람의 초대는
        // 지금 답할 수 있는 일이 아니다
        if (ActiveRunGuard.active) continue;
        final hostId = doc.data()['hostId'] as String;
        final host = await FirebaseFirestore.instance
            .collection('users').doc(hostId).get();
        if (!mounted) return;
        GoToast.show(context,
            '${_displayName(host.data()?['name'])}님이 함께 달리자고 해요');
      }
      _announcedPrimed = true;
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

  /// GO?를 보내는 중인 상대의 uid. 세션 생성은 왕복이 있어서 그 사이
  /// 버튼이 그대로면 사람들은 반응이 없다고 생각해 한 번 더 누르고,
  /// 그러면 같은 상대에게 세션이 두 개 만들어진다 — 상대 화면에는 수락
  /// 시트가 두 번 뜨고, 하나는 영영 주인 없이 남는다
  String? _sendingTo;

  /// GO?는 **화면을 바꾸지 않는다**(2026-09-09).
  ///
  /// 전에는 세션을 만들자마자 로비로 밀어 넣었다. 상대가 요청을 본 적도
  /// 없는데 화면 제목이 이미 "함께 달릴 준비"였고, 답이 언제 올지 모르는
  /// 채로 사용자는 그 화면에 갇혔다. 지금은 홈에 머물고 카드가 상태를
  /// 말한다 — 폰을 주머니에 넣고 기다려도 된다
  Future<void> _sendGo(String friendUid, String friendName) async {
    if (_sendingTo != null) return; // 연타·다른 행 동시 탭 모두 여기서 막힌다
    setState(() => _sendingTo = friendUid);
    try {
      await _runs.createSession(_auth.uid, friendUid);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (!mounted) return;
      GoToast.error(context, '요청을 보내지 못했어요. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _sendingTo = null);
    }
  }

  /// 양쪽이 동시에 GO?를 눌러 세션이 둘 생긴 것을 접는다.
  ///
  /// 두 기기가 각자 같은 판정을 내리고 **자기가 할 수 있는 것만** 한다 —
  /// 접는 것은 누구든, 수락은 게스트만(규칙이 그렇게 막는다). 겹쳐 불러도
  /// 두 번째 쓰기는 SessionRules가 null을 돌려 아무 일도 하지 않는다
  void _resolveCollisions(List<Invite> list) {
    final merges = inviteCollisions(list, _auth.uid, DateTime.now());
    for (final m in merges) {
      if (_merging.contains(m.drop.sessionId)) continue;
      _merging.add(m.drop.sessionId);
      _runs.cancelSession(m.drop.sessionId).catchError((_) {});
      if (m.iAmGuestOfKeep) {
        _runs.acceptSession(m.keep.sessionId).catchError((_) {});
      }
    }
  }

  @override
  void dispose() {
    _incomingSub?.cancel();
    _friendsSub?.cancel();
    _invitesSub?.cancel();
    _hidden.removeListener(_onHiddenChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final friends = _friendList;
    final roles = GoRoles.of(context);
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // ── 상단 워드마크(중앙) + 친구 찾기 ──
        WordmarkHeader(
          trailing: GoIconButton(
            icon: Icons.search,
            color: roles.textSecondary,
            onTap: () => showFriendSearchSheet(context),
            tooltip: '페이스메이트 찾기',
          ),
        ),
        // ── 연결 문제 안내 ──
        if (_incomingBroken || _friendsError) _connectionNotice(),
        // ── 같이 뛰는 사람들 ──
        // 화면의 첫 콘텐츠는 관계다. 이 앱의 값어치는 내 숫자가 아니라
        // 저쪽에 사람이 있다는 것이고, 위계는 그 순서를 따라야 한다
        const Padding(
          padding: EdgeInsets.fromLTRB(22, 14, 22, 10),
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
                  : Column(children: friends.map(_pacemateCard).toList()),
        ),
        // 친구가 없어도 전체 흐름을 체험할 수 있는 통로. 심사관이 로비·러닝·
        // 완료 화면을 볼 유일한 방법이라 반드시 눈에 띄는 곳에 있어야 함
        if (_friendsLoaded && friends.isEmpty) _demoLink(),
        // ── 내 기록 ── 관계 아래. 내 숫자는 확인하는 것이지 첫 화면에서
        // 마주쳐야 하는 것이 아니다
        const Padding(
          padding: EdgeInsets.fromLTRB(22, GoSpace.section, 22, 10),
          child: Text('내 기록', style: GoText.label),
        ),
        _profileCard(friends.length),
        const SizedBox(height: GoSpace.xl),
      ],
    );
  }

  /// 목록이 들어올 자리. 값 대신 회색 면만 두어 높이를 미리 차지한다.
  /// **뼈대의 모양은 들어올 것과 같아야 한다** — 행이던 뼈대가 카드로
  /// 바뀌면 자리를 잡아 둔 의미가 없어지고 화면이 한 번 더 튄다
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
    return Column(
      children: List.generate(
        2,
        (_) => Container(
          margin: const EdgeInsets.fromLTRB(22, 0, 22, 10),
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            color: roles.surface,
            borderRadius: BorderRadius.circular(GoRadius.md),
            boxShadow: GoShadow.card,
          ),
          child: Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration:
                  BoxDecoration(color: roles.line, shape: BoxShape.circle),
            ),
            const SizedBox(width: GoSpace.m),
            Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [bar(96, 13), const SizedBox(height: 6), bar(64, 10)]),
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
        Icon(Icons.wifi_off, size: 18, color: roles.warning.fg),
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
        // 이름·사진은 한 줄로 눕는다. 세로로 쌓인 큰 아바타는 이 카드를
        // 화면의 주인공으로 만들었는데, 여기는 확인하는 자리다
        Row(children: [
          GoAvatar(size: 36, photoUrl: _me?['photoUrl'] as String?),
          const SizedBox(width: GoSpace.m),
          Expanded(
            child: Text(myName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: roles.textPrimary)),
          ),
        ]),
        // 불러오는 중인지는 아래 숫자가 '—'로 말한다 — 같은 것을 두 번 말하지 않는다
        const SizedBox(height: 12),
        Container(height: 1, color: roles.line),
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

  /// 페이스메이트 한 명 — 홈의 주인공.
  ///
  /// 카드를 누르면 상세 시트가 열린다(progressive disclosure). 전에는 행
  /// 오른쪽의 ⋯ 하나가 유일한 입구였는데, GO? 바로 옆에서 표적을 나눠 갖고
  /// 있으면서 정작 무엇이 열리는지는 알려주지 않았다. 지금은 카드 전체가
  /// 눌리고(2층 → 눌림), 차단·연결 끊기는 그 시트 안에 있다
  Widget _pacemateCard(Map<String, dynamic> f) {
    final name = _displayName(f['name']);
    final uid = f['uid'] as String;
    final now = DateTime.now();
    // 치운 결과는 홈에서도 안 보인다. 살아 있는 제안은 치울 수 없으므로
    // (오가는 중에는 스와이프가 없다) 여기서 가려질 일이 없다
    final invite = currentInviteFor(
        _inviteList.where((i) =>
            i.isOpen(now) || !_hidden.contains(i.sessionId)),
        uid,
        now);
    return PacemateCard(
      key: ValueKey(uid),
      user: f,
      name: name,
      invite: invite,
      onOpen: () => _openProfile(f, name),
      onGo: () => _sendGo(uid, name),
      onMessage: () => _openThread(uid, name),
      goLoading: _sendingTo == uid,
      // 다른 행을 보내는 중이면 이 행도 눌리지 않는다 — 두 사람에게
      // 동시에 GO?를 보내면 어느 로비로 들어갈지가 경합이 된다
      goEnabled: _sendingTo == null || _sendingTo == uid,
      answerable: false,
    );
  }

  void _openProfile(Map<String, dynamic> f, String name) {
    final uid = f['uid'] as String;
    showFriendProfileSheet(
      context,
      user: f,
      name: name,
      myUid: _auth.uid,
      // 시트가 열릴 때 한 번만 부른다 — 시트 안에서 만들면 리빌드마다
      // 다시 조회하면서 숫자가 깜빡인다('우리' 탭이 같은 함정을 밟았다)
      togetherFuture: _runs.finishedSessionsWith(_auth.uid, uid),
      onGo: () => _sendGo(uid, name),
      onMessage: () => _openThread(uid, name),
      onDisconnect: () => _confirmRemoveFriend(uid, name),
      onBlock: () => _confirmBlock(uid, name),
    );
  }

  /// 홈에서 대화로 바로 간다. 대화 탭을 거치면 세 번인 길을 한 번으로
  void _openThread(String uid, String name) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ThreadScreen(partnerUid: uid, partnerName: name),
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
      ]),
    );
  }
}
