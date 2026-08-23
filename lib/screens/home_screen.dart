import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../services/auth_service.dart';
import '../services/friend_service.dart';
import '../services/ghost/today_partner.dart';
import '../services/ghost/today_partner_loader.dart';
import '../services/onboarding/onboarding_progress.dart';
import '../services/onboarding/runner_level.dart';
import '../services/session/chart.dart';
import '../theme.dart';
import '../widgets/pressable.dart';
import 'pacemates_screen.dart';
import 'today_partner_screen.dart';

/// 홈 — 와이어프레임 05(입문자) / 06(경험자).
///
/// **한 화면의 두 얼굴이다.** 온보딩 질문 하나의 답이 정하는 것은 이것뿐이고
/// (§2-3), 그 아래 연결 레이어(공명·고스트·여정)는 둘이 똑같다. 갈리는 이유는
/// 결핍이 달라서다 — 입문자에게는 러닝 자체가 부담이라 8분 완결이 앞에
/// 놓이고, 경험자에게는 함께가 부재라 자유런이 앞에 놓인다.
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
  Chart? _episode;
  TodayPartners _partners = TodayPartners.empty;

  /// 나에게 온 페이스메이트 요청. 놓치면 상대는 무한정 기다리므로 홈 맨 위에
  /// 한 줄로 남긴다 — 목록 자체는 페이스메이트 화면의 일이다
  StreamSubscription? _requestsSub;
  int _requestCount = 0;

  RunnerLevel get _level => OnboardingProgress.levelOf(_me);

  @override
  void initState() {
    super.initState();
    _load();
    _loadEpisode();
    _listenRequests();
  }

  @override
  void dispose() {
    _requestsSub?.cancel();
    super.dispose();
  }

  void _listenRequests() {
    _requestsSub = _friends.incomingRequestsStream(_auth.uid).listen((list) {
      if (mounted) setState(() => _requestCount = list.length);
    }, onError: (Object e, StackTrace s) {
      FirebaseCrashlytics.instance.recordError(e, s, fatal: false);
    });
  }

  Future<void> _load() async {
    try {
      final me = await _auth.myProfile();
      if (mounted) setState(() => _me = me);
      final partners = await _loader.load(_auth.uid, max: 1);
      if (mounted) setState(() => _partners = partners);
    } catch (e, stack) {
      // 홈은 실패해도 서 있어야 한다. 상대를 못 불러오면 카드가 한 줄
      // 덜 말할 뿐이고, 시작 버튼은 그대로 눌린다
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
    }
  }

  /// 에피소드는 코드가 아니라 데이터다(§3-6) — 앱 번들의 채보를 읽는다.
  /// 지금은 한 편뿐이라 '오늘의'는 고정이고, 편성이 생기면 여기만 바뀐다
  Future<void> _loadEpisode() async {
    try {
      final json =
          await rootBundle.loadString('assets/episodes/episode_train.chart.json');
      final chart = Chart.parse(json);
      if (mounted) setState(() => _episode = chart);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
    }
  }

  void _openPartners() => Navigator.push(context,
      MaterialPageRoute(builder: (_) => const TodayPartnerScreen()));

  void _openPacemates() => Navigator.push(
      context, MaterialPageRoute(builder: (_) => const PacematesScreen()));

  @override
  Widget build(BuildContext context) {
    final beginner = _level == RunnerLevel.beginner;
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
              children: beginner ? _beginnerCards() : _experiencedCards(),
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
              child: Text(beginner ? '오늘의 8분 시작' : '자유런 시작',
                  style: GoTheme.serif(18, color: GoColors.paper)),
            ),
          ),
        ],
      ),
    );
  }

  // ── 입문자: 8분 에피소드가 전면 ──
  List<Widget> _beginnerCards() => [
        _card(
          height: 160,
          onTap: _openPartners,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _label('오늘의 에피소드'),
            const SizedBox(height: 10),
            Text(_episodeTitle, style: GoTheme.serif(24)),
            const SizedBox(height: 8),
            Text(_partnerLine,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12, height: 1.5, color: GoColors.mid)),
          ]),
        ),
        const SizedBox(height: 14),
        _journeyCard(),
      ];

  // ── 경험자: 자유런이 전면, 에피소드는 마디로 ──
  List<Widget> _experiencedCards() => [
        _card(
          height: 160,
          onTap: _openPartners,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _label('오늘'),
            const SizedBox(height: 10),
            Text('자유런', style: GoTheme.serif(24)),
            const SizedBox(height: 8),
            const Text('오늘의 사운드트랙과 함께 — 고스트 동행을 골라도 돼요',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12, height: 1.5, color: GoColors.mid)),
          ]),
        ),
        const SizedBox(height: 14),
        _card(
          height: 84,
          onTap: _openPartners,
          child: Text('$_episodeTitle · 8분 — 오프닝으로 몸 올리기',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: GoColors.ink)),
        ),
        const SizedBox(height: 14),
        _journeyCard(),
      ];

  Widget _journeyCard() => _card(
        height: 84,
        onTap: widget.onOpenJourney,
        child: Text(_journeyLine,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: GoColors.ink)),
      );

  String get _episodeTitle => _episode?.title ?? '오늘의 8분';

  /// 오늘의 상대 한 줄. 못 불러왔거나 아직 없으면 **없다고 말하지 않는다** —
  /// 고르러 가는 문을 열어둘 뿐이다
  String get _partnerLine {
    final p = _partners.first;
    if (p == null) return '8분 · 함께 달릴 리듬 고르기';
    final name = _partners.names[p.ghost.uid] ?? '페이스메이트';
    final who = switch (p.reason) {
      PartnerReason.pacemate => '$name의 지난 리듬',
      PartnerReason.myPast => '지난번의 나',
      PartnerReason.seed => '어느 러너의 리듬',
    };
    final story = p.ghost.story;
    return story == null || story.isEmpty
        ? '8분 · 오늘의 상대: $who'
        : '8분 · 오늘의 상대: $who\n"$story"';
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
  }) {
    final card = Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 16),
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
