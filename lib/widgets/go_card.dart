import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../theme.dart';
import 'pressable.dart';

/// 화면 위의 독립된 객체 하나.
///
/// 배경은 [GoRoles.surface](따뜻한 흰 면), 라운드 [GoRadius.md],
/// **기본 테두리 없음.** 경계를 만드는 것은 선이 아니라 [GoShadow.card]다 —
/// 페이퍼와 면의 명도 차이는 1.15:1이라 그것만으로는 가장자리가 보이지
/// 않았고, 그래서 카드가 배경에 녹아 "흰 얼룩"처럼 보였다(2026-09-07).
/// [borderColor]에 역할색(self=나, partner=상대, attention=경고)을
/// 주면 그때만 [GoStroke.accent] 테두리가 더해진다.
/// 목록은 카드가 아니라 [GoGroup]으로 — 행마다 카드를 만들지 말 것.
///
/// [onTap]이 있으면 목록 행처럼 눌린다 — **축소 없이** 햅틱 + 눌림 배경 +
/// 그림자 접힘. 버튼(GoButton)의 0.97 축소와 구분해, 행은 "열린다"는 느낌.
class GoCard extends StatefulWidget {
  const GoCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderColor,
    this.padding = const EdgeInsets.all(GoSpace.card),
    this.margin = EdgeInsets.zero,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? borderColor;
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
    final accent = widget.borderColor;
    final roles = GoRoles.of(context);
    final card = AnimatedContainer(
      duration: _down ? Duration.zero : Pressable.releaseDuration,
      curve: Curves.easeOut,
      width: double.infinity, // 카드는 부모 폭을 채운다 — Column 안에서도 줄지 않게
      margin: widget.margin,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: _down ? roles.surfacePressed : roles.surface,
        borderRadius: BorderRadius.circular(GoRadius.md),
        border: accent == null
            ? null
            : Border.all(color: accent, width: GoStroke.accent),
        // 눌리면 그림자가 접히면서 카드가 종이 쪽으로 내려앉는다
        boxShadow: _down ? GoShadow.pressed : GoShadow.card,
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
