import 'package:flutter/material.dart';

import '../theme.dart';
import 'pressable.dart';

/// 칩 셋. 12px 미만 글자는 없다.
///
/// - [GoSelectChip]: 필터·목표 선택. 선택되면 dark 면 + dark 글자
/// - [GoStoryChip]: 순간 행의 스토리 라벨("첫 런", "새 기록"). statusOnline
///   칩 — 틴트 면 + 앵커색 글자, 테두리 없음
/// - [GoStatusTag]: 시트 상단의 상태 한 마디("함께 달리기 요청"). 기본
///   statusRunning 칩, 자간 1.2 — 시트에 하나만
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
    final roles = GoRoles.of(context);
    return Semantics(
      selected: selected,
      button: onTap != null,
      child: Pressable(
        onTap: onTap,
        builder: (context, pressed, child) => AnimatedContainer(
          duration: pressed ? Duration.zero : GoMotion.select,
          curve: GoMotion.curve,
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? (pressed ? roles.dark.pressed : roles.dark.bg)
                : (pressed ? roles.surfacePressed : roles.surface),
            borderRadius: BorderRadius.circular(GoRadius.sm),
            border: Border.all(
              color: selected ? roles.dark.bg : roles.line,
              width: GoStroke.card,
            ),
          ),
          child: child,
        ),
        // 선택은 면 색만이 아니라 체크로도 말한다 (Color Usage Rules §5)
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (selected) ...[
            Icon(Icons.check, size: 14, color: roles.dark.fg),
            const SizedBox(width: 4),
          ],
          AnimatedDefaultTextStyle(
            duration: GoMotion.select,
            curve: GoMotion.curve,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? roles.dark.fg : roles.textPrimary,
            ),
            child: Text(label),
          ),
        ]),
      ),
    );
  }
}

/// 순간 행의 스토리 라벨. statusOnline 칩 — pineTint 면, 12/600 pine
class GoStoryChip extends StatelessWidget {
  const GoStoryChip(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final role = GoRoles.of(context).statusOnline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: role.bg,
        borderRadius: BorderRadius.circular(GoRadius.sm),
      ),
      child: Text(label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: role.fg,
          )),
    );
  }
}

/// 시트 상단의 상태 태그. [role]은 상태 칩 역할([GoRoles.statusRunning] /
/// [GoRoles.statusOnline])만 — null이면 statusRunning
class GoStatusTag extends StatelessWidget {
  const GoStatusTag(this.label, {super.key, this.role});

  final String label;
  final GoRole? role;

  @override
  Widget build(BuildContext context) {
    final r = role ?? GoRoles.of(context).statusRunning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: r.bg,
        borderRadius: BorderRadius.circular(GoRadius.sm),
        boxShadow: GoShadow.card,
      ),
      child: Text(label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
            color: r.fg,
          )),
    );
  }
}
