import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';

import '../theme.dart';
import 'pressable.dart';

/// 버튼의 종류. 색은 여기서 정해지고 호출부는 고르기만 한다.
enum GoButtonKind {
  /// 잉크 배경 · 페이퍼 글자. 화면의 주 행동
  primary,

  /// 라임 배경 · 잉크 글자. **GO?와 요청 수락 둘만** 쓴다
  go,

  /// 투명 · line 1.5 테두리
  secondary,

  /// 배경·테두리 없음
  text,
}

/// 버튼의 크기. 높이·라운드·글자·가로폭이 한 세트다.
enum GoButtonSize {
  /// 높이 52 · 라운드 16 · 가로 꽉 · 글자 16 w600
  lg,

  /// 높이 44 · 라운드 12 · 내용폭 + 좌우 16 · 글자 14 w600
  md,
}

/// 앱의 유일한 버튼.
///
/// 패딩·색·라운드 인자를 받지 않는다 — 그건 [kind]와 [size]가 정한다.
/// 눌림은 [Pressable](0.97 축소 + selectionClick)이 담당하고, 비활성은
/// 40% 투명, 로딩은 스피너로 바뀌되 **폭은 유지**한다(레이아웃이 튀지 않게).
///
/// 라벨은 산세리프. [serifLabel]은 "GO?" 단독 라벨 전용이다 — 세리프
/// 이탤릭은 숫자·라틴 문자에만 쓴다는 규칙(theme.dart) 때문.
class GoButton extends StatelessWidget {
  const GoButton(
    this.label, {
    super.key,
    required this.onTap,
    this.kind = GoButtonKind.primary,
    this.size = GoButtonSize.lg,
    this.icon,
    this.iconTrailing = false,
    this.enabled = true,
    this.loading = false,
    this.destructive = false,
    this.serifLabel = false,
  });

  final String label;
  final VoidCallback? onTap;
  final GoButtonKind kind;
  final GoButtonSize size;
  final IconData? icon;
  final bool iconTrailing;
  final bool enabled;
  final bool loading;

  /// secondary·text의 글자를 coralDark로. primary·go에는 영향 없음
  final bool destructive;

  /// "GO?" 단독 전용
  final bool serifLabel;

  bool get _active => enabled && !loading && onTap != null;

  @override
  Widget build(BuildContext context) {
    final lg = size == GoButtonSize.lg;
    final height = lg ? 52.0 : 44.0;
    final radius = lg ? GoRadius.md : GoRadius.sm;
    final fontSize = lg ? 16.0 : 14.0;

    final Color bg;
    final Color fg;
    final BoxBorder? border;
    // 눌렸을 때의 배경. 면이 있는 버튼은 **어두워지고**, 면이 없는 버튼은
    // 잉크가 옅게 깔린다 — 투명한 버튼에 색을 씌우려 하면 배경이 뭐든
    // 상관없이 지저분해지므로 잉크 6%만 얹는다
    final Color bgDown;
    final List<BoxShadow>? shadow;
    switch (kind) {
      case GoButtonKind.primary:
        bg = GoColors.ink;
        fg = GoColors.paper;
        bgDown = const Color(0xFF35342C); // ink를 밝히는 쪽으로 — 이미 거의 검정
        border = null;
        shadow = GoShadow.raised;
      case GoButtonKind.go:
        bg = GoColors.lime;
        fg = GoColors.ink;
        bgDown = const Color(0xFFAFC935); // lime을 한 단 낮춘 값
        border = null;
        shadow = GoShadow.raised;
      case GoButtonKind.secondary:
        bg = GoColors.surface;
        fg = destructive ? GoColors.coralDark : GoColors.ink;
        bgDown = const Color(0xFFEDE7DE);
        border = Border.all(color: GoColors.line, width: GoStroke.card);
        shadow = GoShadow.card;
      case GoButtonKind.text:
        bg = Colors.transparent;
        fg = destructive ? GoColors.coralDark : GoColors.ink;
        bgDown = const Color(0x141A1A16); // ink 8%
        border = null;
        shadow = null;
    }

    final textStyle = serifLabel
        ? GoTheme.serif(fontSize + 2, color: fg)
        : TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600, color: fg);

    final labelWidget = Text(label, style: textStyle, maxLines: 1);
    final Widget content;
    if (icon == null) {
      content = labelWidget;
    } else {
      final ic = Icon(icon, size: 18, color: fg);
      content = Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: iconTrailing
            ? [labelWidget, const SizedBox(width: GoSpace.s), ic]
            : [ic, const SizedBox(width: GoSpace.s), labelWidget],
      );
    }

    // 로딩: 라벨 자리는 그대로 두고(폭 유지) 위에 스피너만 얹는다
    final body = Stack(alignment: Alignment.center, children: [
      Opacity(opacity: loading ? 0 : 1, child: content),
      if (loading) CupertinoActivityIndicator(color: fg),
    ]);

    // 축소(Pressable)만으로는 손끝에 가려 안 보인다. 색이 가라앉고 그림자가
    // 접히는 것이 실제로 "눌렸다"고 말해주는 부분이다
    return Pressable(
      onTap: _active ? onTap : null,
      builder: (context, pressed, child) => Opacity(
        opacity: enabled ? 1 : .4,
        child: AnimatedContainer(
          duration: pressed ? Duration.zero : Pressable.releaseDuration,
          curve: Curves.easeOut,
          height: height,
          width: lg ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: GoSpace.l),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: pressed ? bgDown : bg,
            borderRadius: BorderRadius.circular(radius),
            border: border,
            boxShadow: shadow == null
                ? null
                : (pressed ? GoShadow.pressed : shadow),
          ),
          child: child,
        ),
      ),
      child: body,
    );
  }
}
