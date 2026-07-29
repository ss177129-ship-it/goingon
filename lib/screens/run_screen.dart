import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../services/active_run_guard.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/run_service.dart';
import '../theme.dart';
import '../widgets/go_dialog.dart';
import 'finish_screen.dart';

/// 러닝 화면 — 각자 GPS로 기록, 끝나면 합산 (MVP: 라이브 동기화 없음)
class RunScreen extends StatefulWidget {
  final String sessionId;
  final String partnerName;
  final bool demo;
  const RunScreen(
      {super.key,
      required this.sessionId,
      required this.partnerName,
      this.demo = false});

  @override
  State<RunScreen> createState() => _RunScreenState();
}

class _RunScreenState extends State<RunScreen>
    with TickerProviderStateMixin {
  final _location = LocationService();
  Timer? _timer;
  DateTime? _startedAt;
  int _seconds = 0;
  double _km = 0;
  bool _gpsOk = true;
  bool _finishing = false;
  late final AnimationController _breath;

  // ── 제스처 상호작용(탭/스와이프/롱프레스로 상대에게 신호 보내기) ──
  late final AnimationController _gesturePop;
  StreamSubscription? _sessionSub;
  DateTime? _lastPartnerGestureAt;
  String? _gestureType;
  bool _gestureFromPartner = false;
  int _gestureSeq = 0;
  Timer? _gestureLabelTimer;
  Offset? _gestureStart;
  Timer? _holdTimer;

  @override
  void initState() {
    super.initState();
    ActiveRunGuard.active = true;
    _breath = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _gesturePop = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    WakelockPlus.enable();
    if (!widget.demo) _listenPartnerGesture();
    _start();
  }

  /// 상대가 보낸 제스처 신호 감지 — 위치/페이스는 안 보내고 이 필드 하나만 봄
  void _listenPartnerGesture() {
    _sessionSub = RunService().sessionStream(widget.sessionId).listen((doc) {
      final g = doc.data()?['gesture'] as Map<String, dynamic>?;
      if (g == null || g['uid'] == AuthService().uid) return;
      final at = (g['at'] as Timestamp?)?.toDate();
      if (at == null) return;
      if (_lastPartnerGestureAt != null && !at.isAfter(_lastPartnerGestureAt!)) {
        return;
      }
      _lastPartnerGestureAt = at;
      _playGesture(g['type'] as String, fromPartner: true);
    });
  }

  Future<void> _start() async {
    // 경과 시간은 틱 카운트가 아니라 시작 시각과의 차이로 계산 —
    // 폰이 잠겨 있는 동안 Timer 틱이 밀려도(백그라운드에서는 흔함)
    // 화면에 다시 나타났을 때 표시되는 시간이 실제와 어긋나지 않음
    _startedAt = DateTime.now();
    if (widget.demo) {
      // 미리보기: GPS 없이 가상 거리 증가 (시뮬레이터는 실제 GPS가 없어요)
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() {
          _seconds = DateTime.now().difference(_startedAt!).inSeconds;
          _km = _seconds * 0.003; // 약 5'30"/km 페이스
        });
      });
      return;
    }
    final ok = await _location.requestPermission(
      onBeforeAlwaysUpgrade: () {
        if (!mounted) return Future.value();
        return GoDialog.notice(
          context,
          title: '위치 접근 허용',
          body: '화면을 꺼도 러닝 기록이 끊기지 않으려면,\n다음 화면에서 "항상 허용"을 선택해 주세요.',
        );
      },
    );
    if (!ok) {
      setState(() => _gpsOk = false);
      return;
    }
    _location.start(
      (km) => setState(() => _km = km),
      onError: _handleGpsError,
    );
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(
          () => _seconds = DateTime.now().difference(_startedAt!).inSeconds);
    });
  }

  /// 러닝 도중 위치 서비스가 꺼지거나 권한이 취소되는 등
  /// GPS를 더 이상 쓸 수 없게 됐을 때 — 크래시 대신 안내 화면으로 전환
  void _handleGpsError() {
    if (!mounted) return;
    _timer?.cancel();
    _location.stop();
    setState(() => _gpsOk = false);
  }

  // ── 제스처 상호작용 ──
  // 짧게 탭 = 파이팅, 위로 스와이프 = 같이 빨라지자, 아래로 스와이프 = 천천히,
  // 길게 누르기(550ms) = 보고싶어. 프로토타입(design/prototype_v2.html)의
  // run-canvas-wrap 제스처를 그대로 옮김

  void _onGesturePointerDown(PointerDownEvent e) {
    _gestureStart = e.localPosition;
    _holdTimer = Timer(const Duration(milliseconds: 550), () {
      _sendGesture('heart');
      _gestureStart = null; // 롱프레스로 이미 처리됨 — pointerUp에서 또 판정하지 않음
    });
  }

  void _onGesturePointerUp(PointerUpEvent e) {
    _holdTimer?.cancel();
    final start = _gestureStart;
    if (start == null) return;
    _gestureStart = null;
    final dy = e.localPosition.dy - start.dy;
    final dist = (e.localPosition - start).distance;
    if (dist < 14) {
      _sendGesture('enc');
    } else if (dy < -20) {
      _sendGesture('up');
    } else if (dy > 20) {
      _sendGesture('dn');
    }
  }

  void _onGesturePointerCancel(PointerCancelEvent e) {
    _holdTimer?.cancel();
    _gestureStart = null;
  }

  Future<void> _sendGesture(String type) async {
    _playGesture(type, fromPartner: false);
    if (widget.demo) return;
    try {
      await RunService().sendGesture(widget.sessionId, AuthService().uid, type);
    } catch (e, stack) {
      // 로컬 애니메이션은 이미 보여줬으니 실패해도 조용히 무시 — 재시도 강요 안 함
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
    }
  }

  void _playGesture(String type, {required bool fromPartner}) {
    if (!mounted) return;
    if (type == 'heart' && !fromPartner) HapticFeedback.mediumImpact();
    setState(() {
      _gestureType = type;
      _gestureFromPartner = fromPartner;
      _gestureSeq++;
    });
    _gesturePop.forward(from: 0);
    _gestureLabelTimer?.cancel();
    _gestureLabelTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _gestureType = null);
    });
  }

  (String, Color) _gestureLabel(String type) {
    switch (type) {
      case 'up':
        return ('같이 빨라지자', GoColors.amber);
      case 'dn':
        return ('힘들어, 천천히', GoColors.coralDark);
      case 'heart':
        return ('보고싶어', GoColors.coralDark);
      default:
        return ('파이팅', GoColors.limeDark);
    }
  }

  Widget _gestureLabelWidget() {
    return SizedBox(
      height: 28,
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _gestureType == null
              ? const SizedBox.shrink(key: ValueKey('empty'))
              : ScaleTransition(
                  key: ValueKey(_gestureSeq),
                  scale: CurvedAnimation(
                      parent: _gesturePop, curve: Curves.easeOutBack),
                  child: _gestureChip(_gestureType!),
                ),
        ),
      ),
    );
  }

  Widget _gestureChip(String type) {
    final (text, color) = _gestureLabel(type);
    final label = _gestureFromPartner ? '${widget.partnerName} · $text' : text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(.3)),
      ),
      child: Text(label, style: GoTheme.serif(15, color: color)),
    );
  }

  Future<void> _finish(String? mood) async {
    if (_finishing) return;
    setState(() => _finishing = true);
    _timer?.cancel();
    _location.stop();
    WakelockPlus.disable();
    final kcal = LocationService.estimateKcal(_seconds);
    if (!widget.demo) {
      try {
        await RunService().submitResult(widget.sessionId, AuthService().uid,
            seconds: _seconds, km: _km, kcal: kcal, mood: mood);
      } catch (e, stack) {
        FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
        if (!mounted) return;
        setState(() => _finishing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('결과 저장에 실패했어요. 다시 시도해 주세요.')),
        );
        return;
      }
    }
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(
      builder: (_) => FinishScreen(
        sessionId: widget.sessionId,
        partnerName: widget.partnerName,
        mySeconds: _seconds,
        myKm: _km,
        myKcal: kcal,
        myMood: mood,
        demo: widget.demo,
      ),
    ));
  }

  @override
  void dispose() {
    _breath.dispose();
    _gesturePop.dispose();
    _sessionSub?.cancel();
    _gestureLabelTimer?.cancel();
    _holdTimer?.cancel();
    _timer?.cancel();
    _location.stop();
    WakelockPlus.disable();
    ActiveRunGuard.active = false;
    super.dispose();
  }

  /// 실수 종료 방지 — 마치기 전 한 번 확인
  Future<void> _confirmFinish() async {
    final confirmed = await GoDialog.confirm(
      context,
      title: '오늘 러닝을 마칠까요?',
      confirmLabel: '마치기',
      cancelLabel: '계속 달리기',
    );
    if (confirmed != true) return;
    if (!mounted) return;
    final mood = await _pickMood();
    if (!mounted) return;
    _finish(mood);
  }

  /// 결과 제출 직전 — 오늘 러닝이 어땠는지 한 탭으로 남김 (건너뛰기 가능)
  Future<String?> _pickMood() async {
    const moods = ['상쾌했어요', '죽을 뻔했어요', '네 생각 났어요', '또 하고 싶어요'];
    return showModalBottomSheet<String>(
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
              Text('오늘 러닝, 어땠어요?', style: GoTheme.serif(20)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: moods
                    .map((m) => OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: GoColors.line, width: 1.5),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20)),
                          ),
                          onPressed: () => Navigator.pop(ctx, m),
                          child: Text(m,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: GoColors.ink)),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text('건너뛰기',
                      style: TextStyle(color: GoColors.dim, fontSize: 13)),
                ),
              ),
            ]),
      ),
    );
  }

  String get _timeText {
    final m = _seconds ~/ 60, s = _seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (!_gpsOk) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('위치 권한이 필요해요', style: GoTheme.serif(24)),
              const SizedBox(height: 10),
              const Text('설정 > GoingOn > 위치에서 허용해 주세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: GoColors.mid)),
            ]),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: GoColors.canvas,
      body: SafeArea(
        child: Column(children: [
          // ── 상단: 나 | 함께 | 파트너 (프로토타입 run-pace-row) ──
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('나 · 페이스',
                          style: TextStyle(fontSize: 9,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1,
                              color: GoColors.limeDark.withOpacity(.6))),
                      Text(LocationService.pace(_km, _seconds),
                          style: GoTheme.serif(22, color: GoColors.limeDark)),
                      const Text('km당',
                          style:
                              TextStyle(fontSize: 9, color: GoColors.dim)),
                    ]),
                const Spacer(),
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('함께 달리는\n중이에요',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 8, letterSpacing: 1.2,
                          color: GoColors.dim)),
                ),
                const Spacer(),
                Column(crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${widget.partnerName} · 상태',
                          style: TextStyle(fontSize: 9,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1,
                              color: GoColors.coralDark.withOpacity(.6))),
                      Text('나란히',
                          style: GoTheme.serif(22, color: GoColors.coralDark)),
                      const Text('함께 시작했어요',
                          style: TextStyle(
                              fontSize: 9, color: GoColors.coralDark)),
                    ]),
              ],
            ),
          ),
          const Spacer(),
          // ── 함께 달리는 감각 — 겹치는 두 원. 탭/스와이프/롱프레스로
          // 상대에게 신호를 보낼 수 있음 (design/prototype_v2.html의
          // run-canvas-wrap 제스처)
          _gestureLabelWidget(),
          const SizedBox(height: 4),
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _onGesturePointerDown,
            onPointerUp: _onGesturePointerUp,
            onPointerCancel: _onGesturePointerCancel,
            child: SizedBox(
              width: 220, height: 140,
              child: Stack(alignment: Alignment.center, children: [
                Positioned(
                  left: 30,
                  child: _breathingCircle(GoColors.lime, GoColors.limeDark),
                ),
                Positioned(
                  right: 30,
                  child: _breathingCircle(GoColors.coral, GoColors.coralDark),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          const Text('탭·스와이프·길게 누르면 신호를 보낼 수 있어요',
              style: TextStyle(fontSize: 9, color: GoColors.dim)),
          const Spacer(),
          // ── 함께 합산 바 (프로토타입 together-bar) ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(children: [
              const Text('함께 달린 것',
                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600,
                      letterSpacing: 1.2, color: GoColors.dim)),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: GoColors.line),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(.05),
                        blurRadius: 6, offset: const Offset(0, 1)),
                  ],
                ),
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(children: [
                  _togetherCell(_timeText, GoColors.ink),
                  _togetherDivider(),
                  _togetherCell(_km.toStringAsFixed(1), GoColors.ink),
                  _togetherDivider(),
                  _togetherCell(
                      '${LocationService.estimateKcal(_seconds)}',
                      GoColors.resonance),
                ]),
              ),
              const SizedBox(height: 5),
              const Text('합산은 완료 후 계산돼요',
                  style: TextStyle(fontSize: 9, color: GoColors.dim)),
            ]),
          ),
          const SizedBox(height: 10),
          // ── 멈춤 ──
          GestureDetector(
            onLongPress: _finishing ? null : _confirmFinish,
            child: Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: GoColors.ink.withOpacity(.07),
                border: Border.all(color: GoColors.ink.withOpacity(.1)),
              ),
              child: const Center(
                child: Text('멈춤',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600,
                        color: GoColors.mid)),
              ),
            ),
          ),
          const SizedBox(height: 5),
          const Text('길게 누르면 종료',
              style: TextStyle(fontSize: 9, color: GoColors.dim)),
          const SizedBox(height: 32),
        ]),
      ),
    );
  }

  Widget _togetherCell(String v, Color color) {
    return Expanded(
        child: Center(child: Text(v, style: GoTheme.serif(20, color: color))));
  }

  Widget _togetherDivider() =>
      Container(width: 1, height: 24, color: GoColors.line);

  Widget _breathingCircle(Color fill, Color border) {
    // 나(정방향)와 상대(역방향)가 엇갈려 숨쉬어요 — 각자의 발걸음처럼
    final reverse = fill == GoColors.coral;
    return AnimatedBuilder(
      animation: _breath,
      builder: (_, __) {
        final t = reverse ? 1 - _breath.value : _breath.value;
        final scale = .95 + t * .1;
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 120, height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                fill.withOpacity(.3),
                fill.withOpacity(.06),
              ]),
              border: Border.all(color: border.withOpacity(.55), width: 2),
            ),
          ),
        );
      },
    );
  }
}
