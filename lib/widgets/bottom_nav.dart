import 'package:flutter/material.dart';

import '../theme.dart';

/// 하단 탭 — 홈 / 우리 / 설정 (프로토타입 .nav-bar)
class GoBottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;

  const GoBottomNav({super.key, required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      // iOS 탭바 방식 — 바탕(페이퍼)과 다른 면(흰 88%) + 상단 헤어라인
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .88),
        border: Border(top: BorderSide(color: GoColors.line, width: GoStroke.rule)),
      ),
      padding: const EdgeInsets.fromLTRB(28, 10, 28, 6),
      child: Row(children: [
        _item(0, Icons.home_rounded, '홈'),
        _item(1, Icons.people_alt_outlined, '우리'),
        _item(2, Icons.settings_outlined, '설정'),
      ]),
    );
  }

  Widget _item(int i, IconData icon, String label) {
    final active = i == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
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
