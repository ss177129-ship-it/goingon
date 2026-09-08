import 'package:flutter/material.dart';

import '../theme.dart';
import 'pressable.dart';

/// 화면 안의 밑줄 탭 — 신문 면의 밑줄처럼 잉크 2px. 하단 탭바(GoBottomNav)와
/// 다르다: 이것은 한 화면 안에서 내용의 갈래를 바꾸는 것.
///
/// 활성은 ink 글자 + 2px ink 밑줄, 비활성은 mid 글자. 컨테이너 바닥에
/// 1px line이 깔리고 밑줄이 그 위를 덮는다(밑줄을 -1 내려 겹침) — 활성 탭의
/// 밑줄이 바닥선과 한 선으로 이어져야 "이 탭이 아래 내용과 붙어 있다"고
/// 읽힌다.
class GoTabs extends StatelessWidget {
  const GoTabs({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  /// 라벨 사이. 항목이 좌우 여백을 갖게 되면서 간격이 두 번 더해지므로
  /// 20에서 줄였다
  static const _gap = 6.0;

  /// 세로 여백 — 14pt 글자와 합쳐 44pt를 넘긴다(12 + 20 + 12 + 밑줄 2)
  static const _padV = 12.0;

  /// 좌우 여백. 이게 없으면 표적 폭이 글자 폭 그대로라, '주'처럼 한 글자짜리
  /// 라벨은 15pt짜리 표적이 된다(2026-09-08)
  static const _padH = 12.0;

  @override
  Widget build(BuildContext context) {
    final roles = GoRoles.of(context);
    final items = <Widget>[];
    for (var i = 0; i < labels.length; i++) {
      if (i > 0) items.add(const SizedBox(width: _gap));
      items.add(_tab(roles, i));
    }
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: roles.line, width: GoStroke.rule),
        ),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: items),
    );
  }

  Widget _tab(GoRoles roles, int i) {
    final active = i == index;
    return Semantics(
      selected: active,
      button: true,
      child: Pressable(
        onTap: () => onChanged(i),
        // 좌우 여백을 줘도 '주'처럼 한 글자면 40pt에 그친다 — 남는 폭은
        // 투명하지만 탭을 받는다. 세로는 이미 46이라 벌어지지 않으므로
        // 밑줄은 바닥선에 그대로 붙어 있다(2026-09-08)
        minTarget: Pressable.minSize,
        // 면이 없는 항목이라 색을 깔 곳이 없다 — 글자가 잠깐 옅어지는 것으로
        builder: (context, pressed, child) => AnimatedOpacity(
          duration: pressed ? Duration.zero : Pressable.releaseDuration,
          curve: GoMotion.curve,
          opacity: pressed ? .6 : 1,
          child: child,
        ),
        child: Container(
          // 밑줄(2px)이 바닥선(1px)을 덮도록 1px 아래로 내민다
          transform: Matrix4.translationValues(0, GoStroke.rule, 0),
          padding:
              const EdgeInsets.symmetric(vertical: _padV, horizontal: _padH),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? roles.textPrimary : Colors.transparent,
                width: GoStroke.accent,
              ),
            ),
          ),
          child: AnimatedDefaultTextStyle(
            duration: GoMotion.select,
            curve: GoMotion.curve,
            style: GoText.buttonSmall.copyWith(
                color: active ? roles.textPrimary : roles.textSecondary),
            child: Text(labels[i]),
          ),
        ),
      ),
    );
  }
}
