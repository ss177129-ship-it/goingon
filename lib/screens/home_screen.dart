import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';

import '../services/active_run_guard.dart';
import '../services/auth_service.dart';
import '../services/friend_service.dart';
import '../services/run_service.dart';
import '../theme.dart';
import '../widgets/friend_search_sheet.dart';
import '../widgets/go_dialog.dart';
import '../widgets/go_toast.dart';
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
        _showGoRequest(doc.id, hostName);
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
    return s.isEmpty ? '친구' : s;
  }

  void _showGoRequest(String sessionId, String hostName) {
    _openSheets++;
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      backgroundColor: GoColors.paper,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: GoColors.coral.withOpacity(.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('함께 달리기 요청',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                    color: GoColors.coralDark, letterSpacing: 1.2)),
          ),
          const SizedBox(height: 18),
          InitialAvatar(
            letter: hostName[0],
            size: 88,
            fontSize: 36,
            fill: GoColors.coral.withOpacity(.12),
            borderColor: GoColors.coralDark,
          ),
          const SizedBox(height: 16),
          Text('$hostName님이\n같이 달리자고 해요',
              textAlign: TextAlign.center, style: GoTheme.serif(26)),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: GoColors.lime,
                padding: const EdgeInsets.symmetric(vertical: 17),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => LobbyScreen(
                      sessionId: sessionId, partnerName: hostName),
                ));
              },
              child: Text('수락하고 함께 달리기',
                  style: GoTheme.serif(19, color: GoColors.ink)),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showDeclineOptions(sessionId);
            },
            child: const Text('나중에',
                style: TextStyle(color: GoColors.mid, fontSize: 13)),
          ),
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
      backgroundColor: GoColors.paper,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('어떻게 전할까요?', style: GoTheme.serif(20)),
              const SizedBox(height: 16),
              ...options.map((o) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: GoColors.line, width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: () {
                          _runs.declineSession(sessionId, o);
                          Navigator.pop(ctx);
                        },
                        child: Text(o,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: GoColors.ink)),
                      ),
                    ),
                  )),
            ]),
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _openSheets--);
    });
  }

  Future<void> _sendGo(String friendUid, String friendName) async {
    try {
      final sessionId = await _runs.createSession(_auth.uid, friendUid);
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(
        builder: (_) =>
            LobbyScreen(sessionId: sessionId, partnerName: friendName),
      ));
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (!mounted) return;
      GoToast.error(context, '요청을 보내지 못했어요. 다시 시도해 주세요.');
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
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // ── 상단 워드마크 + 친구 찾기 ──
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 10, 12, 6),
          child: Row(children: [
            Text('goingon',
                style:
                    GoTheme.serif(13, color: GoColors.ink.withOpacity(.3))),
            const Spacer(),
            IconButton(
              onPressed: () => showFriendSearchSheet(context),
              icon: const Icon(Icons.search, color: GoColors.dim),
              tooltip: '친구 찾기',
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
          child: Text('같이 뛰는 사람들',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  color: GoColors.dim)),
        ),
        if (friends.isEmpty)
          _noFriendsYet()
        else
          ...friends.map(_friendRow),
        // ── 초대 히어로 ──
        _inviteHero(),
        // 친구가 없어도 전체 흐름을 체험할 수 있는 통로. 심사관이 로비·러닝·
        // 완료 화면을 볼 유일한 방법이라 반드시 눈에 띄는 곳에 있어야 함
        if (friends.isEmpty) _demoLink(),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _demoLink() {
    return Center(
      child: TextButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const LobbyScreen(
                sessionId: 'demo', partnerName: '지수', demo: true),
          ),
        ),
        child: const Text('혼자서 먼저 체험해보기 →',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: GoColors.limeDark)),
      ),
    );
  }

  /// 나에게 온 친구 요청 — 프로필 카드보다 위에 둠. 푸시가 없어서 앱을
  /// 열었을 때 보이는 게 전부이고, 놓치면 상대는 무한정 기다리게 됨
  List<Widget> _requestSection() {
    return [
      const Padding(
        padding: EdgeInsets.fromLTRB(22, 14, 22, 8),
        child: Text('나에게 온 요청',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
                color: GoColors.dim)),
      ),
      ..._requests.map(_requestRow),
    ];
  }

  Widget _requestRow(FriendRequest r) {
    final name = _displayName(r.name);
    return Container(
      margin: const EdgeInsets.fromLTRB(22, 0, 22, 8),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: GoColors.coral.withOpacity(.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: GoColors.coral.withOpacity(.25), width: 1.5),
      ),
      child: Column(children: [
        Row(children: [
          InitialAvatar(
            letter: name[0],
            size: 40,
            fontSize: 17,
            fill: GoColors.coral.withOpacity(.12),
            borderColor: GoColors.coralDark,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$name님이 함께 달리고 싶어해요',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: GoColors.ink)),
                  if (r.username.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text('@${r.username}',
                        style: const TextStyle(
                            fontSize: 11, color: GoColors.mid)),
                  ],
                ]),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: GoColors.line, width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => _respondToRequest(r, accept: false),
              child: const Text('거절',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: GoColors.mid)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: GoColors.lime,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => _respondToRequest(r, accept: true),
              child: const Text('수락하고 연결',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: GoColors.ink)),
            ),
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
    return Container(
      margin: const EdgeInsets.fromLTRB(22, 6, 22, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: GoColors.amber.withOpacity(.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GoColors.amber.withOpacity(.25)),
      ),
      child: Row(children: [
        const Icon(Icons.wifi_off, size: 18, color: GoColors.amber),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            _incomingBroken
                ? '지금은 함께 달리기 요청을 받지 못하고 있어요.'
                : '친구 목록을 불러오지 못했어요.',
            style: TextStyle(
                fontSize: 12, height: 1.4, color: GoColors.ink.withOpacity(.7)),
          ),
        ),
        TextButton(
          onPressed: () {
            setState(() {
              _incomingRetries = 0;
              _friendsRetries = 0;
              _incomingBroken = false;
              _friendsError = false;
            });
            _listenIncoming();
            _listenFriends();
            _load();
          },
          child: const Text('다시 시도',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: GoColors.ink)),
        ),
      ]),
    );
  }

  /// 내 프로필 카드 — 프로토타입의 흰 카드 + 3분할 스탯
  Widget _profileCard(int friendCount) {
    final myName = _me?['name'] ?? '';
    final now = DateTime.now();
    final monthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final monthKm = (_me?['monthKey'] == monthKey)
        ? ((_me?['monthKm'] ?? 0) as num).toDouble()
        : 0.0;
    final totalRuns = (_me?['totalRuns'] ?? 0) as num;
    return Container(
      margin: const EdgeInsets.fromLTRB(22, 6, 22, 0),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: GoColors.line),
      ),
      child: Column(children: [
        InitialAvatar(
          letter: myName.isEmpty ? '' : myName[0],
          size: 60,
          fontSize: 26,
          fill: GoColors.lime.withOpacity(.18),
          borderColor: GoColors.limeDark,
          emptyIcon: Icons.person_outline,
        ),
        const SizedBox(height: 8),
        Text(myName, style: GoTheme.serif(22)),
        const SizedBox(height: 3),
        const Text('함께 달릴 준비 완료',
            style: TextStyle(fontSize: 12, color: GoColors.limeDark)),
        const SizedBox(height: 14),
        Container(height: 1, color: GoColors.line),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _stat(monthKm.toStringAsFixed(1), 'km', '이번 달'),
            _statDivider(),
            _stat('$totalRuns', '', '함께 달림'),
            _statDivider(),
            _stat('$friendCount', '명', '함께하는 사람'),
          ]),
        ),
      ]),
    );
  }

  Widget _stat(String v, String unit, String label) {
    return Expanded(
      child: Column(children: [
        Text.rich(TextSpan(children: [
          TextSpan(text: v, style: GoTheme.serif(19)),
          TextSpan(
              text: unit,
              style: const TextStyle(fontSize: 11, color: GoColors.mid)),
        ])),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(fontSize: 9, letterSpacing: .54,
                color: GoColors.dim)),
      ]),
    );
  }

  Widget _statDivider() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Container(width: 1, color: GoColors.line),
      );

  /// 친구 행 — 프로토타입의 friend-row (아바타 + 이름 + GO?)
  /// 길게 누르면 연결 끊기 / 차단 메뉴
  Widget _friendRow(Map<String, dynamic> f) {
    final name = _displayName(f['name']);
    final uid = f['uid'] as String;
    return GestureDetector(
      onLongPress: () => _showFriendActions(uid, name),
      child: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: GoColors.line)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
        child: Row(children: [
          InitialAvatar(
            letter: name[0],
            size: 44,
            fontSize: 18,
            borderColor: GoColors.line,
            borderWidth: 1.5,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: GoColors.ink)),
                  const SizedBox(height: 1),
                  const Text('멀리 있어도, 함께',
                      style: TextStyle(fontSize: 11, color: GoColors.mid)),
                ]),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: GoColors.lime,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () => _sendGo(uid, name),
            child: Text('GO?', style: GoTheme.serif(18, color: GoColors.ink)),
          ),
        ]),
      ),
    );
  }

  /// 연결 끊기 / 차단 선택. 둘의 차이가 분명해야 해서 설명을 함께 보여줌 —
  /// 끊기는 상대가 다시 요청을 보낼 수 있고, 차단은 그것까지 막음
  void _showFriendActions(String uid, String name) {
    showModalBottomSheet(
      context: context,
      backgroundColor: GoColors.paper,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(name, style: GoTheme.serif(20)),
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
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: GoColors.line, width: 1.5),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        alignment: Alignment.centerLeft,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      onPressed: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: destructive ? GoColors.coralDark : GoColors.ink)),
        const SizedBox(height: 2),
        Text(note,
            style: const TextStyle(
                fontSize: 11, height: 1.4, color: GoColors.mid)),
      ]),
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
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 22),
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: GoColors.line, width: 1.5),
      ),
      child: Column(children: [
        Text('아직 함께 뛰는 사람이 없어요',
            style: GoTheme.serif(18, color: GoColors.mid)),
        const SizedBox(height: 6),
        const Text('한 명만 있으면 고잉온이 시작돼요.',
            style: TextStyle(fontSize: 12, color: GoColors.dim)),
      ]),
    );
  }

  /// 친구 찾기 히어로 — 프로토타입의 검은 카드
  Widget _inviteHero() {
    return GestureDetector(
      onTap: () => showFriendSearchSheet(context),
      child: Container(
        margin: const EdgeInsets.fromLTRB(22, 16, 22, 6),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: GoColors.ink,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(children: [
          Icon(Icons.search,
              size: 34, color: GoColors.paper.withOpacity(.8)),
          const SizedBox(height: 8),
          Text('함께 달리고 싶은\n사람이 있나요?',
              textAlign: TextAlign.center,
              style: GoTheme.serif(21, color: GoColors.paper)),
          const SizedBox(height: 6),
          Text('아이디로 찾아 요청을 보내요.',
              style: TextStyle(
                  fontSize: 12, color: GoColors.paper.withOpacity(.55))),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: GoColors.lime,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => showFriendSearchSheet(context),
              child: const Text('친구 찾기',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600,
                      color: GoColors.ink)),
            ),
          ),
        ]),
      ),
    );
  }
}
