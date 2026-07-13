import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/auth_service.dart';
import '../services/run_service.dart';
import '../theme.dart';
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

  Future<void> _shareCard() async {
    final boundary = _cardKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 3.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/goingon_card.png');
    await file.writeAsBytes(bytes.buffer.asUint8List());
    await Share.shareXFiles(
      [XFile(file.path)],
      text: '멀리 있어도, 함께 달렸어요 🏃 #goingon',
    );
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
                  // 브랜드 마크 — 두 원
                  SizedBox(
                    width: 66, height: 42,
                    child: Stack(children: [
                      Positioned(
                        left: 2, top: 2,
                        child: Container(
                          width: 38, height: 38,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: GoColors.limeDark.withOpacity(.15),
                            border: Border.all(
                                color: GoColors.limeDark, width: 2),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 2, top: 2,
                        child: Container(
                          width: 38, height: 38,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: GoColors.coral.withOpacity(.25),
                            border: Border.all(
                                color: GoColors.coralDark, width: 2),
                          ),
                        ),
                      ),
                    ]),
                  ),
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
                      color: GoColors.ink.withOpacity(.08),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(children: [
                      Text('함께 달린 것',
                          style: TextStyle(fontSize: 8,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2,
                              color: GoColors.ink.withOpacity(.4))),
                      const SizedBox(height: 12),
                      Row(children: [
                        _togetherStat(_fmt(widget.mySeconds), '함께한 시간'),
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
                    ]),
                  ),
                  const SizedBox(height: 8),
                  Text('goingon · 멀리 있어도, 함께',
                      style: GoTheme.serif(12,
                          color: GoColors.ink.withOpacity(.35))),
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
                      color: GoColors.ink.withOpacity(.4))),
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
                      fontSize: 11, color: GoColors.ink.withOpacity(.4))),
            ],
            const SizedBox(height: 18),
            // ── CTA ──
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: GoColors.ink,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                ),
                onPressed: () => Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const RootScreen()),
                    (_) => false),
                child: Text('다음에 또 함께 달려요',
                    style: GoTheme.serif(18, color: GoColors.lime)),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: _shareCard,
              child: Text('오늘의 순간 공유하기',
                  style: TextStyle(
                      fontSize: 12, color: GoColors.ink.withOpacity(.4))),
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
                color: GoColors.ink.withOpacity(.4))),
      ]),
    );
  }

  Widget _tDivider() =>
      Container(width: 1, height: 32, color: GoColors.ink.withOpacity(.12));

  Widget _personalCard(String who, double? km, Color color, {String? mood}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: GoColors.ink.withOpacity(.07),
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
                  fontSize: 9, color: GoColors.ink.withOpacity(.4))),
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
