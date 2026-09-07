import 'package:flutter/material.dart';

import '../theme.dart';

/// 브랜드 마크 — 나(self) · 상대(partner) 두 원이 나란히 겹치는 로고.
/// login/nickname/스플래시/완료 카드에서 크기와 강조 색만 다르게 반복 쓰임.
///
/// 색을 안 넘기면(팩토리들) build에서 [GoRoles]의 self/partner로 채운다 —
/// 팩토리에는 context가 없어서 여기서 미룬다. [fillAlpha]는 그때 면의 투명도
class BrandMark extends StatelessWidget {
  final double width;
  final double height;
  final double circleSize;
  final double leftDx;
  final double rightDx;
  final double topDy;
  final Color? leftFill;
  final Color? leftBorder;
  final Color? rightFill;
  final Color? rightBorder;

  /// 색을 안 넘겼을 때 면(self/partner)의 알파 — (왼쪽, 오른쪽)
  final (double, double) fillAlpha;
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
    this.leftFill,
    this.leftBorder,
    this.rightFill,
    this.rightBorder,
    this.fillAlpha = (.4, .35),
    this.borderWidth = 2,
    this.leftScale = 1,
    this.rightScale = 1,
  });

  /// login/nickname 화면의 기본 크기 (74×46, 원 40)
  factory BrandMark.standard() => const BrandMark(
        width: 74, height: 46, circleSize: 40,
        leftDx: 3, rightDx: 3, topDy: 4,
      );

  /// finish 공유 카드의 축소 버전 — 면을 더 옅게(0.15 / 0.25)
  factory BrandMark.compact() => const BrandMark(
        width: 66, height: 42, circleSize: 38,
        leftDx: 2, rightDx: 2, topDy: 2,
        fillAlpha: (.15, .25),
      );

  /// 스플래시의 숨쉬는 버전 — 좌우 확대율을 매 프레임 갱신해서 넘겨줌
  factory BrandMark.pulsing({
    required double leftScale,
    required double rightScale,
  }) =>
      BrandMark(
        width: 88, height: 54, circleSize: 50,
        leftDx: 4, rightDx: 4, topDy: 2,
        leftScale: leftScale,
        rightScale: rightScale,
      );

  @override
  Widget build(BuildContext context) {
    final roles = GoRoles.of(context);
    final (leftAlpha, rightAlpha) = fillAlpha;
    final lFill = leftFill ?? roles.self.withValues(alpha: leftAlpha);
    final lBorder = leftBorder ?? roles.self;
    final rFill = rightFill ?? roles.partner.withValues(alpha: rightAlpha);
    final rBorder = rightBorder ?? roles.partner;

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
            child: circle(lFill, lBorder, leftScale)),
        Positioned(
            right: rightDx,
            top: topDy,
            child: circle(rFill, rBorder, rightScale)),
      ]),
    );
  }
}
