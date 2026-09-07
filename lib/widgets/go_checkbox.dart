import 'package:flutter/material.dart';

import '../theme.dart';
import 'pressable.dart';

/// 원형 체크박스 — 브랜드 마크와 같은 원. 여러 개를 동시에 고를 때
/// (동의 항목처럼 각각 독립인 것). 하나만 고르면 [GoRadioGroup].
///
/// 미선택은 흰 면 + line 1.5, 선택은 lime 면 + ink 체크. 틴트가 아니라
/// **면 자체가 라임**이 되므로 페이퍼 위에서도 사라지지 않는다.
///
/// 탭 영역은 행 전체(최소 44). 체크만 작게 눌러야 하는 체크박스는
/// 법적 동의 화면에서 "동의를 어렵게 만든" 것으로 읽힌다.
class GoCheckbox extends StatelessWidget {
  const GoCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  /// 보통 [Text]. "(선택)" 같은 보조 표기는 [GoCheckbox.note]로 붙인다
  final Widget label;

  static const _size = 22.0;
  static const minHeight = 44.0;

  /// 라벨 뒤의 보조 표기 — "(선택)" 등. 12px mid
  static Widget note(String text) => Text(text,
      style: const TextStyle(fontSize: 12, color: GoColors.mid));

  /// 원의 색. 눌려 있는 동안은 면이 가라앉는다 — 행 전체가 탭 영역이라
  /// 손끝이 원을 가리지 않으므로, 원이 반응하는 것이 곧 보인다
  Color _fill(bool pressed) {
    if (value) return pressed ? GoColors.limePressed : GoColors.lime;
    return pressed ? GoColors.surfacePressed : GoColors.surface;
  }

  Widget _box(bool pressed) => AnimatedContainer(
        duration: pressed ? Duration.zero : GoMotion.select,
        curve: GoMotion.curve,
        width: _size,
        height: _size,
        decoration: BoxDecoration(
          color: _fill(pressed),
          shape: BoxShape.circle,
          border: Border.all(
            color: value ? GoColors.lime : GoColors.line,
            width: GoStroke.card,
          ),
        ),
        child: value
            ? const Icon(Icons.check, size: 16, color: GoColors.ink)
            : null,
      );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: value,
      child: Pressable(
        scale: 1, // 행 전체가 줄면 글줄이 흔들린다 — 원만 반응한다
        onTap: () => onChanged(!value),
        builder: (context, pressed, child) => ConstrainedBox(
          constraints: const BoxConstraints(minHeight: minHeight),
          child: Row(children: [
            _box(pressed),
            const SizedBox(width: GoSpace.m),
            Expanded(child: child),
          ]),
        ),
        child: DefaultTextStyle.merge(style: GoText.body, child: label),
      ),
    );
  }
}
