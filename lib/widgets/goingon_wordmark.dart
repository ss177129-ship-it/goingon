// 브랜드 워드마크 — Going'on 손글씨 로고타입을 원본 path 그대로 그린다.
//
// 글자 데이터는 스플래시 모션과 같은 소스(goingon_splash_paths.dart)를
// 쓴다. 스플래시에서 다 그려진 뒤의 모습과 화면 상단의 로고가 정확히
// 같아야 하므로, 두 곳이 같은 path를 보게 두는 것이 중요하다.
//
// 색: 잉크 글자는 역할 토큰(textPrimary)에서, 두 o는 브랜드 고유색
// (lime/coral)에서 온다. o의 색은 로고의 정체성이라 화면 역할에 따라
// 바뀌지 않는다 — 스플래시 모션도 같은 두 색을 쓴다.

import 'package:flutter/material.dart';
import 'package:path_drawing/path_drawing.dart';

import '../theme.dart';
import 'splash_motion/goingon_splash_paths.dart';

class GoingOnWordmark extends StatelessWidget {
  const GoingOnWordmark({super.key, this.height = 18, this.color});

  /// 글자 전체(위로 튄 i의 점부터 아래로 내려간 g의 꼬리까지)의 높이.
  final double height;

  /// 잉크 글자 색. 안 넘기면 [GoRoles.textPrimary].
  final Color? color;

  /// 글자 전체를 감싸는 원본 좌표계 상자 — 폭/높이 비를 여기서 얻는다.
  static final Rect _bounds = () {
    Rect? r;
    for (final p in _paths.values) {
      final b = p.getBounds();
      r = r == null ? b : r.expandToInclude(b);
    }
    return r!;
  }();

  static final Map<String, Path> _paths = {
    for (final e in GoingOnPaths.glyphs.entries)
      e.key: parseSvgPathData(e.value),
  };

  static double get _aspect => _bounds.width / _bounds.height;

  @override
  Widget build(BuildContext context) {
    final ink = color ?? GoRoles.of(context).textPrimary;
    return Semantics(
      label: 'goingon',
      image: true,
      child: SizedBox(
        width: height * _aspect,
        height: height,
        child: CustomPaint(painter: _WordmarkPainter(ink)),
      ),
    );
  }
}

class _WordmarkPainter extends CustomPainter {
  const _WordmarkPainter(this.ink);

  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final b = GoingOnWordmark._bounds;
    canvas.save();
    canvas.scale(size.height / b.height);
    canvas.translate(-b.left, -b.top);

    for (final e in GoingOnWordmark._paths.entries) {
      final color = switch (e.key) {
        'o1' => GoColors.lime,
        'o2' => GoColors.coral,
        _ => ink,
      };
      canvas.drawPath(e.value, Paint()..color = color);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WordmarkPainter old) => old.ink != ink;
}
