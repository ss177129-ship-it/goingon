import 'package:flutter/material.dart';

import '../theme.dart';
import 'pressable.dart';

/// 칩 셋. 전부 틴트 없이 — 흰 면에 테두리, 글자는 테두리와 같은 색.
/// 12px 미만 글자는 없다.
///
/// - [GoSelectChip]: 필터·목표 선택. 선택되면 ink 면 + paper 글자
/// - [GoStoryChip]: 순간 행의 스토리 라벨("첫 런", "새 기록"). limeDark 2px
/// - [GoStatusTag]: 시트 상단의 상태 한 마디("함께 달리기 요청"). *Dark 2px,
///   자간 1.2 — 시트에 하나만
class GoSelectChip extends StatelessWidget {
  const GoSelectChip({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  static const height = 32.0;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: onTap != null,
      child: Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: GoMotion.select,
          curve: GoMotion.curve,
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? GoColors.ink : GoColors.surface,
            borderRadius: BorderRadius.circular(GoRadius.sm),
            border: Border.all(
              color: selected ? GoColors.ink : GoColors.line,
              width: GoStroke.card,
            ),
          ),
          child: AnimatedDefaultTextStyle(
            duration: GoMotion.select,
            curve: GoMotion.curve,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? GoColors.paper : GoColors.ink,
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}

/// 순간 행의 스토리 라벨. 흰 면, limeDark 2px, 12/600 limeDark
class GoStoryChip extends StatelessWidget {
  const GoStoryChip(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: GoColors.surface,
        borderRadius: BorderRadius.circular(GoRadius.sm),
        border: Border.all(color: GoColors.limeDark, width: GoStroke.accent),
      ),
      child: Text(label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: GoColors.limeDark,
          )),
    );
  }
}

/// 시트 상단의 상태 태그. [color]는 *Dark 계열만(글자로도 쓰이므로)
class GoStatusTag extends StatelessWidget {
  const GoStatusTag(this.label, {super.key, this.color = GoColors.coralDark});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: GoColors.surface,
        borderRadius: BorderRadius.circular(GoRadius.sm),
        border: Border.all(color: color, width: GoStroke.accent),
        boxShadow: GoShadow.card,
      ),
      child: Text(label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
            color: color,
          )),
    );
  }
}
