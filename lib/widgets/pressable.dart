import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

/// 누르면 즉시 반응하는 탭 영역.
///
/// 왜 공통 위젯인가: 눌림 반응은 화면마다 조금씩 다르게 만들어지기 쉽고,
/// 그러면 같은 앱 안에서 어떤 버튼은 반응하고 어떤 버튼은 죽은 것처럼
/// 느껴진다. **"눌렀다"는 감각은 화면이 아니라 앱의 성질**이라 한 곳에 둔다.
///
/// 규칙 두 개뿐:
/// - 손가락이 닿는 **즉시**(0ms) 0.97로 줄어든다. 애니메이션 시작을 늦추면
///   빠른 탭에서는 아무 일도 안 일어난 것처럼 보인다
/// - 닿는 순간 [HapticFeedback.selectionClick] — 실행이 아니라 "받았다"는 뜻
///
/// 되돌아오는 것만 90ms를 준다. 눌릴 때 늦으면 둔하고, 돌아올 때 빠르면
/// 튕기는 느낌이 난다.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.97,
    this.behavior = HitTestBehavior.opaque,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 눌렸을 때 크기. 0.97보다 작게 하면 큰 버튼에서 과장돼 보인다
  final double scale;
  final HitTestBehavior behavior;

  /// 눌림 상태가 원래대로 돌아오는 시간
  static const releaseDuration = Duration(milliseconds: 90);

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  void _setDown(bool down) {
    if (!_enabled || _down == down) return;
    if (down) HapticFeedback.selectionClick();
    setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: (_) => _setDown(true),
      onTapUp: (_) => _setDown(false),
      onTapCancel: () => _setDown(false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        // 눌리는 것은 즉시, 놓는 것만 부드럽게
        duration: _down ? Duration.zero : Pressable.releaseDuration,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
