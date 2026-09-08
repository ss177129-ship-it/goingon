import 'package:flutter/material.dart';

import '../theme.dart';
import 'pressable.dart';

/// 기간 전환 같은 짧은 선택지의 세그먼트. 흰 면 + line 1.5 컨테이너(radius
/// 12, 안쪽 3) 안에서 활성 항목만 **ink 면 + paper 글자**로 뒤집힌다.
///
/// 항목 radius 9는 12 − 3 — 바깥 모서리와 동심이 되게 하는 기하값이라
/// 토큰이 아니다.
class GoSegment extends StatelessWidget {
  const GoSegment({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  /// 안쪽 항목이 44pt가 되도록 거꾸로 정한 높이 — 44 + 안쪽 여백 3×2 +
  /// 테두리 1.5×2 = 53. 테두리도 자리를 먹는다는 것을 빠뜨리면 3pt가 조용히
  /// 모자란다. 40이던 시절 항목은 34pt였고, 그건 겨냥이 아니라 운이었다
  /// (2026-09-08)
  static const height = 53.0;
  static const _inset = 3.0;
  static const _gap = 2.0;
  static const _itemRadius = GoRadius.sm - _inset;

  @override
  Widget build(BuildContext context) {
    final roles = GoRoles.of(context);
    final items = <Widget>[];
    for (var i = 0; i < labels.length; i++) {
      if (i > 0) items.add(const SizedBox(width: _gap));
      items.add(Expanded(child: _item(roles, i)));
    }
    return Container(
      height: height,
      padding: const EdgeInsets.all(_inset),
      decoration: BoxDecoration(
        color: roles.surface,
        borderRadius: BorderRadius.circular(GoRadius.sm),
        border: Border.all(color: roles.line, width: GoStroke.card),
      ),
      // 항목이 통 높이를 꽉 채우게 늘린다 — 기본값(center)이면 항목이 글자
      // 높이만큼만 자라 표적이 41pt에 머문다(2026-09-08)
      child:
          Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: items),
    );
  }

  Widget _item(GoRoles roles, int i) {
    final active = i == index;
    return Semantics(
      selected: active,
      button: true,
      child: Pressable(
        onTap: () => onChanged(i),
        // 활성 항목은 잉크가 가라앉고, 비활성은 잉크 8%가 잠깐 깔린다
        builder: (context, pressed, child) => AnimatedContainer(
          duration: pressed ? Duration.zero : GoMotion.select,
          curve: GoMotion.curve,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active
                ? (pressed ? roles.dark.pressed : roles.dark.bg)
                : (pressed ? roles.pressOverlay : Colors.transparent),
            borderRadius: BorderRadius.circular(_itemRadius),
          ),
          child: child,
        ),
        child: AnimatedDefaultTextStyle(
          duration: GoMotion.select,
          curve: GoMotion.curve,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: active ? roles.dark.fg : roles.textSecondary,
          ),
          child: Text(labels[i]),
        ),
      ),
    );
  }
}
