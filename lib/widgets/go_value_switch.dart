import 'package:flutter/material.dart';

import '../theme.dart';

/// 값이 바뀌었을 때만 짧게 반응하는 자리.
///
/// 새 값은 아래에서 살짝 떠오르며 밝아지고, 옛 값은 같은 자리에서 가라앉으며
/// 사라진다([GoMotion.update]). 같은 값이 다시 그려지는 것은 그냥 지나간다 —
/// 반응하는 것은 **바뀜**이지 다시 그림이 아니다.
///
/// 왜 필요한가: 숫자가 뚝 바뀌면 사용자는 "내가 잘못 봤나" 하고 다시 읽는다.
/// 200ms의 교차는 "방금 갱신됐다"를 눈에 알려서 그 의심을 없앤다. 러닝 중
/// 매초 바뀌는 시간·거리처럼 **계속 바뀌는 값에는 쓰지 않는다** — 늘
/// 움직이면 아무것도 말하지 않는 것과 같다.
///
/// [value]가 곧 키다. 문자열이든 숫자든 `==`가 되는 것이면 된다.
class GoValueSwitch extends StatelessWidget {
  const GoValueSwitch({
    super.key,
    required this.value,
    required this.child,
    this.alignment = Alignment.center,
  });

  final Object? value;
  final Widget child;

  /// 옛 값과 새 값이 겹치는 동안의 정렬. 왼쪽 정렬 문단이면 [Alignment.centerLeft]
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return AnimatedSwitcher(
      duration: reduce ? Duration.zero : GoMotion.update,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, .25), end: Offset.zero)
              .animate(anim),
          child: child,
        ),
      ),
      layoutBuilder: (current, previous) => Stack(
        alignment: alignment,
        children: [...previous, if (current != null) current],
      ),
      child: KeyedSubtree(key: ValueKey(value), child: child),
    );
  }
}
