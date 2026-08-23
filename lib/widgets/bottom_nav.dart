import 'package:flutter/material.dart';

import '../theme.dart';

/// 하단 탭 — 홈 / 여정 / 프로필.
///
/// 이름이 바뀐 것은 개편(P5)에서 각 탭이 가리키는 것이 달라졌기 때문이다.
/// '우리'는 여정(누적)을 보여주는 화면이었고, '설정'에는 프로필·페이스메이트가
/// 함께 있다. 와이어프레임의 네 번째 탭 '서랍'은 화면이 생기는 P7에서 붙는다
class GoBottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;

  const GoBottomNav({super.key, required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: GoColors.paper.withValues(alpha: .95),
        border: Border(top: BorderSide(color: GoColors.line)),
      ),
      padding: const EdgeInsets.fromLTRB(28, 10, 28, 6),
      child: Row(children: [
        _item(0, Icons.home_rounded, '홈'),
        _item(1, Icons.timeline_outlined, '여정'),
        _item(2, Icons.person_outline, '프로필'),
      ]),
    );
  }

  Widget _item(int i, IconData icon, String label) {
    final active = i == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(i),
        child: Opacity(
          opacity: active ? 1 : .32,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 24, color: GoColors.ink),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w600,
                    color: active ? GoColors.limeDark : GoColors.ink)),
          ]),
        ),
      ),
    );
  }
}
