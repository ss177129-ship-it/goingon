import 'package:flutter/material.dart';

import '../theme.dart';

/// 브랜드 마크 — 나(lime) · 상대(coral) 두 원이 나란히 겹치는 로고.
/// login/nickname/스플래시/완료 카드에서 크기와 강조 색만 다르게 반복 쓰임.
class BrandMark extends StatelessWidget {
  final double width;
  final double height;
  final double circleSize;
  final double leftDx;
  final double rightDx;
  final double topDy;
  final Color leftFill;
  final Color leftBorder;
  final Color rightFill;
  final Color rightBorder;
  final double borderWidth;
  final double leftScale;
  final double rightScale;

  const BrandMark({
    super.key,
    required this.width,
    required this.height,
    required this.circleSize,
    required this.leftDx,
    required this.rightDx,
    required this.topDy,
    required this.leftFill,
    required this.leftBorder,
    required this.rightFill,
    required this.rightBorder,
    this.borderWidth = 2,
    this.leftScale = 1,
    this.rightScale = 1,
  });

  /// login/nickname 화면의 기본 크기 (74×46, 원 40)
  factory BrandMark.standard() => BrandMark(
        width: 74, height: 46, circleSize: 40,
        leftDx: 3, rightDx: 3, topDy: 4,
        leftFill: GoColors.lime.withOpacity(.4),
        leftBorder: GoColors.limeDark,
        rightFill: GoColors.coral.withOpacity(.35),
        rightBorder: GoColors.coralDark,
      );

  /// finish 공유 카드의 축소 버전 — 라임 배경 위라 왼쪽은 limeDark로 대비를 줌
  factory BrandMark.compact() => BrandMark(
        width: 66, height: 42, circleSize: 38,
        leftDx: 2, rightDx: 2, topDy: 2,
        leftFill: GoColors.limeDark.withOpacity(.15),
        leftBorder: GoColors.limeDark,
        rightFill: GoColors.coral.withOpacity(.25),
        rightBorder: GoColors.coralDark,
      );

  /// 스플래시의 숨쉬는 버전 — 좌우 확대율을 매 프레임 갱신해서 넘겨줌
  factory BrandMark.pulsing({
    required double leftScale,
    required double rightScale,
  }) =>
      BrandMark(
        width: 88, height: 54, circleSize: 50,
        leftDx: 4, rightDx: 4, topDy: 2,
        leftFill: GoColors.lime.withOpacity(.4),
        leftBorder: GoColors.limeDark,
        rightFill: GoColors.coral.withOpacity(.35),
        rightBorder: GoColors.coralDark,
        leftScale: leftScale,
        rightScale: rightScale,
      );

  @override
  Widget build(BuildContext context) {
    Widget circle(Color fill, Color border, double scale) {
      final c = Container(
        width: circleSize,
        height: circleSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: fill,
          border: Border.all(color: border, width: borderWidth),
        ),
      );
      return scale == 1 ? c : Transform.scale(scale: scale, child: c);
    }

    return SizedBox(
      width: width,
      height: height,
      child: Stack(children: [
        Positioned(
            left: leftDx,
            top: topDy,
            child: circle(leftFill, leftBorder, leftScale)),
        Positioned(
            right: rightDx,
            top: topDy,
            child: circle(rightFill, rightBorder, rightScale)),
      ]),
    );
  }
}
