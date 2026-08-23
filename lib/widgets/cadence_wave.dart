import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// 케이던스 곡선. 그날의 리듬이 어떻게 흘렀는지를 한 줄로 보여준다.
///
/// **값이 없는 초(모름)에서는 선을 끊는다.** 이어 그리면 없는 사실을 그리는
/// 셈이고, 이 앱에서 리듬은 꾸며도 되는 값이 아니다.
class CadenceWave extends StatelessWidget {
  const CadenceWave(
    this.spm, {
    super.key,
    this.color = GoColors.limeDark,
    this.strokeWidth = 1.6,
  });

  /// 1초 해상도의 spm. null은 '모름'
  final List<double?> spm;
  final Color color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _WavePainter(spm, color, strokeWidth),
        size: Size.infinite,
      );
}

class _WavePainter extends CustomPainter {
  const _WavePainter(this.spm, this.color, this.strokeWidth);

  final List<double?> spm;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final known = spm.whereType<double>();
    if (known.length < 2) return;
    final lo = known.reduce(math.min), hi = known.reduce(math.max);
    // 흔들림이 거의 없는 러닝에서 스팬이 0에 가까우면 미세한 잡음이
    // 화면 전체 높이로 증폭된다. 최소 폭을 둬서 평평한 것은 평평하게 보이게
    final span = (hi - lo) < 6 ? 6.0 : hi - lo;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    final path = Path();
    var drawing = false;
    for (var i = 0; i < spm.length; i++) {
      final v = spm[i];
      if (v == null) {
        drawing = false;
        continue;
      }
      final x = size.width * (i / (spm.length - 1));
      final y = size.height * (1 - ((v - lo) / span).clamp(0.0, 1.0));
      if (drawing) {
        path.lineTo(x, y);
      } else {
        path.moveTo(x, y);
        drawing = true;
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.spm != spm || old.color != color || old.strokeWidth != strokeWidth;
}
