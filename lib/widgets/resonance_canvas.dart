import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../services/resonance.dart';
import '../theme.dart';

/// 두 개의 고리 — 이 앱이 "함께 달린다"를 보여주는 유일한 그림.
///
/// ## 왜 합치지 않고 둘로 두는가 (2026-09-11 재설계)
///
/// 전에는 두 원이 같은 중심에서 반지름만 다른 동심원이었고, 발이 맞으면
/// 하나가 되는 그림이었다. 아름다웠지만 한 가지를 못 했다 — **"저 원이 나다"**.
/// 합쳐진 하나에는 내 것이라고 부를 부분이 없다.
///
/// 소유는 세 가지에서 생긴다:
/// 1. **분리** — 내 선과 네 선이 눈에 따로 있어야 한다
/// 2. **대응** — 내가 한 일이 0.3초 안에 화면에 나타나야 한다. 그래서
///    [kSelfSmoothing]과 [kPartnerSmoothing]이 다르다. 상대는 어차피
///    네트워크를 건너오느라 느리니, 그 차이를 숨기지 말고 소유감의 재료로 쓴다
/// 3. **사건** — 값이 아니라 발구름 하나하나가 보여야 한다. 테두리가
///    케이던스로 물결친다
///
/// 겹침은 별도의 선이 아니라 **두 고리가 만나는 각도에 앉는 금빛**이다.
/// 그래서 전부 아니면 전무가 아니라 부분 공명이 보인다.
///
/// ## 반지름은 여전히 케이던스가 정한다
///
/// 속도가 같아도 보폭이 다르면 발은 안 맞는다. 발이 맞으면 두 고리가
/// 같은 자리로 와서 포개진다 — 이 앱의 원래 명제 그대로다.
///
/// 규칙 하나로 적으면: **연속값은 매 프레임, 순간은 이벤트로, 반복 사건은 위상으로.**
/// 반지름·색은 값을 따라 부드럽게 움직이고, 공명 진입 같은 순간은 이벤트를
/// 받아 한 번 터지며, 발구름은 케이던스에서 뽑은 위상이 매 프레임 그린다.
/// **위상은 절대 스무딩하지 않는다** — 스무딩하면 물결이 죽는다.
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
    this.selfColor,
    this.partnerColor,
    this.resonanceColor,
    this.haloColor,
  });

  final ResonanceEngine engine;

  /// 지금 내 발구름(spm). 없으면 null — 시뮬레이터·권한 거부·데모
  final double? Function()? myCadence;

  /// 지금 상대 발구름(spm). 낡은 값은 호출부가 이미 걸러서 null로 준다
  final double? Function()? partnerCadence;

  /// 어둠 위에서 쓸 색. null이면 [GoRoles]의 밝은 바탕용 색을 쓴다.
  ///
  /// theme.dart가 `selfOnDark`(원색 라임)·`partnerOnDark`(원색 코랄)를 만들어
  /// 두고 "ink·canvas 위에서만 쓰는 원색"이라 적어 뒀다 — 러닝 화면이 잉크로
  /// 내려앉는 순간이 그 색을 쓰라고 비워둔 자리다
  final Color? selfColor;
  final Color? partnerColor;

  /// 어둠 위의 금빛. null이면 [GoRoles.resonance]
  final Color? resonanceColor;

  /// 고리 선과 금빛 점 뒤에 까는 옅은 어둠. null이면 깔지 않는다 —
  /// 밝은 종이 위에서는 필요 없고, 흐르는 배경 위에서만 쓴다
  final Color? haloColor;

  @override
  State<ResonanceCanvas> createState() => _ResonanceCanvasState();
}

/// 내 고리의 시정수. **0.3초를 넘기면 소유감이 끊긴다** —
/// 내가 한 일이 화면에 나타나기까지 그보다 오래 걸리면 사람은 그것을
/// 자기 것으로 느끼지 않는다
const kSelfSmoothing = Duration(milliseconds: 150);

/// 상대 고리의 시정수. 어차피 3초마다 오는 값이라 부드럽게 따라와야 한다.
/// 소리·상태어와 같은 속도([kSharedSmoothingTimeConstant])를 쓴다
const kPartnerSmoothing = kSharedSmoothingTimeConstant;

/// 테두리 물결의 마루 개수. 7은 얕고 잦은 물결이 되는 수 —
/// 적으면 덩어리로 보이고 많으면 톱니로 보인다
const _kLobes = 7;

/// 물결의 깊이(반지름 대비). 0.06이면 반지름 140px에서 ±8px 정도로,
/// 곁눈으로 "떨고 있다"가 읽히되 형태는 안 무너진다
const _kWaveDepth = 0.06;

/// 발구름 한 번의 숨 깊이. 1.0이면 마루와 골이 뒤집혀 3Hz로 깜빡이는데,
/// 물리적으로는 맞지만 화면에서는 깜빡임으로 읽힌다. 봉우리를 뒤집지 않고
/// 숨만 쉬게 한다
const _kBeatDepth = 0.42;

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
        // 버스트와 같은 이유다 — 옛 시각으로 남은 신호는 p가 음수라 영영
        // 그려지지도 지워지지도 않는다
        _signals.clear();
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
          selfColor: widget.selfColor ?? roles.self,
          partnerColor: widget.partnerColor ?? roles.partner,
          resonanceColor: widget.resonanceColor ?? roles.resonance,
          haloColor: widget.haloColor,
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

  /// 발구름 → 반지름 비율.
  ///
  /// **NaN은 clamp를 통과한다** — `num.clamp`는 부등호로 구현돼 있고 NaN과의
  /// 비교는 전부 false라 `NaN.clamp(0,1)`은 NaN이다. 그 값이 반지름에 한 번
  /// 섞이면 지수 평활의 누산기가 영영 NaN으로 남아, 케이던스가 정상으로
  /// 돌아와도 고리가 다시 그려지지 않는다. 그래서 입구에서 막는다
  static double forCadence(double spm) {
    if (!spm.isFinite) return radiusNominal;
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
    if (myCadence != null &&
        partnerCadence != null &&
        myCadence.isFinite &&
        partnerCadence.isFinite) {
      return (forCadence(myCadence), forCadence(partnerCadence));
    }
    if (hasCloseness && closeness.isFinite) {
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

  /// 물결의 깊이. 케이던스를 모르면 0으로 수렴해 매끄러운 원이 된다 —
  /// **멈추면 죽어야 한다.** 원은 멈춰도 원이라서 이 처리가 특히 중요하다
  double waveMine = 0;
  double waveTheirs = 0;

  /// 누적된 물결 위상(라디안).
  ///
  /// **`omega * t`로 쓰면 안 된다.** t는 티커가 시작한 뒤의 경과 초라
  /// 20분이면 1200쯤 된다. 그 지점에서 케이던스가 0.1 spm만 움직여도
  /// 위상이 12라디안 건너뛴다 — 물결이 매 프레임 순간이동한다.
  /// 배경의 `_scroll`과 같은 이유로, 시간이 아니라 **각을 누적한다**
  double phaseMine = 0;
  double phaseTheirs = 0;

  double lastPaintAt = 0;

  /// 고리 두 개와 아우라의 셰이더 캐시.
  ///
  /// `RadialGradient(...).createShader(...)`는 매번 네이티브 그라디언트를
  /// 새로 만든다. 초당 180개면 30분 러닝에서 그대로 배터리다 — 배경의
  /// 하늘 셰이더를 캐시한 것과 같은 이유다.
  ///
  /// 반지름은 매 프레임 조금씩 움직이므로 **2pt로 양자화해서 키를 만든다.**
  /// 0.04 → 0.16짜리 옅은 면이라 2pt 차이는 눈에 보이지 않는다
  final shaders = _ShaderCache();
}

class _ShaderCache {
  final _keys =
      <int, ({double r, int argb, double cx, double cy, double extra})>{};
  final _shaders = <int, ui.Shader>{};

  /// [extra]는 반지름·색 말고 그라디언트를 바꾸는 값(투명도 세기 등).
  /// 호출부에서 미리 계단으로 끊어서 넘긴다
  ui.Shader get(int slot, Offset center, double radius, Color color,
      List<Color> Function() colors,
      {double extra = 0}) {
    // 반지름을 2pt로 양자화한다. 이게 없으면 반지름이 매 프레임 미세하게
    // 움직이는 탓에 캐시가 한 번도 맞지 않는다
    final q = (radius / 2).roundToDouble() * 2;
    final k = _keys[slot];
    final hit = k != null &&
        k.r == q &&
        k.argb == color.toARGB32() &&
        k.cx == center.dx &&
        k.cy == center.dy &&
        k.extra == extra;
    if (!hit || _shaders[slot] == null) {
      _keys[slot] = (
        r: q,
        argb: color.toARGB32(),
        cx: center.dx,
        cy: center.dy,
        extra: extra
      );
      _shaders[slot] = RadialGradient(colors: colors())
          .createShader(Rect.fromCircle(center: center, radius: q));
    }
    return _shaders[slot]!;
  }
}

/// 재생 중인 신호 하나.
///
/// 보낸 신호와 받은 신호는 **방향이 반대**다. 보낸 것은 중심에서 바깥으로
/// 빠져나가고(내가 보냈다), 받은 것은 상대 원 위에서 맥동한다(상대가 왔다).
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
    this.haloColor,
  }) : super(repaint: frame);

  final ValueListenable<double> frame;
  final ResonanceEngine engine;

  final Color selfColor;
  final Color partnerColor;
  final Color resonanceColor;

  /// 선·점 뒤의 옅은 어둠. null이면 그리지 않는다
  final Color? haloColor;
  final List<double> bursts;
  final List<_SignalAnim> signals;
  final bool Function() isBreathing;
  final double? Function()? myCadence;
  final double? Function()? partnerCadence;
  final _RadiiState radii;

  /// 센서가 헛것을 본 값(NaN·무한대)은 0으로 — 없는 것과 같이 다룬다
  static double _finite(double? v) =>
      (v == null || !v.isFinite) ? 0 : v;

  @override
  void paint(Canvas canvas, Size size) {
    final t = frame.value;
    final closeness = engine.smoothedCloseness;

    final unit = math.min(size.width, size.height) * 0.42;
    if (unit <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);

    final mine = myCadence?.call();
    final theirs = partnerCadence?.call();

    // 케이던스에서 각속도를 뽑는다. **스무딩하지 않는다** — 반지름만 부드럽게
    // 따라가고 위상은 raw다. 여기에 시정수를 걸면 물결이 통째로 사라진다.
    // 부호가 나와 상대에서 반대라, 두 물결은 서로를 향해 돈다
    final wMine = -2 * math.pi * (_finite(mine) / 60);
    final wTheirs = 2 * math.pi * (_finite(theirs) / 60);

    _advance(t, closeness, mine, theirs, wMine, wTheirs);
    final phMine = radii.phaseMine;
    final phTheirs = radii.phaseTheirs;

    var rMine = unit * radii.mine;
    var rTheirs = unit * radii.theirs;
    if (isBreathing()) {
      // 공명을 오래 유지할 때만 도는 아주 느린 숨 — 눈에 띄면 실패다
      final breath = 1 + 0.02 * math.sin(2 * math.pi * t / 3);
      rMine *= breath;
      rTheirs *= breath;
    }

    _paintAura(canvas, center, unit, closeness);
    _paintRing(canvas, center, rTheirs, radii.waveTheirs * unit, _kLobes,
        phTheirs, partnerColor, 2.4, .72, 0);
    _paintRing(canvas, center, rMine, radii.waveMine * unit, _kLobes, phMine,
        selfColor, 3.4, 1.0, 1);
    _paintMeetings(canvas, center, rMine, rTheirs, radii.waveMine * unit,
        radii.waveTheirs * unit, phMine, phTheirs, t);
    _paintBursts(canvas, center, unit, size, t);
    _paintSignals(canvas, center, rMine, rTheirs, unit, t);
  }

  /// 반지름과 물결 깊이를 목표치로 옮긴다.
  ///
  /// **시정수가 나와 상대에게 다르다.** 내 것은 150ms, 상대 것은 1초 —
  /// 이 비대칭이 "이게 내 것"이라는 감각을 만든다. 같은 속도로 움직이면
  /// 두 고리는 그냥 두 개의 도형이지 나와 너가 아니다.
  void _advance(double t, double closeness, double? mine, double? theirs,
      double wMine, double wTheirs) {
    final dt = radii.lastPaintAt == 0
        ? 0.016
        : (t - radii.lastPaintAt).clamp(0.0, 0.25);
    radii.lastPaintAt = t;

    // 각을 누적한다. 2π로 접어두지 않으면 몇 시간 뒤 정밀도가 떨어진다
    const tau = 2 * math.pi;
    radii.phaseMine = (radii.phaseMine + wMine * dt) % tau;
    radii.phaseTheirs = (radii.phaseTheirs + wTheirs * dt) % tau;

    double alphaFor(Duration tau) =>
        1 - math.exp(-dt / (tau.inMicroseconds / Duration.microsecondsPerSecond));
    final aSelf = alphaFor(kSelfSmoothing);
    final aPartner = alphaFor(kPartnerSmoothing);

    final (targetMine, targetTheirs) = CadenceRadius.targets(
      myCadence: mine,
      partnerCadence: theirs,
      hasCloseness: engine.hasCloseness,
      closeness: closeness,
    );
    radii.mine += (targetMine - radii.mine) * aSelf;
    radii.theirs += (targetTheirs - radii.theirs) * aPartner;

    // 케이던스를 모르면 물결이 잦아들어 매끄러운 원만 남는다
    final depthMine = (mine != null && mine.isFinite) ? _kWaveDepth : 0.0;
    final depthTheirs = (theirs != null && theirs.isFinite) ? _kWaveDepth : 0.0;
    radii.waveMine += (depthMine - radii.waveMine) * aSelf;
    radii.waveTheirs += (depthTheirs - radii.waveTheirs) * aPartner;
  }

  /// 발구름으로 물결치는 고리 하나.
  ///
  /// r(θ) = R + A·env(t)·cos(nθ − ωt)
  ///
  /// env는 봉우리를 뒤집지 않고 숨만 쉬게 한다([_kBeatDepth] 주석 참고).
  /// 각속도의 부호가 나와 상대에서 반대라, 두 물결은 서로를 향해 돈다
  void _paintRing(Canvas canvas, Offset center, double radius, double amp,
      int lobes, double phase, Color color, double width, double alpha,
      int slot) {
    if (radius <= 0) return;
    final env = (1 - _kBeatDepth) + _kBeatDepth * math.cos(phase);
    final path = _wavePath(center, radius, amp * env, lobes, phase);

    // 면은 같은 색을 아주 옅게 — 고리 안쪽이 비면 화면에 구멍이 뚫린 것처럼 보인다.
    // 셰이더는 반지름을 2pt로 끊어 캐시한다 (slot 0=상대, 1=나, 2=아우라)
    canvas.drawPath(
      path,
      _fillPaint
        ..shader = radii.shaders.get(
            slot,
            center,
            radius,
            color,
            () => [
                  color.withValues(alpha: 0.04 * alpha),
                  color.withValues(alpha: 0.16 * alpha),
                ]),
    );
    // 노을 하늘은 고리의 원색과 같은 밝기라 선이 배경에 녹는다. 색은 그대로
    // 두고 선 뒤에 옅은 어둠을 한 겹 깔아 떼어낸다
    final halo = haloColor;
    if (halo != null) {
      canvas.drawPath(
        path,
        _haloPaint
          ..strokeWidth = width + 3
          ..color = halo.withValues(alpha: halo.a * alpha),
      );
    }
    canvas.drawPath(
      path,
      _strokePaint
        ..strokeWidth = width
        ..color = color.withValues(alpha: 0.82 * alpha),
    );
  }

  /// 그리기마다 새로 만들지 않는 Paint 셋. `drawPath`는 호출 시점에
  /// Paint를 디스플레이 리스트로 복사하므로 재사용해도 안전하다
  static final _fillPaint = Paint();
  static final _strokePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round;
  static final _auraPaint = Paint();
  static final _haloPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round;

  /// 닫힌 Catmull-Rom 곡선. 꺾은선으로 그리면 반지름이 커질수록 각이 보인다 —
  /// 72점이면 이음매 없이 매끄럽고, 점을 늘리는 것보다 싸다
  Path _wavePath(
      Offset center, double radius, double amp, int lobes, double phase) {
    const n = 72;
    final pts = List<Offset>.generate(n, (i) {
      final th = (i / n) * 2 * math.pi;
      final r = radius + amp * math.cos(lobes * th - phase);
      return Offset(center.dx + math.cos(th) * r, center.dy + math.sin(th) * r);
    });
    Offset at(int i) => pts[(i % n + n) % n];
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (var i = 0; i < n; i++) {
      final p0 = at(i - 1), p1 = at(i), p2 = at(i + 1), p3 = at(i + 2);
      path.cubicTo(
        p1.dx + (p2.dx - p0.dx) / 6,
        p1.dy + (p2.dy - p0.dy) / 6,
        p2.dx - (p3.dx - p1.dx) / 6,
        p2.dy - (p3.dy - p1.dy) / 6,
        p2.dx,
        p2.dy,
      );
    }
    return path..close();
  }

  /// 두 고리가 만나는 각도에만 금빛이 앉는다.
  ///
  /// 옛 화면은 작은 원 전체를 금빛으로 채웠다 — 공명이 전부 아니면 전무였다.
  /// 여기서는 각도마다 두 곡선의 거리를 재서 가까운 자리에만 점을 놓으므로
  /// **부분 공명**이 보인다. "지금 이쪽에서 우리가 만났다"가 그려진다
  void _paintMeetings(
      Canvas canvas,
      Offset center,
      double rMine,
      double rTheirs,
      double ampMine,
      double ampTheirs,
      double phMine,
      double phTheirs,
      double t) {
    if (!engine.hasCloseness && ampTheirs <= 0.01) return;
    final envM = (1 - _kBeatDepth) + _kBeatDepth * math.cos(phMine);
    final envT = (1 - _kBeatDepth) + _kBeatDepth * math.cos(phTheirs);

    // 만남으로 볼 거리. 너무 좁으면 영영 안 만나고, 넓으면 늘 만난 것처럼 보인다
    final tolerance = math.max(6.0, (rMine + rTheirs) * 0.035);
    const samples = 108;
    final burst = _burstProgress(t);
    final boost = burst == null ? 0.0 : 0.45 * math.exp(-4 * burst);

    // Paint는 루프 밖에서 하나만 만든다 — 108번 새로 만들면 초당 6천 개다
    final dot = Paint();
    final haloDot = Paint();
    final halo = haloColor;

    for (var i = 0; i < samples; i++) {
      final th = (i / samples) * 2 * math.pi;
      final a = rMine + ampMine * envM * math.cos(_kLobes * th - phMine);
      final b =
          rTheirs + ampTheirs * envT * math.cos(_kLobes * th - phTheirs);
      final gap = (a - b).abs();
      if (gap > tolerance) continue;
      final near = 1 - gap / tolerance;
      final strength = (near * near * 0.72 + boost).clamp(0.0, 1.0);
      if (strength < 0.04) continue;
      final r = (a + b) / 2;
      final pos =
          Offset(center.dx + math.cos(th) * r, center.dy + math.sin(th) * r);
      final dotR = 1.2 + 2.8 * strength;
      // 금빛은 노을 주황과 거의 같은 색이라 뒤에 어둠이 없으면 묻힌다
      if (halo != null) {
        haloDot.color = halo.withValues(alpha: halo.a * strength);
        canvas.drawCircle(pos, dotR + 1.5, haloDot);
      }
      dot.color = resonanceColor.withValues(alpha: strength);
      canvas.drawCircle(pos, dotR, dot);
    }
  }

  /// 가까워질수록 두 사람 사이에 도는 옅은 금빛
  void _paintAura(Canvas canvas, Offset center, double unit, double closeness) {
    if (closeness <= 0.2) return;
    final radius = unit * 2.0;
    final strength = ((closeness - 0.2) / 0.8).clamp(0.0, 1.0);
    // 세기는 0.05 단위로 끊는다 — 캐시가 맞아야 캐시다
    final step = (strength * 20).round() / 20;
    canvas.drawCircle(
      center,
      radius,
      _auraPaint
        ..shader = radii.shaders.get(
            2,
            center,
            radius,
            resonanceColor,
            () => [
                  resonanceColor.withValues(alpha: 0.10 * step),
                  resonanceColor.withValues(alpha: 0),
                ],
            extra: step),
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

  /// 신호 — 보낸 것은 바깥으로 빠져나가고, 받은 것은 상대 고리가 맥동한다.
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

  /// 보낸 신호 — 내 고리에서 시작해 바깥으로 흘러 나간다.
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

  /// 받은 신호 — 상대 고리가 종류마다 다른 박자로 맥동한다
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
