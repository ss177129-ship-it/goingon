import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';

import '../theme.dart';
import 'pressable.dart';

/// 버튼의 종류. 색은 [GoRoles]의 액션 역할에서 오고 호출부는 고르기만 한다.
enum GoButtonKind {
  /// actionPrimary — 코랄 면 + 흰 글자. 러닝 시작/정지·GO?·수락 같은
  /// 주 액션. **글자는 항상 굵게 16pt 이상** — 코랄 위의 흰 글자는 그
  /// 크기에서만 읽힌다
  primary,

  /// actionComplete — 초록 면 + 라임 글자. 저장·완료
  complete,

  /// actionSecondary — 투명 면 + 코랄 테두리·글자
  secondary,

  /// 배경·테두리 없음. 글자는 textPrimary
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
    this.onDark = false,
  });

  final String label;
  final VoidCallback? onTap;
  final GoButtonKind kind;
  final GoButtonSize size;
  final IconData? icon;
  final bool iconTrailing;
  final bool enabled;
  final bool loading;

  /// text 버튼의 글자를 코랄로. 면이 있는 버튼에는 영향 없음
  final bool destructive;

  /// "GO?" 단독 전용
  final bool serifLabel;

  /// 잉크·초록처럼 어두운 면 위에 놓일 때. secondary·text의 글자·테두리가
  /// textOnDark로 바뀐다. 면이 있는 primary·complete에는 영향 없음
  final bool onDark;

  bool get _active => enabled && !loading && onTap != null;

  @override
  Widget build(BuildContext context) {
    final lg = size == GoButtonSize.lg;
    final height = lg ? 52.0 : 44.0;
    final radius = lg ? GoRadius.md : GoRadius.sm;
    final roles = GoRoles.of(context);
    final Color bg;
    final Color fg;
    final BoxBorder? border;
    final Color bgDown;
    final List<BoxShadow>? shadow;
    // 코랄 위의 흰 글자는 굵은 16pt 이상만 허용 — md 크기여도 주 액션은
    // 글자를 줄이지 않는다
    var fontSize = lg ? 16.0 : 14.0;
    switch (kind) {
      case GoButtonKind.primary:
        bg = roles.actionPrimary.bg;
        fg = roles.actionPrimary.fg;
        bgDown = roles.actionPrimary.pressed;
        border = null;
        shadow = GoShadow.raised;
        fontSize = 16;
      case GoButtonKind.complete:
        bg = roles.actionComplete.bg;
        fg = roles.actionComplete.fg;
        bgDown = roles.actionComplete.pressed;
        border = null;
        shadow = GoShadow.raised;
      case GoButtonKind.secondary:
        bg = roles.actionSecondary.bg;
        fg = onDark ? roles.textOnDark : roles.actionSecondary.fg;
        bgDown = onDark
            ? roles.textOnDark.withValues(alpha: .12)
            : roles.actionSecondary.pressed;
        border = Border.all(color: fg, width: GoStroke.card);
        shadow = null;
      case GoButtonKind.text:
        bg = roles.actionSecondary.bg;
        fg = onDark
            ? roles.textOnDark
            : (destructive ? roles.actionSecondary.fg : roles.textPrimary);
        bgDown = onDark
            ? roles.textOnDark.withValues(alpha: .12)
            : roles.pressOverlay;
        border = null;
        shadow = null;
    }

    final textStyle = serifLabel
        ? GoTheme.serif(fontSize + 2, color: fg)
        : TextStyle(
            fontSize: fontSize,
            fontWeight: kind == GoButtonKind.primary
                ? FontWeight.w700
                : FontWeight.w600,
            color: fg);

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
            boxShadow:
                shadow == null ? null : (pressed ? GoShadow.pressed : shadow),
          ),
          child: child,
        ),
      ),
      child: body,
    );
  }
}
