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
      default:
        break;
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
          isBreathing: () => _breathing,
        ),
      ),
    );
  }
}

/// 링 한 번이 사는 시간(초)
const _kBurstDuration = 0.7;

class _ResonancePainter extends CustomPainter {
  _ResonancePainter({
    required this.frame,
    required this.engine,
    required this.bursts,
    required this.isBreathing,
  }) : super(repaint: frame);

  final ValueListenable<double> frame;
  final ResonanceEngine engine;
  final List<double> bursts;
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
