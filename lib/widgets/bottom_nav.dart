import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'go_badge.dart';
import 'pressable.dart';

/// 하단 탭 — 홈 / 우리 / 설정 (프로토타입 .nav-bar)
class GoBottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;

  /// '우리' 탭 아이콘에 얹을 수 — 나에게 온 친구 요청. 0이면 배지 없음
  final int requestCount;

  const GoBottomNav({
    super.key,
    required this.index,
    required this.onChanged,
    this.requestCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    // iOS 탭바 방식 — 목록이 밑으로 지나가는 게 비쳐 보이는 막.
    // 불투명한 색을 깔면 화면을 가로로 자른 벽이 되고, 반투명이기만 하고
    // 블러가 없으면 글자가 그대로 비쳐 지저분해진다. 둘은 한 세트다
    final roles = GoRoles.of(context);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: roles.surfaceVeil,
            border: Border(
                top: BorderSide(
                    color: roles.line, width: GoStroke.rule)),
            boxShadow: GoShadow.bar,
          ),
          padding: const EdgeInsets.fromLTRB(28, 6, 28, 6),
          child: Row(children: [
            _item(roles, 0, Icons.home_rounded, '홈'),
            _item(roles, 1, Icons.people_alt_outlined, '우리',
                badge: requestCount),
            _item(roles, 2, Icons.settings_outlined, '설정'),
          ]),
        ),
      ),
    );
  }

  /// 선택 인디케이터 — 아이콘 뒤의 알약(56×32, radius 16). **주 색(primary)
  /// 면 + 흰 아이콘.** 현재 선택된 내비게이션은 주 색을 쓴다는 규칙(theme.dart
  /// Color Usage Rules §1). 색만이 아니라 알약이라는 *형태*가 함께 말하므로
  /// 색을 못 보는 사람에게도 어느 탭인지 읽힌다(§5). 비선택은 textSecondary —
  /// 덜 중요할 뿐 덜 보여서는 안 된다(§4)
  static const _pillWidth = 56.0;
  static const _pillHeight = 32.0;

  Widget _item(GoRoles roles, int i, IconData icon, String label,
      {int badge = 0}) {
    final active = i == index;
    final iconWidget = Icon(icon,
        size: 24,
        color: active ? roles.actionPrimary.fg : roles.textSecondary);
    return Expanded(
      // 탭바는 모든 화면에 붙어 있어서, 여기가 반응하지 않으면 앱 전체가
      // 둔하게 느껴진다. 축소는 0.92 — 아이콘 하나짜리 작은 표적이라
      // 버튼(0.97)보다 크게 줄여야 눈에 보인다
      child: Semantics(
        selected: active,
        button: true,
        child: Pressable(
          scale: .92,
          onTap: () => onChanged(i),
          // 눌려 있는 동안: 활성 알약은 잉크가 가라앉고, 비활성 자리에는
          // 잉크 8% 알약이 잠깐 나타난다 — "여기가 눌리고 있다"를 자리로 말한다
          builder: (context, pressed, child) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: pressed ? Duration.zero : GoMotion.select,
                curve: GoMotion.curve,
                width: _pillWidth,
                height: _pillHeight,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active
                      ? (pressed
                          ? roles.actionPrimary.pressed
                          : roles.actionPrimary.bg)
                      : (pressed ? roles.pressOverlay : Colors.transparent),
                  borderRadius: BorderRadius.circular(GoRadius.md),
                ),
                child: GoCountBadge(count: badge, child: iconWidget),
              ),
              const SizedBox(height: 4),
              child,
            ],
          ),
          child: AnimatedDefaultTextStyle(
            duration: GoMotion.select,
            curve: GoMotion.curve,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600,
                color: active ? roles.textPrimary : roles.textSecondary),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}
