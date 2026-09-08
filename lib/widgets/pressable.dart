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
    this.builder,
    this.onPressedChanged,
    this.minTarget,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 눌림 상태를 자기 모양에 반영해야 하는 위젯용. 크기 축소만으로는
  /// 부족한 것들이 있다 — 버튼은 색이 가라앉아야 하고, 카드는 그림자가
  /// 줄어야 눌린 것처럼 보인다. [child]를 감쌀 껍데기를 여기서 만든다
  final Widget Function(BuildContext context, bool pressed, Widget child)?
      builder;

  /// 눌림 상태를 **바깥이** 알아야 할 때. [builder]는 자기 안쪽만 다시 그릴
  /// 수 있어서, 눌린 자리 밖에 있는 것(탭바에서 자리를 옮겨 다니는 알약
  /// 하나처럼)이 반응해야 하면 이쪽으로 받는다
  final ValueChanged<bool>? onPressedChanged;

  /// 눌렸을 때 크기. 0.97보다 작게 하면 큰 버튼에서 과장돼 보인다
  final double scale;
  final HitTestBehavior behavior;

  /// 손가락이 닿는 최소 표적. **보이는 크기는 그대로 두고 닿는 자리만**
  /// 넓힌다 — 안쪽 내용은 가운데에 놓이고, 남는 자리는 투명하지만 탭을
  /// 받는다.
  ///
  /// 왜 옵션인가: [Pressable]은 스스로 크기를 정하지 않아서, 44pt를 지키는
  /// 일이 전부 호출부 책임이었고 실제로 여기저기서 새어 나갔다(2026-09-08
  /// 감사). 작은 것을 누를 때 필요한 건 큰 그림이 아니라 큰 표적이다.
  ///
  /// 자리를 실제로 차지하므로 부모가 그만큼 자랄 수 있다는 점만 유의할 것
  final Size? minTarget;

  /// 애플 최소 권장 표적. 이보다 작으면 겨냥이 아니라 운이 된다
  static const minSize = Size.square(44);

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
    widget.onPressedChanged?.call(down);
  }

  @override
  Widget build(BuildContext context) {
    Widget visual = widget.builder == null
        ? widget.child
        : widget.builder!(context, _down && _enabled, widget.child);

    final target = widget.minTarget;
    if (target != null) {
      // 안쪽 크기에 맞춰 오므린 뒤(widthFactor/heightFactor 1) 최소치까지만
      // 벌린다. 인수를 빼면 Align이 부모가 허락하는 최대까지 부풀어, 화면
      // 하나를 통째로 먹는다(2026-09-08 테스트에서 800×600이 나왔다)
      visual = ConstrainedBox(
        constraints:
            BoxConstraints(minWidth: target.width, minHeight: target.height),
        child: Align(widthFactor: 1, heightFactor: 1, child: visual),
      );
    }

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
        child: visual,
      ),
    );
  }
}
