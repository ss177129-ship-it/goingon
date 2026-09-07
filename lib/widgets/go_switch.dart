import 'package:flutter/material.dart';

import '../theme.dart';
import 'pressable.dart';

/// iOS 크기(51×31)의 스위치에 이 앱의 색만 입힌 것.
///
/// Material `Switch`를 쓰지 않는 이유: M3 스위치는 트랙 테두리·손잡이 크기
/// 변화·아이콘 등 자기 문법이 많아 페이퍼 위에서 다른 앱의 부품처럼 보인다.
/// 여기 스위치는 **트랙 색 하나와 손잡이 위치 하나**로만 말한다 —
/// 켬은 actionComplete(pine) 트랙, 끔은 textSecondary 트랙.
///
/// 상태는 갖지 않는다(controlled). [onChanged]가 null이면 비활성 —
/// 전체가 40%로 가라앉고 탭을 받지 않는다. 행 안에 놓일 때는 행 전체가
/// 탭 영역이어야 하므로 행의 onTap도 같은 토글을 호출한다.
class GoSwitch extends StatelessWidget {
  const GoSwitch({super.key, required this.value, this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  static const width = 51.0;
  static const height = 31.0;
  static const _thumb = 27.0;
  static const _inset = 2.0;

  bool get _enabled => onChanged != null;

  /// 손가락이 닿아 있는 동안 손잡이가 옆으로 늘어난다(iOS와 같은 반응).
  /// 축소가 아니라 늘어남인 이유: 스위치는 작아서 0.97 축소가 보이지
  /// 않고, 손잡이가 움직일 방향으로 늘어나는 것이 "곧 넘어간다"를 말해준다
  static const _thumbStretch = 4.0;

  Widget _track(GoRoles roles, bool pressed) => AnimatedContainer(
        duration: GoMotion.toggle,
        curve: GoMotion.curve,
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: value ? roles.actionComplete.bg : roles.textSecondary,
          borderRadius: BorderRadius.circular(GoRadius.md),
        ),
        child: AnimatedAlign(
          duration: GoMotion.toggle,
          curve: GoMotion.curve,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: AnimatedContainer(
            duration: pressed ? Duration.zero : Pressable.releaseDuration,
            curve: GoMotion.curve,
            width: pressed ? _thumb + _thumbStretch : _thumb,
            height: _thumb,
            margin: const EdgeInsets.symmetric(horizontal: _inset),
            decoration: BoxDecoration(
              color: roles.surfaceHigh,
              borderRadius: BorderRadius.circular(_thumb / 2),
              boxShadow: GoShadow.thumb,
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final roles = GoRoles.of(context);
    return Semantics(
      toggled: value,
      enabled: _enabled,
      child: Opacity(
        opacity: _enabled ? 1 : .4,
        child: Pressable(
          scale: 1, // 축소 대신 손잡이 늘어남
          onTap: _enabled ? () => onChanged!(!value) : null,
          builder: (context, pressed, _) => _track(roles, pressed),
          child: const SizedBox.shrink(),
        ),
      ),
    );
  }
}
