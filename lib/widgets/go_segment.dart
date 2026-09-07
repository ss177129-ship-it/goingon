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

  static const height = 40.0;
  static const _inset = 3.0;
  static const _gap = 2.0;
  static const _itemRadius = GoRadius.sm - _inset;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (var i = 0; i < labels.length; i++) {
      if (i > 0) items.add(const SizedBox(width: _gap));
      items.add(Expanded(child: _item(i)));
    }
    return Container(
      height: height,
      padding: const EdgeInsets.all(_inset),
      decoration: BoxDecoration(
        color: GoColors.surface,
        borderRadius: BorderRadius.circular(GoRadius.sm),
        border: Border.all(color: GoColors.line, width: GoStroke.card),
      ),
      child: Row(children: items),
    );
  }

  Widget _item(int i) {
    final active = i == index;
    return Semantics(
      selected: active,
      button: true,
      child: Pressable(
        onTap: () => onChanged(i),
        child: AnimatedContainer(
          duration: GoMotion.select,
          curve: GoMotion.curve,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? GoColors.ink : Colors.transparent,
            borderRadius: BorderRadius.circular(_itemRadius),
          ),
          child: AnimatedDefaultTextStyle(
            duration: GoMotion.select,
            curve: GoMotion.curve,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: active ? GoColors.paper : GoColors.mid,
            ),
            child: Text(labels[i]),
          ),
        ),
      ),
    );
  }
}
