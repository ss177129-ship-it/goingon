// 화면 상단 중앙의 워드마크 — 탭 화면 넷이 같은 자리에 같은 크기로 단다.
//
// 전에는 홈만 왼쪽 위에 로고를 달고 나머지 탭은 제목 글자로 시작해서,
// 탭을 옮길 때마다 상단의 모양이 달라졌다. 로고를 **한 위젯**으로 두는
// 이유는 크기(18)·여백·위치가 화면마다 조금씩 어긋나는 것을 막기 위해서다.
//
// 가운데 정렬은 Row+Spacer가 아니라 Stack이다. 오른쪽에 버튼(홈의 검색)이
// 있는 화면에서 Row로 두면 워드마크가 버튼 폭만큼 왼쪽으로 밀려 화면마다
// 중심이 달라진다.

import 'package:flutter/material.dart';

import 'go_icon_button.dart';
import 'goingon_wordmark.dart';

class WordmarkHeader extends StatelessWidget {
  const WordmarkHeader({super.key, this.trailing});

  /// 오른쪽 끝에 서는 것(홈의 페이스메이트 찾기). 없으면 로고만 선다
  final Widget? trailing;

  /// 로고 높이. 홈이 쓰던 값 그대로 — 스플래시에서 이어지는 크기다
  static const logoHeight = 18.0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 오른쪽 여백이 좁은 이유: 44pt 표적 안의 24pt 아이콘이 시각적으로
      // 본문 가장자리(22)에 맞으려면 상자는 그보다 안쪽에 서야 한다
      padding: const EdgeInsets.fromLTRB(22, 10, 12, 6),
      child: SizedBox(
        // 오른쪽 버튼이 없어도 높이를 같게 둔다 — 탭을 옮길 때 아래 내용이
        // 위아래로 튀지 않는다
        height: GoIconButton.target,
        child: Stack(children: [
          const Center(child: GoingOnWordmark(height: logoHeight)),
          if (trailing != null)
            Positioned(right: 0, top: 0, bottom: 0, child: Center(child: trailing)),
        ]),
      ),
    );
  }
}
