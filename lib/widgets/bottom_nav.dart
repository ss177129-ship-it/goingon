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
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: const BoxDecoration(
            color: GoColors.surfaceVeil,
            border: Border(
                top: BorderSide(
                    color: GoColors.line, width: GoStroke.rule)),
            boxShadow: GoShadow.bar,
          ),
          padding: const EdgeInsets.fromLTRB(28, 6, 28, 6),
          child: Row(children: [
            _item(0, Icons.home_rounded, '홈'),
            _item(1, Icons.people_alt_outlined, '우리', badge: requestCount),
            _item(2, Icons.settings_outlined, '설정'),
          ]),
        ),
      ),
    );
  }

  /// 선택 인디케이터 — 아이콘 뒤의 알약(56×32, radius 16). 틴트가 아니라
  /// **ink 면 + paper 아이콘**으로 뒤집는다(GoSegment와 같은 문법). 페이퍼
  /// 위의 반투명 틴트는 사라지지만, 잉크 면은 어디서든 가장 어두운 것이라
  /// 시선이 먼저 간다. 비선택은 아이콘·라벨 모두 mid로 한 단 내려간다
  static const _pillWidth = 56.0;
  static const _pillHeight = 32.0;

  Widget _item(int i, IconData icon, String label, {int badge = 0}) {
    final active = i == index;
    final iconWidget =
        Icon(icon, size: 24, color: active ? GoColors.paper : GoColors.mid);
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
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedContainer(
              duration: GoMotion.select,
              curve: GoMotion.curve,
              width: _pillWidth,
              height: _pillHeight,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? GoColors.ink : Colors.transparent,
                borderRadius: BorderRadius.circular(GoRadius.md),
              ),
              child: GoCountBadge(count: badge, child: iconWidget),
            ),
            const SizedBox(height: 4),
            AnimatedDefaultTextStyle(
              duration: GoMotion.select,
              curve: GoMotion.curve,
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w600,
                  color: active ? GoColors.ink : GoColors.mid),
              child: Text(label),
            ),
          ]),
        ),
      ),
    );
  }
}
