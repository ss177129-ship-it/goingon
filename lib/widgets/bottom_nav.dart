import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'pressable.dart';

/// 하단 탭 — 홈 / 우리 / 설정 (프로토타입 .nav-bar)
class GoBottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;

  const GoBottomNav({super.key, required this.index, required this.onChanged});

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
          padding: const EdgeInsets.fromLTRB(28, 10, 28, 6),
          child: Row(children: [
            _item(0, Icons.home_rounded, '홈'),
            _item(1, Icons.people_alt_outlined, '우리'),
            _item(2, Icons.settings_outlined, '설정'),
          ]),
        ),
      ),
    );
  }

  Widget _item(int i, IconData icon, String label) {
    final active = i == index;
    return Expanded(
      // 탭바는 모든 화면에 붙어 있어서, 여기가 반응하지 않으면 앱 전체가
      // 둔하게 느껴진다. 축소는 0.92 — 아이콘 하나짜리 작은 표적이라
      // 버튼(0.97)보다 크게 줄여야 눈에 보인다
      child: Pressable(
        scale: .92,
        onTap: () => onChanged(i),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 24, color: active ? GoColors.ink : GoColors.mid),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w600,
                  color: active ? GoColors.limeDark : GoColors.mid)),
        ]),
      ),
    );
  }
}
