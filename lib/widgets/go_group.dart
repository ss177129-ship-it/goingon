import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../theme.dart';

/// iOS 설정 앱의 그룹 목록. 그룹 하나가 둥근 면 하나이고, 안의 행은
/// **왼쪽을 들여쓴 헤어라인**으로만 나뉜다. 행마다 카드를 만들지 않는다 —
/// 흰 조각이 많아질수록 화면이 지저분해진다.
///
/// 테두리는 없다. 그룹의 경계는 [GoShadow.card]가, 행 사이는
/// [GoColors.lineStrong]이 만든다 — 구분선이 안 보이면 행이 몇 개인지,
/// 어디까지가 한 행인지 읽히지 않는다(2026-09-07).
class GoGroup extends StatelessWidget {
  const GoGroup({
    super.key,
    required this.rows,
    this.margin = const EdgeInsets.symmetric(horizontal: GoSpace.screen),
    this.dividerInset = GoSpace.card,
  });

  final List<GoGroupRow> rows;
  final EdgeInsetsGeometry margin;

  /// 행 구분선의 왼쪽 들여쓰기. 아이콘이 있으면 아이콘 너비만큼 더 준다
  final double dividerInset;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) {
        children.add(Padding(
          padding: EdgeInsets.only(left: dividerInset),
          child: Container(height: GoStroke.rule, color: GoColors.lineStrong),
        ));
      }
      children.add(rows[i]);
    }
    return Container(
      width: double.infinity,
      margin: margin,
      decoration: BoxDecoration(
        color: GoColors.surface,
        borderRadius: BorderRadius.circular(GoRadius.md),
        boxShadow: GoShadow.card,
      ),
      // 그림자는 바깥에, 잘라내기는 안쪽에 — 한 Container에서 둘을 같이
      // 하면 clip이 그림자까지 잘라 없앤다
      child: ClipRRect(
        borderRadius: BorderRadius.circular(GoRadius.md),
        child: Column(children: children),
      ),
    );
  }
}

/// 그룹 안의 행 하나. 눌리면 **축소 없이** 햅틱 + 잉크 6% 눌림 배경.
class GoGroupRow extends StatefulWidget {
  const GoGroupRow({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.symmetric(
        horizontal: GoSpace.card, vertical: GoSpace.m),
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry padding;

  @override
  State<GoGroupRow> createState() => _GoGroupRowState();
}

class _GoGroupRowState extends State<GoGroupRow> {
  bool _down = false;
  bool get _pressable => widget.onTap != null || widget.onLongPress != null;

  void _set(bool down) {
    if (!_pressable || _down == down) return;
    if (down) HapticFeedback.selectionClick();
    setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final row = Container(
      width: double.infinity,
      padding: widget.padding,
      color: _down
          ? Color.lerp(GoColors.surface, GoColors.ink, .07)
          : GoColors.surface,
      child: widget.child,
    );
    if (!_pressable) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: row,
    );
  }
}
