import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/friend_service.dart';
import '../services/ghost/today_partner.dart';
import '../services/ghost/today_partner_loader.dart';
import '../theme.dart';
import '../widgets/friend_search_sheet.dart';
import '../widgets/initial_avatar.dart';
import '../widgets/pressable.dart';
import 'pacemates_screen.dart';
import 'today_partner_screen.dart';

/// 홈 — 한 화면.
///
/// 원래는 레벨에 따라 두 얼굴이었다(입문자=8분 에피소드 전면 / 경험자=자유런
/// 전면). 그 분기의 근거가 에피소드였는데 **에피소드런을 내리면서 근거가
/// 사라져** 하나로 합쳤다(2026-09-01 결정).
///
/// `users.level`과 온보딩의 레벨 질문은 그대로 둔다 — 데이터는 계속 쌓이고,
/// 나중에 분기할 근거가 생기면 그때 다시 갈라진다. 지금 지우면 그 사이에
/// 가입한 사람들의 답만 비게 된다.
///
/// 로비는 없다(P5에서 삭제). 상대를 고르는 일은 [TodayPartnerScreen]이 맡고,
/// 그 화면은 서로 기다리지 않는다.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.onOpenJourney});

  /// '여정' 카드를 눌렀을 때. 탭 전환은 셸(RootScreen)의 일이라 올려 보낸다
  final VoidCallback? onOpenJourney;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _auth = AuthService();
  final _friends = FriendService();
  final _loader = TodayPartnerLoader();

  Map<String, dynamic>? _me;
  TodayPartners _partners = TodayPartners.empty;

  /// 페이스메이트 프로필. 홈에 **명단**을 두려는 게 아니라 **문**을 두려는
  /// 것이다(§6 원칙 3: 그 자체로 소비되고 끝나는 소셜은 만들지 않는다) —
  /// 아바타를 누르면 그 사람의 리듬으로 바로 들어간다
  StreamSubscription? _matesSub;
  List<Map<String, dynamic>> _mates = const [];

  /// 지금 함께 달릴 리듬을 가진 사람. 있는 사람만 라임 링이 붙는다.
  /// **숫자는 쓰지 않는다** — 몇 개인지가 아니라 있는지 없는지만 말한다
  Set<String> _withRhythm = const {};

  /// 나에게 온 페이스메이트 요청. 놓치면 상대는 무한정 기다리므로 홈 맨 위에
  /// 한 줄로 남긴다 — 목록 자체는 페이스메이트 화면의 일이다
  StreamSubscription? _requestsSub;
  int _requestCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _listenRequests();
    _listenMates();
  }

  @override
  void dispose() {
    _requestsSub?.cancel();
    _matesSub?.cancel();
    super.dispose();
  }

  void _listenRequests() {
    _requestsSub = _friends.incomingRequestsStream(_auth.uid).listen((list) {
      if (mounted) setState(() => _requestCount = list.length);
    }, onError: (Object e, StackTrace s) {
      FirebaseCrashlytics.instance.recordError(e, s, fatal: false);
    });
  }

  void _listenMates() {
    _matesSub = _friends.friendsStream(_auth.uid).listen((list) {
      if (mounted) setState(() => _mates = list);
    }, onError: (Object e, StackTrace s) {
      FirebaseCrashlytics.instance.recordError(e, s, fatal: false);
    });
  }

  Future<void> _load() async {
    try {
      final me = await _auth.myProfile();
      if (mounted) setState(() => _me = me);
      final partners = await _loader.load(_auth.uid);
      if (!mounted) return;
      setState(() {
        _partners = partners;
        _withRhythm = {
          for (final p in partners.list)
            if (p.reason == PartnerReason.pacemate) p.ghost.uid,
        };
      });
    } catch (e, stack) {
      // 홈은 실패해도 서 있어야 한다. 상대를 못 불러오면 카드가 한 줄
      // 덜 말할 뿐이고, 시작 버튼은 그대로 눌린다
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
    }
  }

  void _openPartners() => Navigator.push(context,
      MaterialPageRoute(builder: (_) => const TodayPartnerScreen()));

  void _openPacemates() => Navigator.push(
      context, MaterialPageRoute(builder: (_) => const PacematesScreen()));

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('goingon', style: GoTheme.serif(16, color: GoColors.dim)),
          const SizedBox(height: 14),
          if (_requestCount > 0) ...[
            _requestBanner(),
            const SizedBox(height: 14),
          ],
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: _cards(),
            ),
          ),
          const SizedBox(height: 14),
          Pressable(
            onTap: _openPartners,
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: GoColors.ink,
                borderRadius: BorderRadius.circular(26),
              ),
              alignment: Alignment.center,
              child: Text('오늘의 러닝 시작',
                  style: GoTheme.serif(18, color: GoColors.paper)),
            ),
          ),
        ],
      ),
    );
  }

  /// 카드 두 장. 에피소드가 내려가면서 히어로 자리는 **오늘 누구와 달리는가**가
  /// 가져갔다 — 이 앱이 파는 것이 8분이라는 형식이 아니라 함께라는 사실이라면,
  /// 형식이 빠진 자리에 남는 것이 그것이다
  List<Widget> _cards() => [
        _card(
          height: 160,
          onTap: _openPartners,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _label('오늘'),
            const SizedBox(height: 10),
            Text(_heroTitle, style: GoTheme.serif(24)),
            const SizedBox(height: 8),
            Text(_partnerLine,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12, height: 1.5, color: GoColors.mid)),
          ]),
        ),
        const SizedBox(height: 14),
        _pacematesCard(),
        const SizedBox(height: 14),
        _journeyCard(),
      ];

  /// 페이스메이트 — 명단이 아니라 문이다.
  ///
  /// 에피소드런이 내려가면서 홈 아래쪽이 통째로 비었고, "기록이 아니라
  /// 관계"를 파는 앱의 홈에서 관계가 안 보이는 것은 이상하다(2026-09-01).
  /// 그래서 이 줄을 세우되 §6의 원칙을 지킨다 — 누르면 그 사람의 리듬으로
  /// 들어가고, 거기서 함께 달리기로 이어진다.
  ///
  /// **숫자를 쓰지 않는다.** 팔로워·팔로잉 수를 노출하지 않기로 했고(P6.5),
  /// 1차 세그먼트는 기록이 부끄러운 사람들이라 남의 성과를 늘어놓을 자리도
  /// 아니다. 말하는 것은 "함께 달릴 리듬이 있는가" 하나뿐이다
  // 높이 계산: 여백 28 + 라벨 17 + 간격 12 + 아바타 44 + 5 + 이름 14 = 120.
  // 118로 뒀다가 7px 넘쳤다 — 이름이 잘려 나갔다
  Widget _pacematesCard() => _card(
        height: 132,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(children: [
          Row(children: [
            _label('페이스메이트'),
            const Spacer(),
            Pressable(
              onTap: _openPacemates,
              child: const Icon(Icons.chevron_right,
                  size: 18, color: GoColors.dim),
            ),
          ]),
          const SizedBox(height: 12),
          Expanded(
            child: _mates.isEmpty ? _noMatesYet() : _mateStrip(),
          ),
        ]),
      );

  Widget _noMatesYet() => Pressable(
        onTap: () => showFriendSearchSheet(context),
        child: const Row(children: [
          Icon(Icons.person_add_alt, size: 20, color: GoColors.limeDark),
          SizedBox(width: 10),
          Expanded(
            child: Text('함께 달릴 사람을 찾아요 — 아이디 하나면 돼요',
                style: TextStyle(fontSize: 13, color: GoColors.mid)),
          ),
        ]),
      );

  Widget _mateStrip() => ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: _mates.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, i) =>
            i == _mates.length ? _findMore() : _mateAvatar(_mates[i]),
      );

  Widget _mateAvatar(Map<String, dynamic> mate) {
    final uid = mate['uid'] as String;
    final name = _displayName(mate['name']);
    final ready = _withRhythm.contains(uid);
    return Pressable(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              TodayPartnerScreen(pacemateUid: uid, pacemateName: name),
        ),
      ),
      child: SizedBox(
        width: 52,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          InitialAvatar(
            letter: name[0],
            size: 44,
            fontSize: 18,
            // 리듬이 있으면 라임 — '나'의 색이 아니라 '지금 함께 달릴 수
            // 있다'는 신호로 쓴다. 상대의 성과가 아니라 가능성의 표시다
            borderColor: ready ? GoColors.limeDark : GoColors.line,
            borderWidth: ready ? 2 : 1.5,
            photoUrl: mate['photoUrl'] as String?,
          ),
          const SizedBox(height: 5),
          Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: GoColors.mid)),
        ]),
      ),
    );
  }

  Widget _findMore() => Pressable(
        onTap: () => showFriendSearchSheet(context),
        child: SizedBox(
          width: 52,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: GoColors.line, width: 1.5),
              ),
              child: const Icon(Icons.add, size: 20, color: GoColors.dim),
            ),
            const SizedBox(height: 5),
            const Text('찾기',
                style: TextStyle(fontSize: 11, color: GoColors.dim)),
          ]),
        ),
      );

  static String _displayName(Object? name) {
    final s = name is String ? name.trim() : '';
    return s.isEmpty ? '페이스메이트' : s;
  }

  Widget _journeyCard() => _card(
        height: 84,
        onTap: widget.onOpenJourney,
        child: Text(_journeyLine,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: GoColors.ink)),
      );

  /// 함께 달릴 리듬이 있으면 그것이, 없으면 자유런이 히어로다
  String get _heroTitle => _partners.first == null ? '자유런' : '오늘의 상대';

  /// 오늘의 상대 한 줄. 못 불러왔거나 아직 없으면 **없다고 말하지 않는다** —
  /// 고르러 가는 문을 열어둘 뿐이다
  String get _partnerLine {
    final p = _partners.first;
    if (p == null) return '오늘의 사운드트랙과 함께 — 고스트 동행을 골라도 돼요';
    final name = _partners.names[p.ghost.uid] ?? '페이스메이트';
    final who = switch (p.reason) {
      PartnerReason.pacemate => '$name의 지난 리듬',
      PartnerReason.myPast => '지난번의 나',
      PartnerReason.seed => '어느 러너의 리듬',
    };
    final story = p.ghost.story;
    return story == null || story.isEmpty ? who : '$who\n"$story"';
  }

  String get _journeyLine {
    final km = ((_me?['monthKm'] ?? 0) as num).toDouble();
    final streak = ((_me?['weekStreak'] ?? 0) as num).toInt();
    if (km <= 0) return '우리 여정 — 첫 걸음이 여기 쌓여요';
    final tail = streak >= 2 ? ' · $streak주 연속' : '';
    return '우리 여정 ${km.toStringAsFixed(1)}km$tail';
  }

  Widget _requestBanner() => Pressable(
        onTap: _openPacemates,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: GoColors.coral.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: GoColors.coral.withValues(alpha: .25)),
          ),
          child: Row(children: [
            Expanded(
              child: Text('함께 달리자는 요청 $_requestCount건',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: GoColors.ink)),
            ),
            const Icon(Icons.chevron_right, size: 18, color: GoColors.coralDark),
          ]),
        ),
      );

  Widget _label(String text) => Text(text,
      style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
          color: GoColors.dim));

  Widget _card({
    required Widget child,
    required double height,
    VoidCallback? onTap,
    EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 16),
  }) {
    final card = Container(
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: GoColors.line),
      ),
      alignment: Alignment.center,
      child: child,
    );
    return onTap == null ? card : Pressable(onTap: onTap, child: card);
  }
}
