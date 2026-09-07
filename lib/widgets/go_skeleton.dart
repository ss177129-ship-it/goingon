import 'package:flutter/material.dart';

import '../theme.dart';

/// 목록의 **최초 로딩**에만 쓰는 자리 표시 행. 이 앱의 원칙은 "마지막
/// 데이터가 있으면 그것을 들고 있는다"이므로, 이미 한 번 받은 목록이 새로
/// 고쳐질 때는 쓰지 않는다 — 있던 내용이 회색 막대로 바뀌면 깜빡임이다.
///
/// 애니메이션은 없다. 반짝이는 스켈레톤은 "기다리게 하고 있다"를 강조하는
/// 효과인데, 여기서는 그저 자리를 잡아 두는 것으로 충분하다.
///
/// 색은 ink 8%(첫 줄·원·오른쪽 블록), 두 번째 막대만 6%.
class GoSkeletonRow extends StatelessWidget {
  const GoSkeletonRow({super.key});

  Widget _bar(double widthFactor, double height, Color color) =>
      FractionallySizedBox(
        widthFactor: widthFactor,
        alignment: Alignment.centerLeft,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(height / 2),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final roles = GoRoles.of(context);
    final strong = roles.textPrimary.withValues(alpha: .08);
    final weak = roles.textPrimary.withValues(alpha: .06);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: GoSpace.m),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: roles.line, width: GoStroke.rule),
        ),
      ),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: strong, shape: BoxShape.circle),
        ),
        const SizedBox(width: GoSpace.m),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _bar(.30, 12, strong),
              const SizedBox(height: GoSpace.s),
              _bar(.55, 10, weak),
            ],
          ),
        ),
        const SizedBox(width: GoSpace.m),
        Container(
          width: 64,
          height: 44,
          decoration: BoxDecoration(
            color: strong,
            borderRadius: BorderRadius.circular(GoRadius.sm),
          ),
        ),
      ]),
    );
  }
}
