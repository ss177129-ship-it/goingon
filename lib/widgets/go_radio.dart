import 'package:flutter/material.dart';

import '../theme.dart';
import 'pressable.dart';

/// 하나만 고르는 목록. 원 22 흰 면 — 미선택은 line 1.5, 선택은 ink 2 +
/// 중앙 점 10. 색이 아니라 **점의 유무**로 말하므로 여러 개가 나란히
/// 있어도 어느 것이 골라졌는지 한눈에 읽힌다.
///
/// 항목은 `(값, 라벨)` 쌍. 탭 영역은 행 전체(최소 44), 항목 사이 14.
class GoRadioGroup<T> extends StatelessWidget {
  const GoRadioGroup({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<(T, String)> options;
  final T? value;
  final ValueChanged<T> onChanged;

  static const _size = 22.0;
  static const _dot = 10.0;
  static const _gap = 14.0;
  static const minHeight = 44.0;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < options.length; i++) {
      final (v, label) = options[i];
      if (i > 0) rows.add(const SizedBox(height: _gap));
      rows.add(_GoRadioRow(
        selected: v == value,
        label: label,
        onTap: () => onChanged(v),
      ));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }
}

class _GoRadioRow extends StatelessWidget {
  const _GoRadioRow({
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final VoidCallback onTap;

  Widget _circle(bool pressed) => AnimatedContainer(
      duration: pressed ? Duration.zero : GoMotion.select,
      curve: GoMotion.curve,
      width: GoRadioGroup._size,
      height: GoRadioGroup._size,
      decoration: BoxDecoration(
        // 눌려 있는 동안 원이 가라앉는다 (GoCheckbox와 같은 반응)
        color: pressed ? GoColors.surfacePressed : GoColors.surface,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? GoColors.ink : GoColors.line,
          width: selected ? GoStroke.accent : GoStroke.card,
        ),
      ),
      child: Center(
        child: AnimatedContainer(
          duration: GoMotion.select,
          curve: GoMotion.curve,
          width: selected ? GoRadioGroup._dot : 0,
          height: selected ? GoRadioGroup._dot : 0,
          decoration: const BoxDecoration(
            color: GoColors.ink,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      child: Pressable(
        scale: 1,
        onTap: onTap,
        builder: (context, pressed, child) => ConstrainedBox(
          constraints:
              const BoxConstraints(minHeight: GoRadioGroup.minHeight),
          child: Row(children: [
            _circle(pressed),
            const SizedBox(width: GoSpace.m),
            Expanded(child: child),
          ]),
        ),
        child: Text(label, style: GoText.body),
      ),
    );
  }
}
