import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'go_badge.dart';
import 'pressable.dart';

/// 하단 탭 — 홈 / 우리 / 설정 (프로토타입 .nav-bar)
///
/// **화면 맨 아래를 끝까지 덮는다**(2026-09-08). 홈 인디케이터 자리를 남겨
/// 두면 탭바가 바닥에서 뜬 판때기로 보이고, 그 틈으로 보이는 종이색이
/// 탭바보다 밝아 눈이 그리로 간다. 인디케이터 높이를 안쪽 여백으로 직접
/// 먹으므로 부모는 `SafeArea(bottom: false)`로 감싸야 한다.
class GoBottomNav extends StatefulWidget {
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

  /// 선택 인디케이터 알약 — 아이콘 뒤에 깔리는 64×36, radius [GoRadius.md]
  static const pillWidth = 64.0;
  static const pillHeight = 36.0;

  /// 아이콘. 라벨이 없는 탭바에서 아이콘은 **글자 없이 혼자 뜻을 지고**
  /// 있으므로, 라벨을 데리고 있던 때의 24pt로는 작다(2026-09-08)
  static const iconSize = 26.0;

  /// 손가락이 닿는 줄의 높이. 알약(36)보다 큰 이유는 **표적이 알약이 아니라
  /// 탭이기 때문**이다 — 라벨을 지우면서 표적이 32pt로 줄어 애플의 최소
  /// 44pt를 밑돌았다(2026-09-08 접근성 트리에서 확인). 최소를 겨우 맞추는
  /// 대신 48로 둔다: 탭바는 화면 맨 아래라 엄지가 가장 부정확하게 닿는
  /// 자리다. 알약은 이 줄 안에 세로 가운데로 놓인다
  static const rowHeight = 48.0;

  /// 아이콘 줄 좌우 여백
  static const _sidePad = 28.0;

  @override
  State<GoBottomNav> createState() => _GoBottomNavState();
}

class _GoBottomNavState extends State<GoBottomNav> {
  /// 지금 손가락이 닿아 있는 탭. 알약 하나를 셋이 나눠 쓰므로 눌림 상태도
  /// 여기서 함께 갖는다 — 각 항목이 따로 갖고 있으면, 미끄러져 다니는 알약이
  /// 누구의 눌림을 그려야 하는지 알 수 없다
  int? _pressed;

  static const _tabs = [
    (Icons.home_outlined, Icons.home_rounded, '홈'),
    (Icons.mail_outline, Icons.mail_rounded, '제안'),
    (Icons.people_alt_outlined, Icons.people_alt_rounded, '우리'),
    (Icons.settings_outlined, Icons.settings_rounded, '설정'),
  ];

  /// 배지가 붙는 탭 — 답해야 할 제안이 있는 곳.
  ///
  /// 전에는 '우리'(인덱스 1)에 친구 요청 수를 달았는데, 정작 그 목록은
  /// 홈에 있었다. 배지가 가리키는 곳과 실제로 가야 하는 곳이 달랐다
  static const _badgeTab = 1;

  @override
  Widget build(BuildContext context) {
    final roles = GoRoles.of(context);
    final media = MediaQuery.of(context);

    // 홈 인디케이터 높이. SafeArea가 먼저 먹었더라도 viewPadding은 그대로라
    // 여기서 다시 읽어도 두 번 들어가지 않는다
    final bottomInset = media.viewPadding.bottom;

    // 진짜 1픽셀. 논리 1.0은 3배 화면에서 3픽셀 막대가 돼 "굵은 선"이 된다
    final hairline = 1 / media.devicePixelRatio;

    return DecoratedBox(
      // 그림자는 ClipRect **밖에서** 그린다. 안에 두면 위로 던진 그림자가
      // 그대로 잘려나가 깊이가 하나도 남지 않는다
      decoration: const BoxDecoration(boxShadow: GoShadow.bar),
      child: ClipRect(
        child: BackdropFilter(
          // iOS 탭바 방식 — 목록이 밑으로 지나가는 게 비쳐 보이는 막.
          // 불투명한 색을 깔면 화면을 가로로 자른 벽이 되고, 반투명이기만
          // 하고 블러가 없으면 글자가 그대로 비쳐 지저분해진다. 둘은 한 세트다
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: DecoratedBox(
            decoration: BoxDecoration(
              // 위는 묽고 아래는 되다 — 목록은 윗입술 아래로 비쳐 들어가고,
              // 인디케이터가 놓이는 바닥은 단단히 막힌다. 이 농도 차이가 곧
              // 판의 두께로 읽힌다
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  roles.surfaceVeil.withValues(alpha: .76),
                  roles.surfaceHigh,
                ],
              ),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // 베벨 두 줄 — 잘린 자국이 아니라 **모서리**로 보이게 하는 최소
              // 장치다. 위는 잉크가 아주 옅게 깔린 그늘, 바로 아래는 빛을 받은
              // 면. 예전의 line 1.0px는 색도 굵기도 세서 화면을 가로로 자르는
              // 막대였다(2026-09-08)
              Container(
                  height: hairline, color: roles.rule.withValues(alpha: .09)),
              Container(
                  height: hairline,
                  color: roles.surfaceHigh.withValues(alpha: .85)),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    GoBottomNav._sidePad, 4, GoBottomNav._sidePad, 4),
                child: _row(roles),
              ),
              // 홈 인디케이터 자리까지 같은 면이 이어진다
              SizedBox(height: bottomInset),
            ]),
          ),
        ),
      ),
    );
  }

  /// 알약 **한 개**가 세 자리를 오간다. 자리마다 알약을 두고 색만 바꾸면
  /// "여기 꺼지고 저기 켜졌다"로 읽힌다 — 같은 물체가 밀려가야 어디서 어디로
  /// 갔는지가 눈에 남는다(2026-09-08)
  Widget _row(GoRoles roles) {
    return LayoutBuilder(builder: (context, c) {
      final slot = c.maxWidth / _tabs.length;
      final pressedActive = _pressed == widget.index;
      return SizedBox(
        height: GoBottomNav.rowHeight,
        child: Stack(children: [
          AnimatedPositioned(
            duration: GoMotion.slide,
            curve: GoMotion.slideCurve,
            left: slot * widget.index + (slot - GoBottomNav.pillWidth) / 2,
            top: (GoBottomNav.rowHeight - GoBottomNav.pillHeight) / 2,
            width: GoBottomNav.pillWidth,
            height: GoBottomNav.pillHeight,
            child: AnimatedContainer(
              // 눌림은 기다리지 않는다 — 손가락이 닿는 순간 가라앉아야 한다
              duration: pressedActive ? Duration.zero : GoMotion.select,
              curve: GoMotion.curve,
              decoration: BoxDecoration(
                color: pressedActive
                    ? roles.selection.pressed
                    : roles.selection.bg,
                borderRadius: BorderRadius.circular(GoRadius.md),
              ),
            ),
          ),
          Row(children: [
            for (var i = 0; i < _tabs.length; i++)
              _item(roles, i,
                  badge: i == _badgeTab ? widget.requestCount : 0),
          ]),
        ]),
      );
    });
  }

  /// 선택 인디케이터의 색은 **잉크를 옅게 드리운 면 + 잉크 아이콘**
  /// ([GoRoles.selection]). 주 색을 쓰지 않는 이유: 탭바는 모든 화면에 붙어
  /// 있어 여기에 코랄을 두면 화면의 CTA와 매번 경쟁한다. 색만이 아니라
  /// 알약이라는 *형태*가 함께 말하므로 색을 못 보는 사람에게도 어느 탭인지
  /// 읽힌다(§5). 비선택은 textSecondary — 덜 중요할 뿐 덜 보여서는 안 된다(§4)
  ///
  /// 선택 상태는 두 겹으로 말한다: 알약(자리) + **채워진 아이콘**(비선택은
  /// 윤곽선). 색 하나가 아니라 형태가 바뀌므로 흑백으로 봐도 어느 탭인지 안다.
  ///
  /// 라벨은 화면에 그리지 않는다(2026-09-08). 대신 Semantics로 넘겨
  /// 스크린리더와 접근성 클릭에는 그대로 남긴다 — 눈에서 지우는 것과
  /// 접근성에서 지우는 것은 다른 일이다
  Widget _item(GoRoles roles, int i, {int badge = 0}) {
    final (icon, activeIcon, label) = _tabs[i];
    final active = i == widget.index;
    final iconWidget = AnimatedSwitcher(
      duration: GoMotion.select,
      switchInCurve: GoMotion.curve,
      switchOutCurve: GoMotion.curve,
      child: Icon(active ? activeIcon : icon,
          key: ValueKey(active),
          size: GoBottomNav.iconSize,
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
          onTap: () => widget.onChanged(i),
          onPressedChanged: (down) =>
              setState(() => _pressed = down ? i : null),
          // 비활성 자리를 누르는 동안엔 잉크 8% 알약이 잠깐 나타난다 —
          // 알약이 미끄러져 오기 전에 "여기가 눌리고 있다"를 자리로 먼저 말한다
          builder: (context, pressed, child) => Center(
            child: AnimatedContainer(
              duration: pressed ? Duration.zero : GoMotion.select,
              curve: GoMotion.curve,
              width: GoBottomNav.pillWidth,
              height: GoBottomNav.pillHeight,
              decoration: BoxDecoration(
                color: (pressed && !active)
                    ? roles.pressOverlay
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(GoRadius.md),
              ),
              child: child,
            ),
          ),
          child: Center(child: GoCountBadge(count: badge, child: iconWidget)),
        ),
      ),
    );
  }
}
