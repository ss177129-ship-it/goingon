import 'package:flutter/material.dart';

import '../theme.dart';
import 'pressable.dart';

/// 아이콘 하나짜리 버튼(헤더의 검색 등). 표적 44×44.
///
/// Material `IconButton`의 잉크 스플래시 대신 이 앱의 눌림 문법을 쓴다 —
/// 닿는 즉시 0.92 축소 + 아이콘 뒤에 잉크 8% 원, 놓으면 90ms에 걷힌다.
/// 면이 없는 것이라 [GoColors.pressOverlay]를 얹는 것이 전부다
class GoIconButton extends StatelessWidget {
  const GoIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.color = GoColors.ink,
    this.size = 24,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final Color color;
  final double size;

  static const target = 44.0;

  @override
  Widget build(BuildContext context) {
    final button = Pressable(
      scale: .92,
      onTap: onTap,
      builder: (context, pressed, child) => AnimatedContainer(
        duration: pressed ? Duration.zero : Pressable.releaseDuration,
        curve: GoMotion.curve,
        width: target,
        height: target,
        decoration: BoxDecoration(
          color: pressed ? GoColors.pressOverlay : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: child,
      ),
      child: Icon(icon, size: size, color: color),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}
