import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/friend_service.dart';
import '../services/run_service.dart';
import '../theme.dart';
import '../widgets/initial_avatar.dart';
import 'invite_screen.dart';
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
  String? _handledSession;
  Map<String, dynamic>? _me;

  @override
  void initState() {
    super.initState();
    _load();
    _listenIncoming();
  }

  Future<void> _load() async {
    try {
      final p = await _auth.myProfile();
      if (mounted) setState(() => _me = p);
    } catch (e) {
      if (mounted) {
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) _load();
        });
      }
    }
  }

  /// 친구가 GO?를 보내면 여기서 감지 → 수락 시트
  void _listenIncoming() {
    _incomingSub = _runs.incomingSessions(_auth.uid).listen((snap) async {
      for (final doc in snap.docs) {
        if (doc.id == _handledSession) continue;
        _handledSession = doc.id;
        final hostId = doc.data()['hostId'] as String;
        final host = await FirebaseFirestore.instance
            .collection('users').doc(hostId).get();
        final hostName = host.data()?['name'] ?? '친구';
        if (!mounted) return;
        _showGoRequest(doc.id, hostName);
      }
    }, onError: (_) {
      // 권한/네트워크 문제로 감지가 끊기면 조용히 멈추는 대신 잠시 뒤 재구독
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) _listenIncoming();
      });
    });
  }

  void _showGoRequest(String sessionId, String hostName) {
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
    );
  }

  /// "나중에" 선택 시 침묵 대신 한 줄 답장을 고르게 함
  void _showDeclineOptions(String sessionId) {
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
    );
  }

  Future<void> _sendGo(String friendUid, String friendName) async {
    try {
      final sessionId = await _runs.createSession(_auth.uid, friendUid);
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(
        builder: (_) =>
            LobbyScreen(sessionId: sessionId, partnerName: friendName),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('요청을 보내지 못했어요. 다시 시도해 주세요.')),
      );
    }
  }

  @override
  void dispose() {
    _incomingSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _friends.friendsStream(_auth.uid),
      builder: (context, snap) {
        final friends = snap.data ?? [];
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            // ── 상단 워드마크 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 6),
              child: Text('goingon',
                  style:
                      GoTheme.serif(13, color: GoColors.ink.withOpacity(.3))),
            ),
            // ── 내 프로필 카드 ──
            _profileCard(friends.length),
            // ── 같이 뛰는 사람들 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
              child: Text('같이 뛰는 사람들',
                  style: const TextStyle(fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2, color: GoColors.dim)),
            ),
            if (friends.isEmpty)
              _noFriendsYet()
            else
              ...friends.map(_friendRow),
            // ── 초대 히어로 ──
            _inviteHero(),
            const SizedBox(height: 12),
          ],
        );
      },
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
  Widget _friendRow(Map<String, dynamic> f) {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: GoColors.line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
      child: Row(children: [
        InitialAvatar(
          letter: f['name'][0],
          size: 44,
          fontSize: 18,
          borderColor: GoColors.line,
          borderWidth: 1.5,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f['name'],
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600,
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
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: () => _sendGo(f['uid'], f['name']),
          child: Text('GO?', style: GoTheme.serif(18, color: GoColors.ink)),
        ),
      ]),
    );
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
        const SizedBox(height: 10),
        TextButton(
          onPressed: _openInvite,
          child: const Text('초대 코드를 받았나요? 입력하기 →',
              style: TextStyle(
                  fontSize: 13,
                  color: GoColors.limeDark,
                  fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: GoColors.line, width: 1.5),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => const LobbyScreen(
                    sessionId: 'demo', partnerName: '지수', demo: true),
              ));
            },
            child: Text('미리보기로 둘러보기',
                style: GoTheme.serif(16, color: GoColors.ink)),
          ),
        ),
      ]),
    );
  }

  /// 초대 히어로 — 프로토타입의 검은 카드
  Widget _inviteHero() {
    return GestureDetector(
      onTap: _openInvite,
      child: Container(
        margin: const EdgeInsets.fromLTRB(22, 16, 22, 6),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: GoColors.ink,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(children: [
          Icon(Icons.mail_outline,
              size: 34, color: GoColors.paper.withOpacity(.8)),
          const SizedBox(height: 8),
          Text('함께 달리고 싶은\n사람이 있나요?',
              textAlign: TextAlign.center,
              style: GoTheme.serif(21, color: GoColors.paper)),
          const SizedBox(height: 6),
          Text('한 명만 초대하면 시작돼요.',
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
              onPressed: _openInvite,
              child: const Text('초대하기',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600,
                      color: GoColors.ink)),
            ),
          ),
        ]),
      ),
    );
  }

  void _openInvite() {
    final code = _me?['inviteCode'] ?? '';
    final name = _me?['name'] ?? '';
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => InviteScreen(myCode: code, myName: name),
    )).then((_) => _load());
  }
}
