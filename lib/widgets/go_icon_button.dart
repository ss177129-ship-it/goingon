import 'package:flutter/material.dart';

import '../theme.dart';
import 'pressable.dart';

/// 아이콘 하나짜리 버튼(헤더의 검색 등). 표적 44×44.
///
/// Material `IconButton`의 잉크 스플래시 대신 이 앱의 눌림 문법을 쓴다 —
/// 닿는 즉시 0.92 축소 + 아이콘 뒤에 잉크 8% 원, 놓으면 90ms에 걷힌다.
/// 면이 없는 것이라 [GoRoles.pressOverlay]를 얹는 것이 전부다.
/// [color]를 안 주면 [GoRoles.textPrimary]
class GoIconButton extends StatelessWidget {
  const GoIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.color,
    this.size = 24,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  /// null이면 textPrimary
  final Color? color;
  final double size;

  static const target = 44.0;

  @override
  Widget build(BuildContext context) {
    final roles = GoRoles.of(context);
    final button = Pressable(
      scale: .92,
      onTap: onTap,
      builder: (context, pressed, child) => AnimatedContainer(
        duration: pressed ? Duration.zero : Pressable.releaseDuration,
        curve: GoMotion.curve,
        width: target,
        height: target,
        decoration: BoxDecoration(
          color: pressed ? roles.pressOverlay : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: child,
      ),
      child: Icon(icon, size: size, color: color ?? roles.textPrimary),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}
