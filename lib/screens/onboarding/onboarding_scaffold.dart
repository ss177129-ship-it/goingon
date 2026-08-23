import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/pressable.dart';

/// 온보딩 네 장이 공유하는 뼈대 — 와이어프레임 01~04가 같은 격자를 쓴다:
/// 좌우 24 · 위 28 · 요소 간격 14 · 바닥에 52pt 알약 버튼.
///
/// 한 곳에 둔 이유는 코드를 줄이려는 게 아니라 **네 장이 한 흐름으로
/// 보이게** 하기 위해서다. 화면마다 여백을 따로 쓰면 넘길 때마다 바닥이
/// 미세하게 움직이고, 그게 "덜 만든 앱"의 냄새다.
class OnboardingScaffold extends StatelessWidget {
  const OnboardingScaffold({
    super.key,
    required this.content,
    required this.action,
    this.footer,
  });

  /// 버튼 위에 쌓이는 것들. 사이 간격(14)은 여기서 넣는다.
  /// 이름이 `children`이 아닌 이유는 이 위젯의 자식이 본문만이 아니어서다 —
  /// 버튼과 꼬리말도 자식이고, 그중 하나만 `children`이면 읽는 사람이 헷갈린다
  final List<Widget> content;

  /// 바닥 알약 버튼
  final Widget action;

  /// 버튼 아래 한 줄(건너뛰기 등). 없으면 자리도 없다
  final Widget? footer;

  static const gap = SizedBox(height: 14);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...content,
              const SizedBox(height: 14),
              action,
              if (footer != null) ...[const SizedBox(height: 14), footer!],
            ],
          ),
        ),
      ),
    );
  }
}

/// 온보딩의 바닥 버튼 — 와이어프레임의 52pt 알약(라운딩 26).
///
/// 기존 화면들의 버튼(라운딩 16~18)과 일부러 다르다. 개편 화면의 기준은
/// 와이어프레임이고, 온보딩은 그 첫 인상이다
class OnboardingButton extends StatelessWidget {
  const OnboardingButton({
    super.key,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1 : .35,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: GoColors.ink,
            borderRadius: BorderRadius.circular(26),
          ),
          alignment: Alignment.center,
          child: Text(label, style: GoTheme.serif(18, color: GoColors.paper)),
        ),
      ),
    );
  }
}

/// 온보딩 본문 카드 — 와이어프레임의 회색 박스 자리.
/// 회색(#ededed)은 와이어프레임의 '내용 미정' 표시이지 색 결정이 아니라,
/// 실제 색은 캔버스 위 흰 카드 + 얇은 선으로 간다(prototype_v2와 같은 재질)
class OnboardingCard extends StatelessWidget {
  const OnboardingCard({
    super.key,
    required this.child,
    this.height,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.selected = false,
  });

  final Widget child;
  final double? height;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: selected ? GoColors.lime.withValues(alpha: .18) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? GoColors.limeDark : GoColors.line,
          width: selected ? 1.6 : 1,
        ),
      ),
      alignment: Alignment.center,
      child: child,
    );
    return onTap == null ? card : Pressable(onTap: onTap, child: card);
  }
}
