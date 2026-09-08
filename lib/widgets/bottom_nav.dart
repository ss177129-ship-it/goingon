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
                top: BorderSide(color: roles.line, width: GoStroke.rule)),
            boxShadow: GoShadow.bar,
          ),
          // 라벨을 없앤 만큼 위아래를 벌려 탭바 높이와 손가락 표적을 지킨다
          padding: const EdgeInsets.fromLTRB(28, 12, 28, 12),
          child: Row(children: [
            _item(roles, 0, Icons.home_outlined, Icons.home_rounded, '홈'),
            _item(roles, 1, Icons.people_alt_outlined, Icons.people_alt_rounded,
                '우리',
                badge: requestCount),
            _item(roles, 2, Icons.settings_outlined, Icons.settings_rounded,
                '설정'),
          ]),
        ),
      ),
    );
  }

  /// 선택 인디케이터 — 아이콘 뒤의 알약(56×32, radius 16). **잉크를 옅게
  /// 드리운 그림자 면 + 잉크 아이콘**([GoRoles.selection]). 주 색을 쓰지 않는
  /// 이유: 탭바는 모든 화면에 붙어 있어 여기에 코랄을 두면 화면의 CTA와 매번
  /// 경쟁한다. 색만이 아니라 알약이라는 *형태*가 함께 말하므로 색을 못 보는
  /// 사람에게도 어느 탭인지 읽힌다(§5). 비선택은 textSecondary — 덜 중요할
  /// 뿐 덜 보여서는 안 된다(§4)
  ///
  /// 선택 상태는 두 겹으로 말한다: 알약(자리) + **채워진 아이콘**(비선택은
  /// 윤곽선). 색 하나가 아니라 형태가 바뀌므로 흑백으로 봐도 어느 탭인지
  /// 안다. 알약은 선택되는 순간 0.9에서 1로 커지며 자리에 앉는다 — 색만
  /// 바뀌면 "켜졌다"가 아니라 "바뀌었다"로만 읽힌다.
  ///
  /// 라벨은 화면에 그리지 않는다(2026-09-08). 대신 [label]을 Semantics로
  /// 넘겨 스크린리더와 접근성 클릭에는 그대로 남긴다 — 눈에서 지우는 것과
  /// 접근성에서 지우는 것은 다른 일이다
  static const _pillWidth = 56.0;
  static const _pillHeight = 32.0;

  Widget _item(
      GoRoles roles, int i, IconData icon, IconData activeIcon, String label,
      {int badge = 0}) {
    final active = i == index;
    final iconWidget = AnimatedSwitcher(
      duration: GoMotion.select,
      switchInCurve: GoMotion.curve,
      switchOutCurve: GoMotion.curve,
      child: Icon(active ? activeIcon : icon,
          key: ValueKey(active),
          size: 24,
          color: active ? roles.selection.fg : roles.textSecondary),
    );
    return Expanded(
      // 탭바는 모든 화면에 붙어 있어서, 여기가 반응하지 않으면 앱 전체가
      // 둔하게 느껴진다. 축소는 0.92 — 아이콘 하나짜리 작은 표적이라
      // 버튼(0.97)보다 크게 줄여야 눈에 보인다
      child: Semantics(
        selected: active,
        button: true,
        label: label,
        child: Pressable(
          scale: .92,
          onTap: () => onChanged(i),
          // 눌려 있는 동안: 활성 알약은 잉크가 가라앉고, 비활성 자리에는
          // 잉크 8% 알약이 잠깐 나타난다 — "여기가 눌리고 있다"를 자리로 말한다
          builder: (context, pressed, child) =>
              // 알약만 커지고 아이콘은 그대로 — 비선택 아이콘까지 줄이면
              // 덜 보이게 되는데, 그건 위계가 아니라 가시성을 깎는 것이다(§4)
              SizedBox(
            width: _pillWidth,
            height: _pillHeight,
            child: Stack(alignment: Alignment.center, children: [
              AnimatedScale(
                scale: active ? 1 : .9,
                duration: GoMotion.select,
                curve: GoMotion.curve,
                child: AnimatedContainer(
                  duration: pressed ? Duration.zero : GoMotion.select,
                  curve: GoMotion.curve,
                  width: _pillWidth,
                  height: _pillHeight,
                  decoration: BoxDecoration(
                    color: active
                        ? (pressed
                            ? roles.selection.pressed
                            : roles.selection.bg)
                        : (pressed ? roles.pressOverlay : Colors.transparent),
                    borderRadius: BorderRadius.circular(GoRadius.md),
                  ),
                ),
              ),
              GoCountBadge(count: badge, child: iconWidget),
            ]),
          ),
          child: const SizedBox.shrink(),
        ),
      ),
    );
  }
}
