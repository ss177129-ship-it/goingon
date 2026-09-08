// GoingOn 브랜드 모션 — 심볼(두 링 + 바 + 미소 아크)이 스스로 그려지고,
// 워드마크를 손글씨로 쓰며 두 o가 바닥에서 튀어오르는 애니메이션.
//
// 확정 스펙 (총 2.7s) — 자세한 타임라인은 SplashTimeline 참고.
//   0.00  링 드로잉 (코랄 CW / 라임 CCW, 교차점에서 출발, 선 굵기 40→60)
//   0.55  바 1, 0.68 바 2 확장
//   0.88  미소 아크 드로잉
//   1.28  심볼 정착 바운스
//   1.30  손글씨(G·i·n·g·'·n) + 두 o 점프 시작 (글자 시간 ×0.8)
//   2.70  완성
//
// 이 위젯은 Scaffold를 갖지 않는다 — SplashGate._splash() 안에 그대로
// 얹어서 쓴다. 인트로가 끝나면 [onIntroComplete]가 한 번 불리고, 이후에도
// 화면이 남아 있으면(아직 로딩 중) **두 링만 서로를 돌며** "기다리는 중"을
// 말한다. 인트로를 처음부터 다시 틀지 않는다 — 두 번 보면 로고가 아니라
// 로딩 바로 읽힌다(2026-09-08). 끄려면 spinWhileWaiting:false.
//
// 색은 전부 GoColors를 통해서만 얻는다(theme.dart 규칙). 원본 아이콘
// 파일(goingon_symbol.svg)의 링 색은 FF6A55 / D6F24E였는데, 앱 팔레트의
// coral(F05840)·lime(C5E040)과 달라서 여기서는 GoColors 값으로 맞췄다.
// 아이콘 전용 색을 그대로 쓰고 싶다면 GoColors에 새 토큰을 추가해서
// 참조할 것(이 파일에 직접 Color(0x…)를 넣지 않는다).

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_drawing/path_drawing.dart';

import '../../theme.dart';
import 'goingon_splash_paths.dart';

class GoingOnBrandMotion extends StatefulWidget {
  const GoingOnBrandMotion({
    super.key,
    this.symbolSize = 150,
    this.wordmarkWidth = 132,
    this.spacing = 22,
    this.onIntroComplete,
    this.spinWhileWaiting = true,
  });

  final double symbolSize;
  final double wordmarkWidth;
  final double spacing;

  /// 인트로(2.7s)가 끝나는 순간 한 번 호출.
  final VoidCallback? onIntroComplete;

  /// 인트로 후 두 링이 공통 중심을 도는 루프로 "대기 중"을 표시할지.
  /// 바·미소·워드마크는 완성된 채 그대로다 — 움직이는 것은 링뿐이다
  final bool spinWhileWaiting;

  /// 링 하나가 비워졌다 채워지는 시간. 두 링이 번갈아 하므로 한 주기는 두 배
  static const spinPeriod = Duration(milliseconds: 1400);

  @override
  State<GoingOnBrandMotion> createState() => _GoingOnBrandMotionState();
}

class _GoingOnBrandMotionState extends State<GoingOnBrandMotion>
    with TickerProviderStateMixin {
  late final AnimationController _intro;
  AnimationController? _spin;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(vsync: this, duration: SplashTimeline.total)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          widget.onIntroComplete?.call();
          if (widget.spinWhileWaiting && mounted && !_reduceMotion) {
            _spin = AnimationController(
              vsync: this,
              duration: GoingOnBrandMotion.spinPeriod * 2, // 코랄 → 라임
            )..repeat();
            setState(() {});
          }
        }
      });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.of(context).disableAnimations;
    if (_reduceMotion) {
      _intro.value = 1;
    } else if (!_intro.isAnimating && _intro.value == 0) {
      _intro.forward();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _spin?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listenable = _spin == null
        ? _intro as Listenable
        : Listenable.merge([_intro, _spin!]);
    return AnimatedBuilder(
      animation: listenable,
      builder: (context, _) {
        final spinTurns = _spin?.value ?? 0;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: widget.symbolSize,
              height: widget.symbolSize,
              child: CustomPaint(
                painter: _SymbolPainter(
                    _intro.value * SplashTimeline.totalMs,
                    spinTurns: spinTurns),
              ),
            ),
            SizedBox(height: widget.spacing),
            SizedBox(
              width: widget.wordmarkWidth,
              height: widget.wordmarkWidth * 110 / 400,
              child: CustomPaint(
                painter:
                    _WordmarkPainter(_intro.value * SplashTimeline.totalMs),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Timeline — the only place timings live. All values in milliseconds.
// ---------------------------------------------------------------------------

class SplashTimeline {
  SplashTimeline._();

  static const int totalMs = 2700;
  static const Duration total = Duration(milliseconds: totalMs);

  // Symbol
  static const ringStart = 0, ringDur = 700, limeLag = 40;
  static const bar1Start = 550, bar2Start = 680, barDur = 320;
  static const arcStart = 880, arcDur = 420;
  static const settleStart = 1280, settleDur = 320;

  // Wordmark. k scales handwriting speed — 0.8 is the confirmed final value.
  static const double k = 0.8;
  static const int wordStart = 1300;
  static const int oJumpDur = 580;

  /// Glyph slots: relative start (ms, before k) and write duration (ms, before k).
  /// Word order: G o i n g ' o n
  static const List<GlyphSlot> slots = [
    GlyphSlot('G', rel: 0, dur: 260),
    GlyphSlot('o1', rel: 240, dur: 0), // jump
    GlyphSlot('i', rel: 300, dur: 130),
    GlyphSlot('n1', rel: 430, dur: 190),
    GlyphSlot('g', rel: 620, dur: 340),
    GlyphSlot('apos', rel: 960, dur: 90),
    GlyphSlot('o2', rel: 1030, dur: 0), // jump
    GlyphSlot('n2', rel: 1120, dur: 190),
  ];

  static int startOf(GlyphSlot s) => wordStart + (s.rel * k).round();
  static int durOf(GlyphSlot s) => (s.dur * k).round();
}

class GlyphSlot {
  const GlyphSlot(this.id, {required this.rel, required this.dur});
  final String id;
  final int rel;
  final int dur;
}

// ---------------------------------------------------------------------------
// Curves
// ---------------------------------------------------------------------------

const _ringEase = Cubic(.2, .9, .3, 1);
const _barEase = Cubic(.22, 1, .36, 1);
const _arcEase = Cubic(.65, 0, .35, 1);
const _writeEase = Cubic(.45, .05, .55, .95);
const _riseEase = Cubic(.2, .8, .4, 1); // decelerate to apex
const _fallEase = Cubic(.5, 0, .9, .6); // accelerate down

double _seg(double t, int start, int dur, [Curve curve = Curves.linear]) {
  if (dur <= 0) return t >= start ? 1 : 0;
  final p = ((t - start) / dur).clamp(0.0, 1.0);
  return curve.transform(p);
}

// ---------------------------------------------------------------------------
// Symbol painter — viewBox 200 70 620 850
// ---------------------------------------------------------------------------

class _SymbolPainter extends CustomPainter {
  _SymbolPainter(this.t, {this.spinTurns = 0});
  final double t;

  /// 대기 루프 — 두 링이 공통 중심을 도는 회전(바퀴 단위, 0~1)
  final double spinTurns;

  static const _coralRect =
      Rect.fromLTWH(598 - 120, 290 - 120, 240, 240); // center 598,290 r120
  static const _limeRect =
      Rect.fromLTWH(431 - 115, 291 - 115, 230, 230); // center 431,291 r115

  /// 코랄이 라임 위로 올라오는 교차 구간 — 사슬처럼 엮인 것으로 읽히게
  static const _crossClip = Rect.fromLTWH(450, 305, 125, 135);

  /// 대기 루프 — 두 링이 **번갈아 비워졌다 채워진다.** 링은 제자리에 있고
  /// 반투명·잔상은 없다(2026-09-08 요청). 차례가 된 링은 시작점(왼쪽)에서
  /// 시계 방향으로 풀려 나가다가(꼬리가 앞으로) 완전히 비워지는 순간 같은
  /// 방향으로 다시 차오른다(머리가 앞으로).
  ///
  /// 풀림과 채움을 **하나의 가속 곡선**으로 묶는다 — 온전한 링에서 천천히
  /// 출발해 비워지는 순간이 가장 빠르고, 다시 온전해지며 천천히 멈춘다.
  /// 그래서 빈 순간은 한 프레임도 안 되게 지나가고, 풀림→채움 경계에서
  /// 멈칫하지 않는다(따로 easing하면 경계에서 속도가 0이 돼 버벅인다)
  static const _spinCurve = Cubic(.7, 0, .3, 1);

  void _paintSpinningRings(Canvas canvas) {
    // 0~.5 코랄 차례, .5~1 라임 차례
    final coralP = spinTurns < .5 ? spinTurns * 2 : 0.0;
    final limeP = spinTurns >= .5 ? (spinTurns - .5) * 2 : 0.0;

    Paint stroke(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 60;

    /// 진행도 p(0~1)의 링. q = ease(p)×2: 0~1 풀림(꼬리 전진), 1~2 채움(머리 전진)
    void ring(Rect rect, Color c, double p) {
      if (p <= 0 || p >= 1) {
        canvas.drawArc(rect, math.pi, 2 * math.pi, false, stroke(c));
        return;
      }
      final q = _spinCurve.transform(p) * 2;
      final double start, sweep;
      if (q < 1) {
        start = math.pi + q * 2 * math.pi;
        sweep = (1 - q) * 2 * math.pi;
      } else {
        start = math.pi;
        sweep = (q - 1) * 2 * math.pi;
      }
      if (sweep > 0) canvas.drawArc(rect, start, sweep, false, stroke(c));
    }

    ring(_coralRect, GoColors.coral, coralP);
    ring(_limeRect, GoColors.lime, limeP);
    // 교차 구간은 코랄이 위 — 사슬처럼 엮인 모양 유지
    canvas.save();
    canvas.clipRect(_crossClip);
    ring(_coralRect, GoColors.coral, coralP);
    canvas.restore();
  }

  static const _vbX = 200.0, _vbY = 70.0, _vbW = 620.0, _vbH = 850.0;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width / _vbW, size.height / _vbH);
    canvas.save();
    canvas.translate(
      (size.width - _vbW * scale) / 2,
      (size.height - _vbH * scale) / 2,
    );
    canvas.scale(scale);
    canvas.translate(-_vbX, -_vbY);

    final settle = _seg(t, SplashTimeline.settleStart, SplashTimeline.settleDur);
    final bounce = 1 + 0.045 * math.sin(settle * math.pi);
    const center = Offset(511.5, 514.75);
    canvas.translate(center.dx, center.dy);
    canvas.scale(bounce);
    canvas.translate(-center.dx, -center.dy);

    if (spinTurns == 0) {
      _paintRings(canvas);
    } else {
      _paintSpinningRings(canvas);
    }
    _paintBars(canvas);
    _paintArc(canvas);
    canvas.restore();
  }

  void _paintRings(Canvas canvas) {
    final pCoral = _seg(t, SplashTimeline.ringStart, SplashTimeline.ringDur, _ringEase);
    final pLime = _seg(t, SplashTimeline.ringStart + SplashTimeline.limeLag,
        SplashTimeline.ringDur, _ringEase);

    Paint ring(Color c, double p) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = ui.lerpDouble(40, 60, p)!;

    final coralRect = Rect.fromCircle(center: const Offset(598, 290), radius: 120);
    final limeRect = Rect.fromCircle(center: const Offset(431, 291), radius: 115);

    if (pCoral > 0) {
      canvas.drawArc(coralRect, math.pi, 2 * math.pi * pCoral, false,
          ring(GoColors.coral, pCoral));
    }
    if (pLime > 0) {
      canvas.drawArc(limeRect, 0, -2 * math.pi * pLime, false,
          ring(GoColors.lime, pLime));
    }
    if (pCoral > 0) {
      canvas.save();
      canvas.clipRect(const Rect.fromLTWH(450, 305, 125, 135));
      canvas.drawArc(coralRect, math.pi, 2 * math.pi * pCoral, false,
          ring(GoColors.coral, pCoral));
      canvas.restore();
    }
  }

  void _paintBars(Canvas canvas) {
    void bar(RRect r, int start) {
      final p = _seg(t, start, SplashTimeline.barDur, _barEase);
      if (p <= 0) return;
      final sx = p < .7 ? 1.06 * (p / .7) : ui.lerpDouble(1.06, 1.0, (p - .7) / .3)!;
      final c = r.center;
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.scale(sx, 1);
      canvas.translate(-c.dx, -c.dy);
      canvas.drawRRect(r, Paint()..color = GoColors.ink);
      canvas.restore();
    }

    bar(RRect.fromLTRBR(322, 456, 702, 514, const Radius.circular(29)), SplashTimeline.bar1Start);
    bar(RRect.fromLTRBR(322, 530, 702, 590, const Radius.circular(30)), SplashTimeline.bar2Start);
  }

  void _paintArc(Canvas canvas) {
    final p = _seg(t, SplashTimeline.arcStart, SplashTimeline.arcDur, _arcEase);
    if (p <= 0) return;
    final rect = Rect.fromCircle(center: const Offset(511.5, 620), radius: 240);
    canvas.drawArc(
      rect,
      math.pi,
      -math.pi * p,
      false,
      Paint()
        ..color = GoColors.ink
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 59,
    );
  }

  @override
  bool shouldRepaint(_SymbolPainter old) =>
      old.t != t || old.spinTurns != spinTurns;
}

// ---------------------------------------------------------------------------
// Wordmark painter — viewBox 55 55 400 110
// ---------------------------------------------------------------------------

class _WordmarkPainter extends CustomPainter {
  _WordmarkPainter(this.t);
  final double t;

  static const _vbX = 55.0, _vbY = 55.0, _vbW = 400.0;

  static final Map<String, Path> _glyph = {
    for (final e in GoingOnPaths.glyphs.entries) e.key: parseSvgPathData(e.value),
  };
  static final Map<String, Path> _stroke = {
    for (final e in GoingOnPaths.strokes.entries) e.key: parseSvgPathData(e.value),
  };
  static final Map<String, double> _strokeLen = {
    for (final e in _stroke.entries)
      e.key: e.value.computeMetrics().fold(0.0, (a, m) => a + m.length),
  };

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / _vbW;
    canvas.save();
    canvas.scale(scale);
    canvas.translate(-_vbX, -_vbY);

    for (final slot in SplashTimeline.slots) {
      final start = SplashTimeline.startOf(slot);
      if (slot.id == 'o1' || slot.id == 'o2') {
        _paintO(canvas, slot.id, start);
      } else {
        _paintWritten(canvas, slot.id, start, SplashTimeline.durOf(slot));
      }
    }
    canvas.restore();
  }

  void _paintWritten(Canvas canvas, String id, int start, int dur) {
    final p = _seg(t, start, dur, _writeEase);
    if (p <= 0) return;
    final glyph = _glyph[id]!;

    if (p >= 1) {
      canvas.drawPath(glyph, Paint()..color = GoColors.ink);
      return;
    }

    final target = _strokeLen[id]! * p;
    final partial = Path();
    var acc = 0.0;
    for (final m in _stroke[id]!.computeMetrics()) {
      if (acc >= target) break;
      final take = math.min(m.length, target - acc);
      partial.addPath(m.extractPath(0, take), Offset.zero);
      acc += m.length;
    }

    // 글자 모양으로 클립한 뒤 손글씨 중심선을 굵게 칠해 드러낸다.
    // (saveLayer + srcIn 마스크는 Impeller에서 쓰는 중인 글자 가장자리에
    // 흰 테두리가 비쳐서 클립 방식으로 바꿈 — 2026-09-08 시뮬레이터 확인)
    canvas.save();
    canvas.clipPath(glyph);
    final ink = Paint()..color = GoColors.ink;
    canvas.drawPath(
      partial,
      ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = GoingOnPaths.strokeWidth[id]!
        ..strokeCap = StrokeCap.butt
        ..strokeJoin = StrokeJoin.round,
    );
    if (id == 'i' && p >= .9) {
      canvas.drawCircle(
          const Offset(203.3, 70.8), 7.6, Paint()..color = GoColors.ink);
    }
    canvas.restore();
  }

  /// "통": squashed on the baseline → springs up stretched → lands with a
  /// squash → one small hop → rest.
  void _paintO(Canvas canvas, String id, int start) {
    final p = _seg(t, start, SplashTimeline.oJumpDur);
    if (p <= 0) return;

    const kf = <_OKey>[
      _OKey(0.00, 24, 1.20, 0.80, _riseEase),
      _OKey(0.38, -48, 0.90, 1.12, _fallEase),
      _OKey(0.60, 0, 1.18, 0.84, _riseEase),
      _OKey(0.76, -15, 0.97, 1.04, _fallEase),
      _OKey(0.88, 0, 1.05, 0.96, Curves.easeOut),
      _OKey(1.00, 0, 1.00, 1.00, Curves.linear),
    ];
    var i = 0;
    while (i < kf.length - 2 && p >= kf[i + 1].t) {
      i++;
    }
    final a = kf[i], b = kf[i + 1];
    final u = a.curve.transform(((p - a.t) / (b.t - a.t)).clamp(0.0, 1.0));
    final dy = ui.lerpDouble(a.dy, b.dy, u)!;
    final sx = ui.lerpDouble(a.sx, b.sx, u)!;
    final sy = ui.lerpDouble(a.sy, b.sy, u)!;
    final opacity = (p / .08).clamp(0.0, 1.0);

    final glyph = _glyph[id]!;
    final origin = GoingOnPaths.oOrigin[id]!;
    final color = id == 'o1' ? GoColors.lime : GoColors.coral;

    canvas.save();
    canvas.translate(origin.dx, origin.dy + dy);
    canvas.scale(sx, sy);
    canvas.translate(-origin.dx, -origin.dy);
    canvas.drawPath(glyph, Paint()..color = color.withValues(alpha: opacity));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WordmarkPainter old) => old.t != t;
}

class _OKey {
  const _OKey(this.t, this.dy, this.sx, this.sy, this.curve);
  final double t, dy, sx, sy;
  final Curve curve;
}
