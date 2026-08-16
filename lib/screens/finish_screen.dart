import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/auth_service.dart';
import '../services/run_service.dart';
import '../theme.dart';
import '../widgets/brand_mark.dart';
import '../widgets/go_toast.dart';
import '../widgets/pressable.dart';
import 'root_screen.dart';

/// 완료 화면 — 프로토타입 s-finish 충실 구현 (라임 배경)
/// 공유 카드: 화면 상단부를 그대로 이미지로 캡처 → 성장 엔진
class FinishScreen extends StatefulWidget {
  final String sessionId;
  final String partnerName;
  final int mySeconds;
  final double myKm;
  final int myKcal;
  final String? myMood;
  final bool demo;

  const FinishScreen({
    super.key,
    required this.sessionId,
    required this.partnerName,
    required this.mySeconds,
    required this.myKm,
    required this.myKcal,
    this.myMood,
    this.demo = false,
  });

  @override
  State<FinishScreen> createState() => _FinishScreenState();
}

class _FinishScreenState extends State<FinishScreen> {
  final _cardKey = GlobalKey();

  /// 공유 시트의 기준점을 잡기 위한 키 — [_shareOrigin] 주석 참조
  final _shareButtonKey = GlobalKey();
  Map<String, dynamic>? _partnerResult;
  StreamSubscription? _sub;
  bool _longWait = false;
  Timer? _waitTimer;
  int? _totalRuns;
  int? _weekStreak;

  /// 상황을 아는 타이틀 — 첫 러닝인지, 스트릭이 이어지고 있는지에 따라 변주
  String get _title {
    if (_totalRuns == 1) return '처음으로 함께 달렸어요';
    if ((_weekStreak ?? 0) >= 2) return '$_weekStreak주째, 발이 맞아요';
    return '오늘도 함께 달렸어요';
  }

  @override
  void initState() {
    super.initState();
    _waitTimer = Timer(const Duration(minutes: 5), () {
      if (mounted && _waiting) setState(() => _longWait = true);
    });
    if (widget.demo) {
      // 데모는 Firestore 없이 진행 — 처음 함께 달린 느낌으로 고정
      _totalRuns = 1;
      _weekStreak = 1;
      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;
        setState(() => _partnerResult = {
              'seconds': widget.mySeconds + 40,
              'km': (widget.myKm * 0.9 + 0.1),
              'kcal': (widget.myKcal * 0.9).round(),
              'mood': '네 생각 났어요',
            });
      });
      return;
    }
    AuthService().myProfile().then((profile) {
      if (!mounted || profile == null) return;
      setState(() {
        _totalRuns = ((profile['totalRuns'] ?? 0) as num).toInt();
        _weekStreak = ((profile['weekStreak'] ?? 0) as num).toInt();
      });
    });
    _subscribeToResults();
  }

  void _subscribeToResults() {
    _sub = RunService().sessionStream(widget.sessionId).listen((doc) {
      final results =
          Map<String, dynamic>.from(doc.data()?['results'] ?? {});
      final uid = AuthService().uid;
      final partner = results.entries
          .where((e) => e.key != uid)
          .map((e) => Map<String, dynamic>.from(e.value))
          .firstOrNull;
      if (partner != null && mounted) {
        setState(() => _partnerResult = partner);
      }
    }, onError: (_) {
      // 결과 감지가 끊기면 조용히 멈추는 대신 잠시 뒤 재구독
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) _subscribeToResults();
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _waitTimer?.cancel();
    super.dispose();
  }

  bool get _waiting => _partnerResult == null;
  double get _partnerKm =>
      ((_partnerResult?['km'] ?? 0) as num).toDouble();
  double get _togetherKm => widget.myKm + _partnerKm;
  int get _togetherKcal =>
      widget.myKcal + ((_partnerResult?['kcal'] ?? 0) as num).toInt();

  String _fmt(int sec) =>
      "${sec ~/ 60}'${(sec % 60).toString().padLeft(2, '0')}\"";

  /// 공유 카드: 화면 상단부를 그대로 캡처해 공유 시트로 넘긴다.
  ///
  /// **`sharePositionOrigin`이 없으면 iOS에서 시트가 아예 안 뜬다.**
  /// 2026-08-16에 시뮬레이터에서 확인함 — 이 인자 없이 부르면
  /// `PlatformException(sharePositionOrigin: argument must be set … must be
  /// non-zero)`로 끝난다. 아이패드 팝오버 기준점으로만 알려져 있어 아이폰에서는
  /// 생략해도 되는 줄 알았는데 아니었고, 그래서 공유가 한 번도 동작한 적이
  /// 없었다. 공유 카드는 이 앱의 성장 엔진이라 조용히 죽어 있으면 안 된다.
  ///
  /// **어떤 경로로도 조용히 끝나지 않는다.** 예전에는 캡처 대상이나 인코딩
  /// 결과가 없으면 그냥 `return`했는데, 그러면 눌러도 아무 일이 없는 버튼이
  /// 되고 그건 앱 전체의 신뢰를 깎는다. 카드를 못 만들면 최소한 글이라도
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

  /// 공유 시트가 어디서 나오는지 — 아이패드에서는 팝오버가 이 자리에 붙고,
  /// 아이폰에서는 보이지 않지만 **값이 없으면 호출 자체가 거부된다.**
  /// 버튼을 못 찾으면 화면 중앙의 작은 사각형으로 대신한다(0 크기는 거부됨)
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

  /// 카드 이미지를 임시 파일로. 만들 수 없으면 null(글만 공유하게 됨)
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GoColors.lime,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 10, 28, 24),
          child: Column(children: [
            // ── 공유 카드로 캡처되는 영역 ──
            RepaintBoundary(
              key: _cardKey,
              child: Container(
                color: GoColors.lime,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(children: [
                  BrandMark.compact(),
                  const SizedBox(height: 12),
                  Text('나 & ${widget.partnerName}\n$_title',
                      textAlign: TextAlign.center,
                      style: GoTheme.serif(28, color: GoColors.ink)),
                  const SizedBox(height: 20),
                  // 함께 합산 블록 (fin-together)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: GoColors.ink.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(children: [
                      Text('함께 달린 것',
                          style: TextStyle(fontSize: 8,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2,
                              color: GoColors.ink.withValues(alpha: .4))),
                      const SizedBox(height: 12),
                      Row(children: [
                        _togetherStat(_fmt(widget.mySeconds), '내가 달린 시간'),
                        _tDivider(),
                        _togetherStat(
                            _waiting
                                ? '${widget.myKm.toStringAsFixed(1)}+'
                                : '${_togetherKm.toStringAsFixed(1)}km',
                            '함께 거리'),
                        _tDivider(),
                        _togetherStat(
                            _waiting
                                ? '${widget.myKcal}+'
                                : '$_togetherKcal',
                            'kcal 합산'),
                      ]),
                      // 러닝 화면에 있던 '합산은 완료 후 계산돼요'가 온 자리 —
                      // 합산이 실제로 일어나는 곳에서 한 번만 말한다
                      const SizedBox(height: 8),
                      Text(
                          _waiting
                              ? '${widget.partnerName}의 기록이 도착하면 합쳐져요'
                              : '둘의 기록을 합친 값이에요',
                          style: TextStyle(
                              fontSize: 11,
                              color: GoColors.ink.withValues(alpha: .4))),
                    ]),
                  ),
                  const SizedBox(height: 8),
                  Text('goingon · 멀리 있어도, 함께',
                      style: GoTheme.serif(12,
                          color: GoColors.ink.withValues(alpha: .35))),
                ]),
              ),
            ),
            const SizedBox(height: 14),
            // ── 개인 기록 (fin-ind-row) ──
            Align(
              alignment: Alignment.centerLeft,
              child: Text('개인 기록',
                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                      color: GoColors.ink.withValues(alpha: .4))),
            ),
            const SizedBox(height: 8),
            Row(children: [
              _personalCard('나', widget.myKm, GoColors.limeDark,
                  mood: widget.myMood),
              const SizedBox(width: 10),
              _personalCard(widget.partnerName,
                  _waiting ? null : _partnerKm, GoColors.coralDark,
                  mood: _waiting ? null : _partnerResult?['mood'] as String?),
            ]),
            if (_waiting) ...[
              const SizedBox(height: 10),
              Text(
                  _longWait
                      ? "${widget.partnerName}의 기록이 도착하면 '우리' 탭에 합산될 거예요. 먼저 쉬고 있어요."
                      : '${widget.partnerName}는 아직 달리는 중이에요',
                  style: TextStyle(
                      fontSize: 11, color: GoColors.ink.withValues(alpha: .4))),
            ],
            const SizedBox(height: 18),
            // ── CTA ──
            Pressable(
              onTap: () => Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const RootScreen()),
                  (_) => false),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  color: GoColors.ink,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Center(
                  child: Text('다음에 또 함께 달려요',
                      style: GoTheme.serif(18, color: GoColors.lime)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Pressable(
              key: _shareButtonKey,
              onTap: _shareCard,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                child: Text('오늘의 순간 공유하기',
                    style: TextStyle(
                        fontSize: 12,
                        color: GoColors.ink.withValues(alpha: .4))),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _togetherStat(String v, String label) {
    return Expanded(
      child: Column(children: [
        Text(v, style: GoTheme.serif(26, color: GoColors.ink)),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(fontSize: 8, letterSpacing: .8,
                color: GoColors.ink.withValues(alpha: .4))),
      ]),
    );
  }

  Widget _tDivider() =>
      Container(width: 1, height: 32, color: GoColors.ink.withValues(alpha: .12));

  Widget _personalCard(String who, double? km, Color color, {String? mood}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: GoColors.ink.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(who,
              style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600,
                  letterSpacing: .8, color: color)),
          const SizedBox(height: 4),
          Text(km == null ? '달리는 중...' : '${km.toStringAsFixed(1)}km',
              style: GoTheme.serif(km == null ? 14 : 22)),
          Text('개인 총 거리',
              style: TextStyle(
                  fontSize: 9, color: GoColors.ink.withValues(alpha: .4))),
          if (mood != null) ...[
            const SizedBox(height: 4),
            Text("'$mood'",
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w600, color: color)),
          ],
        ]),
      ),
    );
  }
}
