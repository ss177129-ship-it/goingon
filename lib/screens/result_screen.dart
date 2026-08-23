import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/auth_service.dart';
import '../services/cheer/cheer.dart';
import '../services/onboarding/push_permission_gate.dart';
import '../services/push_service.dart';
import '../services/run_service.dart';
import '../theme.dart';
import '../widgets/brand_mark.dart';
import '../widgets/cadence_wave.dart';
import '../widgets/go_toast.dart';
import '../widgets/pressable.dart';
import 'root_screen.dart';

/// 13 결과 — **트랙이 주인공**(§5-3).
///
/// 순서가 고정이다: ① 오늘 만든 것 ② 함께 요약 ③ 여정 ④ 기록(접힘).
/// 거리·페이스가 맨 위에 오면 러너스 하이가 통계로 식는다. 기록은 있되
/// 조연이고, 펼쳐야 나온다.
class ResultScreen extends StatefulWidget {
  const ResultScreen({
    super.key,
    required this.sessionId,
    required this.partnerName,
    required this.mySeconds,
    required this.myKm,
    required this.myKcal,
    required this.cadence,
    required this.journeyKm,
    this.resonanceSeconds = 0,
    this.myMood,
    this.demo = false,
    this.onDone,
    this.partnerSnapshot,
    this.cheerTo,
    this.runId,
  });

  final String sessionId;
  final String partnerName;
  final int mySeconds;
  final double myKm;
  final int myKcal;

  /// 오늘의 리듬. 화면의 주인공이자 공유 카드에 담기는 것
  final List<double?> cadence;

  /// 오늘까지 쌓인 여정(오늘 포함)
  final double journeyKm;

  /// 함께한 초. 골드는 여기에만 쓴다
  final int resonanceSeconds;

  final String? myMood;
  final bool demo;

  /// 닫기를 눌렀을 때 홈 대신 갈 곳(온보딩 데모런)
  final VoidCallback? onDone;

  /// 세션 없는 러닝의 '상대' — 함께 달린 고스트의 그날 기록
  final Map<String, dynamic>? partnerSnapshot;

  /// 응원을 남길 상대. 고스트의 주인이고, 없으면 혼자 달린 것이다
  final String? cheerTo;

  final String? runId;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  final _cardKey = GlobalKey();
  final _shareButtonKey = GlobalKey();

  Map<String, dynamic>? _partnerResult;
  StreamSubscription? _sub;
  int? _totalRuns;
  int? _weekStreak;
  bool _recordOpen = false;
  bool _cheering = false;
  bool _cheered = false;

  bool get _solo => widget.sessionId.isEmpty;
  bool get _alone => _solo && _partnerResult == null;

  @override
  void initState() {
    super.initState();
    // 고스트의 그날 기록은 **데모보다 먼저** 채운다. 순서가 반대면
    // 상대가 있는 러닝인데도 화면이 '혼자 달렸어요'라고 말한다
    if (_solo) _partnerResult = widget.partnerSnapshot;
    if (widget.demo) {
      _totalRuns = 1;
      _weekStreak = 1;
      return;
    }
    AuthService().myProfile().then((profile) {
      if (!mounted || profile == null) return;
      setState(() {
        _totalRuns = ((profile['totalRuns'] ?? 0) as num).toInt();
        _weekStreak = ((profile['weekStreak'] ?? 0) as num).toInt();
      });
      _maybeAskPush(_totalRuns ?? 0);
    });
    if (!_solo) _subscribeToResults();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// 알림 권한을 묻는 **유일한 자리**(P5). iOS는 한 번 거절당하면 앱에서
  /// 다시 물을 수 없어서, 이 질문은 계정당 한 번 쓸 수 있는 카드다.
  /// 판정은 [PushPermissionGate]가 한 곳에서 하고 여기서는 따르기만 한다
  Future<void> _maybeAskPush(int completedRuns) async {
    final prefs = await SharedPreferences.getInstance();
    if (!PushPermissionGate.shouldAsk(
      completedRuns: completedRuns,
      alreadyAsked: prefs.getBool(PushPermissionGate.prefsKey) ?? false,
      isDemo: widget.demo,
    )) {
      return;
    }
    // 결과가 눈에 들어온 **뒤에** 시스템 팝업이 뜨게 한다. 방금 무엇을
    // 해냈는지 보이는 채로 묻는 것과, 팝업이 화면을 덮은 채 묻는 것은
    // 같은 질문이 아니다
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    await prefs.setBool(PushPermissionGate.prefsKey, true);
    await PushService.instance.requestAndStart(AuthService().uid);
  }

  void _subscribeToResults() {
    _sub = RunService().sessionStream(widget.sessionId).listen((doc) {
      final results = Map<String, dynamic>.from(doc.data()?['results'] ?? {});
      final uid = AuthService().uid;
      final partner = results.entries
          .where((e) => e.key != uid)
          .map((e) => Map<String, dynamic>.from(e.value))
          .firstOrNull;
      if (partner != null && mounted) {
        setState(() => _partnerResult = partner);
      }
    }, onError: (_) {
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) _subscribeToResults();
      });
    });
  }

  // ── 값 ──────────────────────────────────────────────────────

  String get _timeText {
    final m = widget.mySeconds ~/ 60, s = widget.mySeconds % 60;
    return "$m'${s.toString().padLeft(2, '0')}\"";
  }

  double? get _averageSpm {
    final known = widget.cadence.whereType<double>();
    if (known.isEmpty) return null;
    return known.reduce((a, b) => a + b) / known.length;
  }

  String get _header {
    final km = widget.myKm.toStringAsFixed(1);
    final streak = _weekStreak ?? 0;
    return streak >= 2 ? '오늘 완주 · ${km}km · $streak주 연속' : '오늘 완주 · ${km}km';
  }

  String get _journeyText {
    final j = widget.journeyKm >= 10
        ? widget.journeyKm.round().toString()
        : widget.journeyKm.toStringAsFixed(1);
    return '우리 여정 ${j}km';
  }

  // ── 동작 ────────────────────────────────────────────────────

  /// 응원은 지금 보내지만 **상대에게 들리는 것은 다음 러닝의 출발선**이다.
  /// 푸시는 도착했다는 예고만 나간다(§5-4)
  Future<void> _cheer() async {
    final to = widget.cheerTo;
    if (to == null || _cheering || _cheered) return;
    setState(() => _cheering = true);
    try {
      await CheerService().send(
        fromUid: AuthService().uid,
        toUid: to,
        runId: widget.runId,
      );
      if (!mounted) return;
      setState(() {
        _cheering = false;
        _cheered = true;
      });
      GoToast.show(context, '${widget.partnerName}의 다음 러닝 시작에 들려줄게요.');
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (!mounted) return;
      setState(() => _cheering = false);
      GoToast.error(context, '응원을 남기지 못했어요. 다시 시도해 주세요.');
    }
  }

  void _leave() {
    final done = widget.onDone;
    if (done != null) {
      done();
      return;
    }
    Navigator.pushAndRemoveUntil(context,
        MaterialPageRoute(builder: (_) => const RootScreen()), (_) => false);
  }

  /// 공유 카드: ① 카드를 그대로 캡처해 공유 시트로 넘긴다.
  ///
  /// **`sharePositionOrigin`이 없으면 iOS에서 시트가 아예 안 뜬다**
  /// (2026-08-16 확인). 아이패드 팝오버 기준점으로만 알려져 있어 아이폰에서는
  /// 생략해도 되는 줄 알았는데 아니었고, 그래서 공유가 한 번도 동작한 적이
  /// 없었다. 공유 카드는 이 앱의 성장 엔진이라 조용히 죽어 있으면 안 된다.
  ///
  /// 어떤 경로로도 조용히 끝나지 않는다 — 카드를 못 만들면 최소한 글이라도
  /// 공유하고, 그것마저 실패하면 실패했다고 말한다
  Future<void> _shareCard() async {
    const text = '멀리 있어도, 함께 달렸어요 🏃 #goingon';
    final origin = _shareOrigin();
    try {
      final file = await _captureCard();
      if (file == null) {
        await Share.share(text, sharePositionOrigin: origin);
        return;
      }
      await Share.shareXFiles([XFile(file.path)],
          text: text, sharePositionOrigin: origin);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (!mounted) return;
      GoToast.error(context, '공유 시트를 열지 못했어요. 다시 시도해 주세요.');
    }
  }

  Rect _shareOrigin() {
    final box =
        _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      return box.localToGlobal(Offset.zero) & box.size;
    }
    final size = MediaQuery.sizeOf(context);
    return Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2), width: 1, height: 1);
  }

  Future<File?> _captureCard() async {
    final boundary =
        _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 3.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return null;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/goingon_card.png');
    await file.writeAsBytes(bytes.buffer.asUint8List());
    return file;
  }

  // ── 화면 ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_header, style: GoTheme.serif(18)),
              const SizedBox(height: 14),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    RepaintBoundary(key: _cardKey, child: _trackCard()),
                    const SizedBox(height: 14),
                    _togetherCard(),
                    const SizedBox(height: 14),
                    _journeyCard(),
                    const SizedBox(height: 14),
                    _recordCard(),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Pressable(
                key: _shareButtonKey,
                onTap: _shareCard,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text('카드 공유',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: GoColors.mid)),
                ),
              ),
              const SizedBox(height: 4),
              Pressable(
                onTap: widget.cheerTo != null && !_cheered ? _cheer : _leave,
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: GoColors.ink,
                    borderRadius: BorderRadius.circular(26),
                  ),
                  alignment: Alignment.center,
                  child: Text(_ctaLabel,
                      style: GoTheme.serif(18, color: GoColors.paper)),
                ),
              ),
              if (widget.cheerTo != null && _cheered) ...[
                const SizedBox(height: 10),
                Pressable(
                  onTap: _leave,
                  child: const Text('마치기',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: GoColors.dim)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String get _ctaLabel {
    if (_cheering) return '보내는 중';
    if (_cheered) return '응원을 남겼어요';
    return widget.cheerTo != null ? '응원 남기고 마치기' : '마치기';
  }

  /// ① 오늘 만든 것 — 화면의 주인공이자 공유되는 것.
  ///
  /// **정식 트랙(내 리듬으로 렌더링된 1분 음원)은 아직 없다.** 스템 3벌이
  /// 준비되면 여기 재생 버튼이 붙는다. 그때까지 재생 버튼을 두지 않는 이유는
  /// 눌러도 아무 일이 없는 버튼이 앱 전체의 신뢰를 깎기 때문이다.
  /// 지금 주인공 자리를 채우는 것은 오늘의 리듬 그 자체다
  Widget _trackCard() {
    final avg = _averageSpm;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: GoColors.line),
      ),
      child: Column(children: [
        BrandMark.compact(),
        const SizedBox(height: 10),
        Text('오늘의 리듬', style: GoTheme.serif(24)),
        const SizedBox(height: 14),
        SizedBox(
          height: 64,
          child: widget.cadence.length < 2
              ? Center(
                  child: Text('리듬이 기록되지 않았어요',
                      style: TextStyle(
                          fontSize: 11,
                          color: GoColors.ink.withValues(alpha: .35))))
              : CadenceWave(widget.cadence, strokeWidth: 2),
        ),
        const SizedBox(height: 14),
        Row(children: [
          _stat(_timeText, '달린 시간'),
          _divider(),
          _stat('${widget.myKm.toStringAsFixed(1)}km', '거리'),
          _divider(),
          _stat(avg == null ? '—' : avg.round().toString(), '평균 spm'),
        ]),
        const SizedBox(height: 12),
        Text('goingon · 멀리 있어도, 함께',
            style: GoTheme.serif(12, color: GoColors.dim)),
      ]),
    );
  }

  /// ② 함께 요약. **골드는 여기에만 쓴다** — 공명은 둘이 함께 만든 것이라
  /// 희소해야 하고, kcal 같은 일반 지표에 같은 색을 쓰면 그 희소함이 사라진다
  Widget _togetherCard() {
    final seconds = widget.resonanceSeconds;
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: seconds > 0
                ? GoColors.resonance.withValues(alpha: .5)
                : GoColors.line),
      ),
      child: _alone
          ? const Text('오늘은 혼자 달렸어요 — 이 리듬이 누군가의 동반자가 돼요',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: GoColors.mid))
          : seconds > 0
              ? RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: const TextStyle(fontSize: 14, color: GoColors.ink),
                    children: [
                      TextSpan(text: '${widget.partnerName}와 '),
                      TextSpan(
                          text: '공명 $seconds초',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: GoColors.resonance)),
                    ],
                  ),
                )
              : Text('${widget.partnerName}와 함께 달렸어요',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: GoColors.ink)),
    );
  }

  /// ③ 여정 — 오늘이 놓인 자리. 혼자 뛴 거리도 여기 쌓인다(§5)
  Widget _journeyCard() => Container(
        height: 110,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: GoColors.line),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_journeyText, style: GoTheme.serif(22)),
          const SizedBox(height: 6),
          const Text('오늘이 놓인 자리예요',
              style: TextStyle(fontSize: 12, color: GoColors.mid)),
        ]),
      );

  /// ④ 기록 — 접혀 있다. 있되 조연이다
  Widget _recordCard() {
    final avg = _averageSpm;
    return Pressable(
      onTap: () => setState(() => _recordOpen = !_recordOpen),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: GoColors.line),
        ),
        child: Column(children: [
          Row(children: [
            const Expanded(
              child: Text('기록',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: GoColors.ink)),
            ),
            Icon(_recordOpen ? Icons.expand_less : Icons.expand_more,
                size: 20, color: GoColors.dim),
          ]),
          if (_recordOpen) ...[
            const SizedBox(height: 14),
            Row(children: [
              _stat('${widget.myKm.toStringAsFixed(2)}km', '거리'),
              _divider(),
              _stat(_timeText, '시간'),
              _divider(),
              _stat('${widget.myKcal}', 'kcal'),
              _divider(),
              _stat(avg == null ? '—' : avg.round().toString(), '평균 spm'),
            ]),
            if (widget.myMood != null) ...[
              const SizedBox(height: 12),
              Text("'${widget.myMood}'",
                  style: const TextStyle(fontSize: 12, color: GoColors.mid)),
            ],
          ],
        ]),
      ),
    );
  }

  Widget _stat(String value, String label) => Expanded(
        child: Column(children: [
          Text(value, style: GoTheme.serif(22)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontSize: 9, letterSpacing: .8, color: GoColors.dim)),
        ]),
      );

  Widget _divider() => Container(
      width: 1, height: 28, color: GoColors.ink.withValues(alpha: .1));
}
