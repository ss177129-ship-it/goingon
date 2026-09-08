import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../services/resonance.dart';
import '../theme.dart';

/// 두 개의 동심원 — 이 앱이 "함께 달린다"를 보여주는 유일한 그림.
///
/// **왜 나란히가 아니라 겹쳐 놓았나** (2026-08-17 재설계): 좌우로 떨어진 두
/// 원은 "두 사람이 각자 달린다"를 그린다. 우리가 팔려는 것은 두 사람의
/// 발구름이 하나로 포개지는 순간이라, 같은 중심을 두고 **반지름이 같아지는
/// 것**이 그 감각에 훨씬 가깝다. 발이 맞으면 두 원이 하나가 된다.
///
/// 반지름은 **케이던스**가 정한다. 속도가 아니라 발구름인 이유: 속도가 같아도
/// 보폭이 다르면 발은 안 맞는다. 원의 크기가 곧 "발을 얼마나 빨리 구르는가"다.
///
/// 규칙 하나로 적으면: **연속값은 매 프레임, 순간은 이벤트로.**
/// 반지름·색은 값을 따라 부드럽게 움직이고, 공명 진입 같은 순간은 이벤트를
/// 받아 한 번 터진다. 두 경로를 섞으면(값이 문턱을 넘는 걸 매 프레임 확인해
/// 링을 쏘면) 경계에서 링이 초당 수십 번 겹쳐 터진다 — 판정은 엔진에만 있어야 한다.
///
/// 성능: 다시 그리는 것은 [CustomPainter]의 `repaint`에 물린 프레임
/// 노티파이어뿐이다. **setState로 매 프레임 리빌드하지 않는다.** 화면이
/// 꺼지면 티커를 완전히 멈춘다 — 러닝 앱에서 배터리 소모는 삭제 사유다.
class ResonanceCanvas extends StatefulWidget {
  const ResonanceCanvas({
    super.key,
    required this.engine,
    this.myCadence,
    this.partnerCadence,
  });

  final ResonanceEngine engine;

  /// 지금 내 발구름(spm). 없으면 null — 시뮬레이터·권한 거부·데모
  final double? Function()? myCadence;

  /// 지금 상대 발구름(spm). 낡은 값은 호출부가 이미 걸러서 null로 준다
  final double? Function()? partnerCadence;

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

  final _radii = _RadiiState();

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
    _signals.add(
        _SignalAnim(kind: kind, start: _frame.value, fromPartner: fromPartner));
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
        _radii.lastPaintAt = 0;
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
    // 페인터에는 context가 없으므로 색은 여기서 꺼내 넘긴다. 캔버스는
    // 밝은 canvas 바탕 위라 나·상대는 다크 앵커(self/partner)를 쓴다
    final roles = GoRoles.of(context);
    // 이 안에서 매 프레임 다시 그려도 바깥 화면(페이스·시간 텍스트)까지
    // 다시 칠하지 않도록 격리한다
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _ResonancePainter(
          frame: _frame,
          engine: widget.engine,
          selfColor: roles.self,
          partnerColor: roles.partner,
          resonanceColor: roles.resonance,
          bursts: _bursts,
          signals: _signals,
          isBreathing: () => _breathing,
          myCadence: widget.myCadence,
          partnerCadence: widget.partnerCadence,
          radii: _radii,
        ),
      ),
    );
  }
}

/// 링 한 번이 사는 시간(초)
const _kBurstDuration = 0.7;

/// 케이던스와 발맞춤을 **원의 크기**로 옮기는 규칙.
///
/// 화면 없이 시험할 수 있도록 그리기에서 떼어냈다 — 이 매핑이 틀리면
/// 두 원이 영영 안 만나거나 처음부터 붙어 있는데, 둘 다 조용히 틀린다.
class CadenceRadius {
  const CadenceRadius._();

  /// 조깅은 대략 160~180spm이고 그 언저리가 화면 한가운데 크기로 보여야
  /// 한다. 아래위 폭은 걷기(140)와 스프린트(200)를 담을 정도로만 잡았다 —
  /// 더 넓히면 흔한 구간에서 원이 거의 안 움직여 "내 발구름이 그려진다"는
  /// 느낌이 사라진다
  static const cadenceMin = 140.0;
  static const cadenceMax = 200.0;

  /// 반지름이 오갈 범위(캔버스 기준 반지름에 대한 비율)
  static const radiusMin = 0.52;
  static const radiusMax = 1.0;

  /// 케이던스를 모를 때 쓰는 기준 크기. 두 원이 이 자리에서 숨만 쉰다
  static const radiusNominal = 0.76;

  /// 발구름 → 반지름 비율
  static double forCadence(double spm) {
    final n = ((spm - cadenceMin) / (cadenceMax - cadenceMin)).clamp(0.0, 1.0);
    return radiusMin + (radiusMax - radiusMin) * n;
  }

  /// 두 원이 가야 할 크기 (내 것, 상대 것).
  ///
  /// 세 경우가 있고 셋 다 정상이다:
  /// 1. 둘 다 케이던스를 안다 → 각자의 실제 발구름 (가장 정직하다)
  /// 2. 발맞춤만 안다(데모) → 내 원은 기준 크기, 상대 원이 발맞춤만큼
  ///    벌어진다. 발맞춤이 곧 케이던스 근접도라 꾸며낸 값이 아니다
  /// 3. 아무것도 모른다 → 둘 다 기준 크기. 숨만 쉬는 두 원
  static (double, double) targets({
    required double? myCadence,
    required double? partnerCadence,
    required bool hasCloseness,
    required double closeness,
  }) {
    if (myCadence != null && partnerCadence != null) {
      return (forCadence(myCadence), forCadence(partnerCadence));
    }
    if (hasCloseness) {
      final gap = (1 - closeness) * (radiusNominal - radiusMin);
      return (radiusNominal, radiusNominal - gap);
    }
    return (radiusNominal, radiusNominal);
  }
}

/// 부드럽게 따라가는 두 반지름(비율)과 마지막 프레임 시각.
///
/// 페인터가 아니라 State가 들고 있어야 한다 — 페인터는 위젯이 다시 빌드될
/// 때마다 새로 만들어지므로, 여기 값을 두면 그때마다 원 크기가 처음으로
/// 되돌아가 튄다
class _RadiiState {
  double mine = CadenceRadius.radiusNominal;
  double theirs = CadenceRadius.radiusNominal;
  double lastPaintAt = 0;
}

/// 재생 중인 신호 하나.
///
/// 보낸 신호와 받은 신호는 **방향이 반대**다. 보낸 것은 중심에서 바깥으로
/// 빠져나가고(내가 보냈다), 받은 것은 상대 원 위에서 맥동한다(상대가 왔다).
/// 동심원이라 좌우가 없어진 자리를 안팎이 대신한다.
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
    required this.myCadence,
    required this.partnerCadence,
    required this.radii,
    required this.selfColor,
    required this.partnerColor,
    required this.resonanceColor,
  }) : super(repaint: frame);

  final ValueListenable<double> frame;
  final ResonanceEngine engine;

  /// 나·상대·공명의 색. 위젯이 [GoRoles]에서 꺼내 넘긴다
  final Color selfColor;
  final Color partnerColor;
  final Color resonanceColor;
  final List<double> bursts;
  final List<_SignalAnim> signals;
  final bool Function() isBreathing;
  final double? Function()? myCadence;
  final double? Function()? partnerCadence;

  /// 부드럽게 따라가는 반지름. **State가 들고 있다** — 페인터는 매 빌드마다
  /// 새로 만들어지므로 여기 두면 화면이 갱신될 때마다 크기가 튄다
  final _RadiiState radii;

  @override
  void paint(Canvas canvas, Size size) {
    final t = frame.value;
    final closeness = engine.smoothedCloseness;

    final unit = math.min(size.width, size.height) * 0.42;
    if (unit <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);

    _advanceRadii(t, closeness);

    // 각자의 발걸음처럼 엇갈려 숨쉬기 (예전 화면에서 이어온 감각)
    final breath = 2 * math.pi * t / 1.8;
    final rMine = unit * radii.mine * (1 + 0.02 * math.sin(breath));
    final rTheirs =
        unit * radii.theirs * (1 + 0.02 * math.sin(breath + math.pi));

    _paintAura(canvas, center, unit, closeness);
    _paintRings(canvas, center, rMine, rTheirs);
    _paintCore(canvas, center, rMine, rTheirs, closeness, t);
    _paintBursts(canvas, center, unit, size, t);
    _paintSignals(canvas, center, rMine, rTheirs, unit, t);
  }

  /// 두 반지름을 목표치로 **공유 시정수(1초)를 따라** 옮긴다.
  ///
  /// 케이던스는 걸음마다 튀는 값이라 그대로 그리면 원이 덜덜 떨린다.
  /// 소리·상태어와 같은 속도로 움직여야 화면과 귀가 한 몸으로 느껴진다
  void _advanceRadii(double t, double closeness) {
    final dt = radii.lastPaintAt == 0
        ? 0.016
        : (t - radii.lastPaintAt).clamp(0.0, 0.25);
    radii.lastPaintAt = t;
    final tau = kSharedSmoothingTimeConstant.inMicroseconds /
        Duration.microsecondsPerSecond;
    final alpha = 1 - math.exp(-dt / tau);

    final (targetMine, targetTheirs) = CadenceRadius.targets(
      myCadence: myCadence?.call(),
      partnerCadence: partnerCadence?.call(),
      hasCloseness: engine.hasCloseness,
      closeness: closeness,
    );
    radii.mine += (targetMine - radii.mine) * alpha;
    radii.theirs += (targetTheirs - radii.theirs) * alpha;
  }

  /// 가까워질수록 두 사람 사이에 도는 옅은 금빛
  void _paintAura(Canvas canvas, Offset center, double unit, double closeness) {
    if (closeness <= 0.2) return;
    final radius = unit * 2.0;
    final strength = ((closeness - 0.2) / 0.8).clamp(0.0, 1.0);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(colors: [
          resonanceColor.withValues(alpha: 0.10 * strength),
          resonanceColor.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  /// 나(self)와 상대(partner)의 테두리. 색 배정은 절대 섞지 않는다.
  /// 면은 같은 색을 옅게 깐 것(5%→20%), 테두리는 65%
  void _paintRings(Canvas canvas, Offset center, double rMine, double rTheirs) {
    void ring(double r, Color color) {
      final rect = Rect.fromCircle(center: center, radius: r);
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = RadialGradient(colors: [
            color.withValues(alpha: 0.05),
            color.withValues(alpha: 0.20),
          ]).createShader(rect),
      );
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = color.withValues(alpha: 0.65),
      );
    }

    // 큰 것부터 그려야 작은 원의 테두리가 위로 온다
    if (rMine >= rTheirs) {
      ring(rMine, selfColor);
      ring(rTheirs, partnerColor);
    } else {
      ring(rTheirs, partnerColor);
      ring(rMine, selfColor);
    }
  }

  /// 두 원이 겹치는 속(= 작은 원)에 드는 공명색.
  ///
  /// 동심원이라 겹침은 늘 작은 원 전체다. 반지름이 같아질수록 그 면적이
  /// 커지므로, **발이 맞을수록 금빛이 넓어진다**가 저절로 성립한다
  void _paintCore(Canvas canvas, Offset center, double rMine, double rTheirs,
      double closeness, double t) {
    var gold = ((closeness - 0.45) / 0.45).clamp(0.0, 1.0);
    // 진입 순간에는 속이 한 번 밝아진다 — 링만 퍼지면 사건이 가장자리에서만
    // 일어나고 정작 두 사람이 만나는 자리는 조용하다
    final burst = _burstProgress(t);
    if (burst != null) gold = math.min(1.0, gold + 0.5 * math.exp(-4 * burst));
    if (gold <= 0) return;

    var r = math.min(rMine, rTheirs);
    if (isBreathing()) {
      // 공명을 오래 유지할 때만 도는 아주 느린 숨 — 눈에 띄면 실패다
      r *= 1 + 0.02 * math.sin(2 * math.pi * t / 3);
    }
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = RadialGradient(colors: [
          resonanceColor.withValues(alpha: 0.55 * gold),
          resonanceColor.withValues(alpha: 0.12 * gold),
        ]).createShader(Rect.fromCircle(center: center, radius: r)),
    );
  }

  double? _burstProgress(double t) {
    for (final start in bursts) {
      final p = (t - start) / _kBurstDuration;
      if (p >= 0 && p <= 1) return p;
    }
    return null;
  }

  /// 공명 진입 링 — 중심에서 한 번 퍼지고 지수적으로 사라진다.
  /// 세 겹으로 시차를 두는 이유: 한 겹은 종이색 배경 위에서 그냥 스쳐
  /// 지나갈 뿐 "사건"으로 안 읽힌다(실기 확인 후 보강)
  void _paintBursts(
      Canvas canvas, Offset center, double unit, Size size, double t) {
    final maxR = math.min(size.width, size.height) / 2 * 0.98;
    for (final start in bursts) {
      final age = (t - start) / _kBurstDuration;
      if (age < 0 || age > 1) continue;
      for (final (delay, weight) in const [
        (0.0, 1.0),
        (0.12, .6),
        (0.24, .35)
      ]) {
        final p = (age - delay) / (1 - delay);
        if (p < 0 || p > 1) continue;
        final alpha =
            (math.exp(-2.0 * p) * (1 - p) * 1.5 * weight).clamp(0.0, 1.0);
        canvas.drawCircle(
          center,
          unit * 0.8 + (maxR - unit * 0.8) * Curves.easeOutCubic.transform(p),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.2 * (1 - 0.7 * p)
            ..color = resonanceColor.withValues(alpha: alpha),
        );
      }
    }
  }

  /// 신호 — 보낸 것은 바깥으로 빠져나가고, 받은 것은 상대 원이 맥동한다.
  /// 글자는 붙지 않는다. 방향과 박자가 곧 뜻이다
  void _paintSignals(Canvas canvas, Offset center, double rMine, double rTheirs,
      double unit, double t) {
    for (final s in signals) {
      final p = (t - s.start) / s.duration;
      if (p < 0 || p > 1) continue;
      if (s.fromPartner) {
        _paintReceived(canvas, center, rTheirs, s.kind, p);
      } else {
        _paintSent(canvas, center, rMine, unit, p);
      }
    }
  }

  /// 보낸 신호 — 내 원에서 시작해 바깥으로 흘러 나간다.
  /// 종류를 구분해 그리지 않는 이유: 보낸 사람은 방금 무슨 제스처를 했는지
  /// 이미 안다. 여기서 확인할 것은 "갔다"뿐이다
  void _paintSent(
      Canvas canvas, Offset center, double rMine, double unit, double p) {
    final eased = Curves.easeOutCubic.transform(p);
    final r = rMine + (unit * 1.5 - rMine) * eased;
    final fade = (1 - p) * (p < 0.15 ? p / 0.15 : 1);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0 * (1 - 0.5 * p)
        ..color = selfColor.withValues(alpha: 0.6 * fade),
    );
  }

  /// 받은 신호 — 상대 원(partner)이 종류마다 다른 박자로 맥동한다
  void _paintReceived(
      Canvas canvas, Offset center, double rTheirs, SignalKind kind, double p) {
    switch (kind) {
      // "여기 있어" — 한 번 툭
      case SignalKind.here:
        _pulse(canvas, center, rTheirs * (1 + 0.16 * p), (1 - p) * 0.75, 3.0);
      // "힘내" — 물결 두 번
      case SignalKind.cheer:
        for (final delay in const [0.0, 0.35]) {
          final q = (p - delay) / (1 - delay);
          if (q < 0 || q > 1) continue;
          _pulse(canvas, center, rTheirs * (1 + 0.20 * q), (1 - q) * 0.7, 2.6);
        }
      // "천천히 가자" — 느리고 크게 한 번. 급할 것 없다는 말이라
      // 애니메이션도 급하지 않다
      case SignalKind.slow:
        final eased = Curves.easeOutQuart.transform(p);
        _pulse(
            canvas, center, rTheirs * (1 + 0.38 * eased), (1 - p) * 0.6, 3.4);
        canvas.drawCircle(
          center,
          rTheirs,
          Paint()..color = partnerColor.withValues(alpha: 0.18 * (1 - p)),
        );
    }
  }

  void _pulse(
      Canvas canvas, Offset center, double radius, double alpha, double width) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = partnerColor.withValues(alpha: alpha.clamp(0.0, 1.0)),
    );
  }

  // 다시 그리기는 frame 노티파이어가 몰아서 시킨다. 위젯이 다시 만들어지는
  // 경우(화면 회전 등)에만 여기로 오므로 그때는 그냥 다시 그린다
  @override
  bool shouldRepaint(covariant _ResonancePainter old) => true;
}
