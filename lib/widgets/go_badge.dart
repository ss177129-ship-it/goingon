import 'package:flutter/material.dart';

import '../theme.dart';

/// 배지 셋 — 다른 것 위에 **겹쳐 놓이는** 작은 표식. 밑에 깔린 것과
/// 떨어져 보이도록 전부 2px paper 링을 두른다.
///
/// - [GoCountBadge]: 탭 아이콘 우상단의 수(친구 요청 등). 0이면 없다
/// - [GoLiveDot]: 아바타 우하단의 라임 점 — 지금 달리는 중
/// - [GoLiveTag]: "달리는 중" 한 마디짜리 태그
class GoCountBadge extends StatelessWidget {
  const GoCountBadge({super.key, required this.count, required this.child});

  final int count;

  /// 배지가 얹힐 것(보통 아이콘)
  final Widget child;

  static const _min = 18.0;
  static const _ring = 2.0;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: -2 - _ring,
          right: -6 - _ring,
          child: Semantics(
            label: '$count',
            child: Container(
              constraints: const BoxConstraints(
                  minWidth: _min + _ring * 2, minHeight: _min + _ring * 2),
              padding: const EdgeInsets.symmetric(horizontal: 5 + _ring),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: GoColors.coralDark,
                borderRadius: BorderRadius.circular((_min + _ring * 2) / 2),
                border: Border.all(color: GoColors.paper, width: _ring),
              ),
              child: Text('$count',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1,
                    color: GoColors.paper,
                  )),
            ),
          ),
        ),
      ],
    );
  }
}

/// 아바타 우하단의 라이브 점. 아바타를 [Stack]에 넣고 `Positioned(right: 0,
/// bottom: 0)`으로 올린다
class GoLiveDot extends StatelessWidget {
  const GoLiveDot({super.key});

  static const size = 14.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: GoColors.lime,
        shape: BoxShape.circle,
        border: Border.all(color: GoColors.paper, width: GoStroke.accent),
      ),
    );
  }
}

/// "달리는 중" 태그. 흰 면, limeDark 2px, 점 8 lime + 12/600 limeDark
class GoLiveTag extends StatelessWidget {
  const GoLiveTag({super.key, this.label = '달리는 중'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
      decoration: BoxDecoration(
        color: GoColors.surface,
        borderRadius: BorderRadius.circular(GoRadius.sm),
        border: Border.all(color: GoColors.limeDark, width: GoStroke.accent),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
              color: GoColors.lime, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: GoColors.limeDark,
            )),
      ]),
    );
  }
}
