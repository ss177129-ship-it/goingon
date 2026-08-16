import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../services/resonance.dart';
import '../theme.dart';

/// 겹치는 두 원 — 이 앱이 "함께 달린다"를 보여주는 유일한 그림.
///
/// 규칙 하나로 적으면: **연속값은 매 프레임, 순간은 이벤트로.**
/// 겹침 정도는 [ResonanceEngine.smoothedCloseness]를 따라 부드럽게 움직이고,
/// 공명 진입 같은 순간은 이벤트를 받아 한 번 터진다. 두 경로를 섞으면
/// (예: 값이 문턱을 넘는 걸 매 프레임 확인해서 링을 쏘면) 경계에서 링이
/// 초당 수십 번 겹쳐 터진다 — 판정은 엔진에만 있어야 한다.
///
/// 성능: 다시 그리는 것은 [CustomPainter]의 `repaint`에 물린 프레임
/// 노티파이어뿐이다. **setState로 매 프레임 리빌드하지 않는다.** 화면이
/// 꺼지면 티커를 완전히 멈춘다 — 러닝 앱에서 배터리 소모는 삭제 사유다.
class ResonanceCanvas extends StatefulWidget {
  const ResonanceCanvas({super.key, required this.engine});

  final ResonanceEngine engine;

  @override
  State<ResonanceCanvas> createState() => _ResonanceCanvasState();
}

class _ResonanceCanvasState extends State<ResonanceCanvas>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// 이 값이 프레임 시계이자 다시 그리기 신호다. 위젯 트리는 건드리지 않는다
  final _frame = ValueNotifier<double>(0);
  late final Ticker _ticker;

  /// 공명 진입 순간마다 쌓이는 링의 시작 시각(초)
  final _bursts = <double>[];

  /// 지금 재생 중인 신호 애니메이션 (보낸 것 + 받은 것)
  final _signals = <_SignalAnim>[];

  /// 공명을 오래(30초 이상) 유지하는 중인가 — 겹침이 아주 느리게 숨 쉰다
  bool _breathing = false;

  StreamSubscription<ResonanceEvent>? _sub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_onTick)..start();
    _sub = widget.engine.events.listen(_onEvent);
  }

  void _onTick(Duration elapsed) {
    _frame.value = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
  }

  void _onEvent(ResonanceEvent e) {
    switch (e) {
      case ResonanceEntered():
        // 링과 햅틱은 여기 한 곳에서만 — 화면이 반짝이는 순간과 손에
        // 닿는 순간이 어긋나지 않게 같은 이벤트에 묶는다
        _bursts.add(_frame.value);
        _bursts.removeWhere((t) => _frame.value - t > _kBurstDuration);
        HapticFeedback.mediumImpact();
      case ResonanceHeld(:final held):
        if (held >= const Duration(seconds: 30)) _breathing = true;
      case ResonanceStateChanged(:final to):
        if (to != SyncState.resonant) _breathing = false;
      case SignalSent(:final kind):
        _addSignal(kind, fromPartner: false);
      case SignalReceived(:final kind):
        _addSignal(kind, fromPartner: true);
      default:
        break;
    }
  }

  void _addSignal(SignalKind kind, {required bool fromPartner}) {
    _signals.add(_SignalAnim(kind: kind, start: _frame.value, fromPartner: fromPartner));
    _signals.removeWhere((s) => _frame.value - s.start > s.duration);
    fromPartner ? _receivedHaptic(kind) : HapticFeedback.lightImpact();
  }

  /// 화면을 안 봐도 셋이 구분돼야 한다 — 그게 이 신호들의 설계 기준이다.
  /// 세기(가벼움 → 무거움)가 아니라 **박자**로 가른다. 주머니 속에서
  /// 세기 차이는 잘 안 느껴지지만 "한 번 / 두 번 / 길게"는 틀리지 않는다
  void _receivedHaptic(SignalKind kind) {
    switch (kind) {
      case SignalKind.here:
        HapticFeedback.lightImpact();
      case SignalKind.cheer:
        HapticFeedback.mediumImpact();
        Future.delayed(const Duration(milliseconds: 140), () {
          if (mounted) HapticFeedback.mediumImpact();
        });
      case SignalKind.slow:
        HapticFeedback.heavyImpact();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_ticker.isActive) {
        // 티커의 경과 시간은 재시작하면 0부터 다시 흐른다. 옛 시각으로 남은
        // 링은 영영 안 사라지거나 즉시 터지므로 함께 버린다
        _bursts.clear();
        _ticker.start();
      }
    } else if (_ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 이 안에서 매 프레임 다시 그려도 바깥 화면(페이스·시간 텍스트)까지
    // 다시 칠하지 않도록 격리한다
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _ResonancePainter(
          frame: _frame,
          engine: widget.engine,
          bursts: _bursts,
          signals: _signals,
          isBreathing: () => _breathing,
        ),
      ),
    );
  }
}

/// 링 한 번이 사는 시간(초)
const _kBurstDuration = 0.7;

/// 재생 중인 신호 하나.
///
/// 보낸 신호와 받은 신호는 **생김새가 반대**다. 보낸 것은 내 원에서 상대
/// 원 쪽으로 흘러가고(내가 무엇을 보냈는지 확인), 받은 것은 상대 원이
/// 맥동한다(상대가 무엇을 보냈는지 감각). 방향이 곧 누구인지다
class _SignalAnim {
  _SignalAnim({
    required this.kind,
    required this.start,
    required this.fromPartner,
  });

  final SignalKind kind;
  final double start;
  final bool fromPartner;

  /// 보낸 잔상은 0.5초. 받은 맥동은 종류마다 다르다 —
  /// '천천히 가자'가 느리고 긴 것은 그 말의 뜻 자체다
  double get duration => fromPartner
      ? switch (kind) {
          SignalKind.here => 0.45,
          SignalKind.cheer => 0.9,
          SignalKind.slow => 1.3,
        }
      : 0.5;
}

class _ResonancePainter extends CustomPainter {
  _ResonancePainter({
    required this.frame,
    required this.engine,
    required this.bursts,
    required this.signals,
    required this.isBreathing,
  }) : super(repaint: frame);

  final ValueListenable<double> frame;
  final ResonanceEngine engine;
  final List<double> bursts;
  final List<_SignalAnim> signals;
  final bool Function() isBreathing;

  @override
  void paint(Canvas canvas, Size size) {
    final t = frame.value;
    final closeness = engine.smoothedCloseness;

    final r = math.min(size.width * 0.285, size.height * 0.40);
    if (r <= 0) return;

    // 멀 때는 살짝 떨어져 있고, 공명에서는 거의 포개진다.
    // 완전히 포개지 않는 이유: 두 사람인 것이 끝까지 보여야 한다
    final gap = r * (2.02 - 1.72 * closeness);
    final center = Offset(size.width / 2, size.height / 2);
    final me = Offset(center.dx - gap / 2, center.dy);
    final partner = Offset(center.dx + gap / 2, center.dy);

    // 각자의 발걸음처럼 엇갈려 숨쉬기 (예전 화면에서 이어온 감각)
    final breath = 2 * math.pi * t / 1.8;
    final rMe = r * (1 + 0.03 * math.sin(breath));
    final rFr = r * (1 + 0.03 * math.sin(breath + math.pi));

    _paintAura(canvas, center, r, closeness);
    _paintCircles(canvas, me, partner, rMe, rFr);
    _paintOverlap(canvas, me, partner, rMe, rFr, closeness, t);
    _paintBursts(canvas, center, r, size, t);
    _paintSignals(canvas, me, partner, r, t);
  }

  /// 신호 — 보낸 것은 흘러가고, 받은 것은 상대 원이 맥동한다
  void _paintSignals(
      Canvas canvas, Offset me, Offset partner, double r, double t) {
    for (final s in signals) {
      final p = (t - s.start) / s.duration;
      if (p < 0 || p > 1) continue;
      if (s.fromPartner) {
        _paintReceived(canvas, partner, r, s.kind, p);
      } else {
        _paintSentTrail(canvas, me, partner, r, p);
      }
    }
  }

  /// 보낸 신호 — 내 색(lime) 잔상이 상대 쪽으로 흘러간다.
  /// 종류를 색이나 모양으로 구분하지 않는 이유: 보낸 사람은 방금 무슨
  /// 제스처를 했는지 이미 안다. 여기서 확인할 것은 "갔다"뿐이다
  void _paintSentTrail(
      Canvas canvas, Offset me, Offset partner, double r, double p) {
    final eased = Curves.easeOutCubic.transform(p);
    final pos = Offset.lerp(me, partner, eased)!;
    final fade = (1 - p) * (p < 0.15 ? p / 0.15 : 1);
    final radius = r * (0.42 - 0.18 * eased);
    canvas.drawCircle(
      pos,
      radius,
      Paint()
        ..shader = RadialGradient(colors: [
          GoColors.lime.withValues(alpha: 0.55 * fade),
          GoColors.lime.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: pos, radius: radius)),
    );
  }

  /// 받은 신호 — 상대 원(coral)이 종류마다 다른 박자로 맥동한다.
  /// 글자는 쓰지 않는다. 박자가 곧 뜻이다
  void _paintReceived(
      Canvas canvas, Offset partner, double r, SignalKind kind, double p) {
    switch (kind) {
      // "여기 있어" — 한 번 툭
      case SignalKind.here:
        _pulseRing(canvas, partner, r * (1 + 0.28 * p), (1 - p) * 0.75, 3.0);
      // "힘내" — 물결 두 번
      case SignalKind.cheer:
        for (final delay in const [0.0, 0.35]) {
          final q = (p - delay) / (1 - delay);
          if (q < 0 || q > 1) continue;
          _pulseRing(canvas, partner, r * (1 + 0.34 * q), (1 - q) * 0.7, 2.6);
        }
      // "천천히 가자" — 느리고 크게 한 번. 급할 것 없다는 말이라
      // 애니메이션도 급하지 않다
      case SignalKind.slow:
        final eased = Curves.easeOutQuart.transform(p);
        _pulseRing(canvas, partner, r * (1 + 0.62 * eased), (1 - p) * 0.6, 3.4);
        canvas.drawCircle(
          partner,
          r,
          Paint()
            ..color = GoColors.coral.withValues(alpha: 0.22 * (1 - p)),
        );
    }
  }

  void _pulseRing(
      Canvas canvas, Offset center, double radius, double alpha, double width) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = GoColors.coralDark.withValues(alpha: alpha.clamp(0.0, 1.0)),
    );
  }

  /// 지금 터지고 있는 링의 진행도(0~1). 없으면 null.
  /// 겹침을 함께 밝히는 데도 쓴다 — 링만 퍼지면 그림의 가장자리에서만
  /// 사건이 일어나고 정작 두 사람이 만나는 자리는 조용하다
  double? _burstProgress(double t) {
    for (final start in bursts) {
      final p = (t - start) / _kBurstDuration;
      if (p >= 0 && p <= 1) return p;
    }
    return null;
  }

  /// 가까워질수록 두 사람 사이에 도는 옅은 금빛
  void _paintAura(Canvas canvas, Offset center, double r, double closeness) {
    if (closeness <= 0.2) return;
    final radius = r * 2.2;
    final strength = ((closeness - 0.2) / 0.8).clamp(0.0, 1.0);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(colors: [
          GoColors.resonance.withValues(alpha: 0.10 * strength),
          GoColors.resonance.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  /// 나(lime)와 상대(coral). 겹치는 자리는 **곱하기로 섞인다** —
  /// 색이 물감처럼 겹쳐야 "겹치면 다른 색이 난다"가 설명 없이 읽힌다
  void _paintCircles(
      Canvas canvas, Offset me, Offset partner, double rMe, double rFr) {
    canvas.saveLayer(null, Paint());
    _disc(canvas, me, rMe, GoColors.lime, GoColors.limeDark, null);
    _disc(canvas, partner, rFr, GoColors.coral, GoColors.coralDark,
        BlendMode.multiply);
    canvas.restore();
  }

  void _disc(Canvas canvas, Offset c, double r, Color fill, Color edge,
      BlendMode? blend) {
    final rect = Rect.fromCircle(center: c, radius: r);
    final body = Paint()
      ..shader = RadialGradient(colors: [
        fill.withValues(alpha: 0.42),
        fill.withValues(alpha: 0.10),
      ]).createShader(rect);
    if (blend != null) body.blendMode = blend;
    canvas.drawCircle(c, r, body);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = edge.withValues(alpha: 0.55)
        ..blendMode = blend ?? BlendMode.srcOver,
    );
  }

  /// 겹친 자리에 도는 공명색. 곱하기 결과(탁한 주황)에서 출발해
  /// 가까워질수록 골드로 간다
  void _paintOverlap(Canvas canvas, Offset me, Offset partner, double rMe,
      double rFr, double closeness, double t) {
    var gold = ((closeness - 0.45) / 0.45).clamp(0.0, 1.0);
    // 진입 순간에는 겹침 자체가 한 번 밝아진다 — 링이 퍼지는 동안
    // 두 사람이 만나는 자리가 조용하면 사건이 가장자리에서만 일어난다
    final burst = _burstProgress(t);
    if (burst != null) gold = math.min(1.0, gold + 0.5 * math.exp(-4 * burst));
    if (gold <= 0) return;

    final overlap = Path.combine(
      PathOperation.intersect,
      Path()..addOval(Rect.fromCircle(center: me, radius: rMe)),
      Path()..addOval(Rect.fromCircle(center: partner, radius: rFr)),
    );
    final mid = Offset((me.dx + partner.dx) / 2, (me.dy + partner.dy) / 2);
    final bounds = overlap.getBounds();
    if (bounds.isEmpty) return;

    canvas.save();
    if (isBreathing()) {
      // 공명을 오래 유지할 때만 도는 아주 느린 숨 — 눈에 띄면 실패다
      final s = 1 + 0.02 * math.sin(2 * math.pi * t / 3);
      canvas.translate(mid.dx, mid.dy);
      canvas.scale(s);
      canvas.translate(-mid.dx, -mid.dy);
    }
    final radius = math.max(bounds.width, bounds.height) / 2;
    canvas.drawPath(
      overlap,
      Paint()
        ..shader = RadialGradient(colors: [
          GoColors.resonance.withValues(alpha: 0.55 * gold),
          GoColors.resonance.withValues(alpha: 0.12 * gold),
        ]).createShader(Rect.fromCircle(center: mid, radius: radius)),
    );
    canvas.restore();
  }

  /// 공명 진입 링 — 겹침 중심에서 한 번 퍼지고 지수적으로 사라진다.
  ///
  /// 링을 세 겹으로 시차를 두고 쏘는 이유: 한 겹이면 종이색 배경 위에서
  /// 그냥 옅은 원 하나가 스쳐 지나갈 뿐 "사건"으로 안 읽힌다.
  /// 퍼지는 끝은 캔버스 안에 가둔다 — 화면 밖으로 나가면 잘린 선만 보인다
  void _paintBursts(Canvas canvas, Offset center, double r, Size size, double t) {
    final maxR = math.min(size.width, size.height) / 2 * 0.98;
    for (final start in bursts) {
      final age = (t - start) / _kBurstDuration;
      if (age < 0 || age > 1) continue;
      for (final (delay, weight) in const [(0.0, 1.0), (0.12, .6), (0.24, .35)]) {
        final p = (age - delay) / (1 - delay);
        if (p < 0 || p > 1) continue;
        final alpha =
            (math.exp(-2.0 * p) * (1 - p) * 1.5 * weight).clamp(0.0, 1.0);
        canvas.drawCircle(
          center,
          r * 0.85 + (maxR - r * 0.85) * Curves.easeOutCubic.transform(p),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.2 * (1 - 0.7 * p)
            ..color = GoColors.resonance.withValues(alpha: alpha),
        );
      }
    }
  }

  // 다시 그리기는 frame 노티파이어가 몰아서 시킨다. 위젯이 다시 만들어지는
  // 경우(화면 회전 등)에만 여기로 오므로 그때는 그냥 다시 그린다
  @override
  bool shouldRepaint(covariant _ResonancePainter old) => true;
}
