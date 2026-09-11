import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'world_palette.dart';
import 'world_scene.dart';

/// 러닝 중 흐르는 여의도 한강공원.
///
/// ## 왜 배경이 필요한가
///
/// 고리는 리듬을 보여주지만 **전진을 못 보여준다.** 달리기의 절반은 앞으로
/// 나아가는 것인데 화면에는 그것이 없었다. 세계가 흐르면 속도가 숫자가 아니라
/// 몸으로 느껴진다 — `5'02"`보다 도시가 빨리 흐르는 쪽이 훨씬 직관적이다.
///
/// ## 성능이 이 위젯 설계의 전부다
///
/// 층 하나에 픽셀 rect가 수백 개다. 매 프레임 다시 그리면 30분 러닝에서
/// 배터리가 남지 않는다 — `resonance_canvas.dart`가 "배터리 소모는 삭제
/// 사유다"라고 적어둔 그 기준이다.
///
/// 그래서 **층마다 한 주기(390px)를 [ui.Picture]로 한 번 굽고**, 프레임마다
/// `drawPicture`를 두 번(현재 주기 + 이음매) 부른다. 층 일곱 개면 프레임당
/// 그리기 호출이 열넷이다. 그림은 팔레트가 바뀔 때만 다시 굽는다.
///
/// 화면이 꺼지면 티커를 완전히 멈춘다. 배경은 아무도 안 볼 때 가장 비싸다
class RunWorld extends StatefulWidget {
  const RunWorld({
    super.key,
    required this.speed,
    this.time,
    this.enabled = true,
  });

  /// 세계의 속도. 5'30"(330초/km)이 1.0이다.
  ///
  /// 호출부에서 `(330 / 현재페이스).clamp(0.5, 2.0)`로 넘긴다. 상·하한이
  /// 있는 이유: 신호등에 서면 0으로 수렴해 세계가 얼어붙고, GPS가 튀면
  /// 배경이 순간이동한다
  final double speed;

  /// 시간대. null이면 실제 시각으로 고른다
  final WorldTime? time;

  /// 꺼두면 티커가 돌지 않는다 (마무리 화면 전환 중 등)
  final bool enabled;

  @override
  State<RunWorld> createState() => _RunWorldState();
}

/// 층 하나의 배치와 속도.
///
/// `period`는 **속도 1.0에서 한 주기(390px)가 지나가는 데 걸리는 초**다.
/// 멀수록 길다 — 별은 220초, 발밑 트랙은 8.5초. 이 차이가 깊이를 만든다
class _Layer {
  const _Layer(this.top, this.height, this.period, this.paint);
  final double top;
  final double height;
  final double period;
  final void Function(Canvas, WorldPalette, double) paint;
}

const _layers = <_Layer>[
  _Layer(0, 300, 260, paintSkyBits),
  _Layer(252, 150, 170, paintSkyline),
  _Layer(372, 60, 80, paintBridge),
  _Layer(402, 104, 130, paintWater),
  _Layer(400, 34, 100, paintIsland),
  _Layer(486, 96, 27, paintBank),
  _Layer(574, 58, 8.5, paintTrack),
];

/// 해의 자리. 화면 오른쪽 위 — 모든 사물의 오른면이 밝은 것이 여기서 나온다
const double _sunX = 288;
const double _sunY = 318;

/// 트랙의 바닥. 이 선을 화면 높이의 75% 자리에 앉힌다
const double _groundY = 632;

class _RunWorldState extends State<RunWorld>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker;

  /// 다시 그리기 신호. 위젯 트리는 건드리지 않는다
  final _frame = ValueNotifier<int>(0);

  /// 층마다 누적된 이동 거리(design px). **시간이 아니라 거리를 쌓는다** —
  /// 속도가 변하는데 시간으로 그리면 속도를 바꾸는 순간 세계가 순간이동한다
  final _scroll = List<double>.filled(_layers.length, 0);

  /// 부드럽게 따라가는 속도. 배경이 화면의 절반을 차지하므로 여기서 튀면
  /// 화면 전체가 튄 것처럼 보인다
  double _speed = 1;
  double _last = 0;

  WorldPalette _palette = WorldPalette.dusk;
  List<ui.Picture>? _baked;
  ui.Picture? _sunPic;
  ui.Picture? _sunPathPic;

  /// 화면이 꺼져서 멈춘 상태인가.
  ///
  /// 부모는 1초 타이머로 계속 다시 빌드한다 — 백그라운드에서도 30초 넘게.
  /// 이 표시가 없으면 [didUpdateWidget]이 방금 생명주기가 멈춘 티커를
  /// 곧바로 되살려서, 아무도 안 보는 배경이 계속 돈다
  bool _pausedByLifecycle = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _palette = WorldPalette.of(widget.time ?? WorldPalette.timeFor(DateTime.now()));
    _speed = widget.speed.clamp(0.5, 2.0);
    _ticker = createTicker(_onTick);
    if (widget.enabled) _ticker.start();
  }

  @override
  void didUpdateWidget(RunWorld old) {
    super.didUpdateWidget(old);
    final t = widget.time ?? WorldPalette.timeFor(DateTime.now());
    final next = WorldPalette.of(t);
    if (next != _palette) {
      _palette = next;
      _disposeBaked();
    }
    if (widget.enabled && !_ticker.isActive && !_pausedByLifecycle) {
      _last = 0;
      _ticker.start();
    } else if (!widget.enabled && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    final t = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    // 티커를 멈췄다 켜면 경과가 0부터 다시 흐른다. 그 한 프레임에 큰 dt가
    // 들어오면 세계가 통째로 미끄러진다
    final dt = (_last == 0) ? 0.0 : (t - _last).clamp(0.0, 0.1);
    _last = t;

    final target = widget.speed.isFinite ? widget.speed.clamp(0.5, 2.0) : 1.0;
    // 2초 시정수 — 페이스가 바뀌어도 세계는 천천히 따라붙는다
    _speed += (target - _speed) * (1 - math.exp(-dt / 2.0));

    for (var i = 0; i < _layers.length; i++) {
      _scroll[i] = (_scroll[i] + dt * (kTile / _layers[i].period) * _speed) % kTile;
    }
    _frame.value++;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _pausedByLifecycle = false;
      if (widget.enabled && !_ticker.isActive) {
        _last = 0;
        _ticker.start();
      }
    } else {
      _pausedByLifecycle = true;
      if (_ticker.isActive) _ticker.stop();
    }
  }

  void _disposeBaked() {
    for (final p in _baked ?? const <ui.Picture>[]) {
      p.dispose();
    }
    _baked = null;
    _sunPic?.dispose();
    _sunPic = null;
    _sunPathPic?.dispose();
    _sunPathPic = null;
  }

  List<ui.Picture> _bake() {
    if (_baked != null) return _baked!;
    // 해와 물 위의 빛길도 매 프레임 다시 그릴 이유가 없다 — 흐르지 않으므로
    // 한 번 굽고 `drawPicture` 한 번이면 끝난다
    _sunPic = bakeLayer(kTile, _sunY + 60,
        (c) => paintSun(c, _palette, _sunX, _sunY));
    final water = _layers.firstWhere((l) => l.paint == paintWater);
    _sunPathPic = bakeLayer(kTile, water.height,
        (c) => paintSunPath(c, _palette, _sunX, water.height));
    return _baked = [
      for (final l in _layers)
        bakeLayer(kTile, l.height, (c) => l.paint(c, _palette, l.height)),
    ];
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _frame.dispose();
    _disposeBaked();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baked = _bake();
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _WorldPainter(
          repaint: _frame,
          palette: _palette,
          pictures: baked,
          sun: _sunPic!,
          sunPath: _sunPathPic!,
          scroll: _scroll,
        ),
      ),
    );
  }
}

class _WorldPainter extends CustomPainter {
  _WorldPainter({
    required Listenable repaint,
    required this.palette,
    required this.pictures,
    required this.sun,
    required this.sunPath,
    required this.scroll,
  }) : super(repaint: repaint);

  final WorldPalette palette;
  final List<ui.Picture> pictures;
  final ui.Picture sun;
  final ui.Picture sunPath;
  final List<double> scroll;

  /// 하늘 그라디언트의 셰이더는 크기가 안 바뀌면 그대로 쓴다 —
  /// 매 프레임 `createShader`를 부르면 프레임마다 셰이더를 새로 컴파일한다
  Size? _skySize;
  Paint? _skyPaint;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // 하늘은 위젯 좌표로 칠한다 — 세계가 어디에 앉든 배경은 화면을 꽉 채워야 한다
    if (_skySize != size || _skyPaint == null) {
      _skySize = size;
      _skyPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.skyTop, palette.skyMid, palette.skyLow],
          stops: const [0, .46, 1],
        ).createShader(Offset.zero & size);
    }
    canvas.drawRect(Offset.zero & size, _skyPaint!);

    final s = size.width / kTile;
    // 트랙 바닥을 화면 높이의 75%에 앉힌다. 위가 잘리면 하늘이 잘리는 것이고,
    // 남으면 하늘이 넓어지는 것이다 — 둘 다 장면을 해치지 않는다
    final dy = size.height * .75 - _groundY * s;

    canvas.save();
    canvas.translate(0, dy);
    canvas.scale(s);

    // 해가 먼저다. 나중에 그리면 스카이라인 **앞에** 떠서, 해가 건물 위에
    // 붙은 스티커처럼 보인다 — 해는 도시 뒤로 진다
    canvas.drawPicture(sun);

    for (var i = 0; i < _layers.length; i++) {
      final l = _layers[i];
      // 화면 밖의 층은 건너뛴다 — 작은 기기에서 위쪽 층이 통째로 잘린다
      final topOnScreen = dy + l.top * s;
      if (topOnScreen > size.height || topOnScreen + l.height * s < 0) continue;

      // 스크롤을 **기기 픽셀 격자**에 맞춘다. 390이 아닌 기기에서 s가
      // 소수라, 맞추지 않으면 이음매에 머리카락 굵기의 틈이 매 프레임
      // 다른 자리에 생겨 화면 전체가 기어다니는 것처럼 보인다
      final sc = (scroll[i] * s).roundToDouble() / s;

      canvas.save();
      canvas.translate(0, l.top);
      canvas.clipRect(Rect.fromLTWH(0, 0, kTile, l.height));
      canvas.translate(-sc, 0);
      canvas.drawPicture(pictures[i]);
      canvas.translate(kTile, 0);
      canvas.drawPicture(pictures[i]);
      canvas.restore();

      // 물 위의 빛길은 흐르지 않는다 — 해가 붙박여 있으므로 반영도 제자리다
      if (l.paint == paintWater) {
        canvas.save();
        canvas.translate(0, l.top);
        canvas.clipRect(Rect.fromLTWH(0, 0, kTile, l.height));
        canvas.drawPicture(sunPath);
        canvas.restore();
      }
    }

    // 트랙 아래 — 화면 바닥까지. 여기는 HUD의 큰 숫자가 앉는 자리라
    // 무늬를 두지 않는다
    canvas.restore();
    final groundOnScreen = dy + _groundY * s;
    if (groundOnScreen < size.height) {
      canvas.drawRect(
        Rect.fromLTWH(0, groundOnScreen, size.width, size.height - groundOnScreen),
        Paint()..color = palette.skyLow.withValues(alpha: palette.night ? .3 : .45),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WorldPainter old) {
    // 셰이더 캐시는 페인터가 새로 만들어져도 살아남아야 한다 —
    // 부모가 1초마다 다시 빌드하므로 매번 버리면 캐시가 아니다.
    // 팔레트가 바뀌었으면 물려받지 않는다 — 노을 하늘이 밤에 남는다
    if (old.palette == palette) {
      _skySize = old._skySize;
      _skyPaint = old._skyPaint;
    }
    return old.palette != palette || !identical(old.pictures, pictures);
  }
}
