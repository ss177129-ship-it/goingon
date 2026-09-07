import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../theme.dart';

/// 화면 위의 독립된 객체 하나.
///
/// 배경은 언제나 흰색, 라운드 [GoRadius.md], 테두리 [GoStroke.card].
/// **색은 테두리와 아이콘에만** 준다 — 배경 틴트 없음(theme.dart 규칙).
/// [borderColor]는 역할색(limeDark=나, coralDark=상대, amberDark=경고)이거나
/// 기본 [GoColors.line]. 역할색이면 굵기가 [GoStroke.accent]로 올라간다.
///
/// [onTap]이 있으면 목록 행처럼 눌린다 — **축소 없이** 햅틱 + 눌림 배경
/// 잉크 6%. 버튼(GoButton)의 0.97 축소와 구분해, 행은 "열린다"는 느낌.
class GoCard extends StatefulWidget {
  const GoCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderColor = GoColors.line,
    this.padding = const EdgeInsets.all(GoSpace.card),
    this.margin = EdgeInsets.zero,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color borderColor;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  @override
  State<GoCard> createState() => _GoCardState();
}

class _GoCardState extends State<GoCard> {
  bool _down = false;

  bool get _pressable => widget.onTap != null || widget.onLongPress != null;

  void _set(bool down) {
    if (!_pressable || _down == down) return;
    if (down) HapticFeedback.selectionClick();
    setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.borderColor != GoColors.line;
    final card = Container(
      width: double.infinity, // 카드는 부모 폭을 채운다 — Column 안에서도 줄지 않게
      margin: widget.margin,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: _down ? Color.lerp(Colors.white, GoColors.ink, .06) : Colors.white,
        borderRadius: BorderRadius.circular(GoRadius.md),
        border: Border.all(
            color: widget.borderColor,
            width: accent ? GoStroke.accent : GoStroke.card),
      ),
      child: widget.child,
    );
    if (!_pressable) return card;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: card,
    );
  }
}
