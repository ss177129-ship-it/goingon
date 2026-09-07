import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goingon/theme.dart';
import 'package:goingon/widgets/go_button.dart';

/// 컬러 토큰 시스템(2026-09-08)의 규칙. 값이 아니라 **조합**을 지킨다.
void main() {
  test('GoRoles가 테마에 등록돼 있다', () {
    final theme = GoTheme.light();
    expect(theme.extension<GoRoles>(), same(GoRoles.light));
    expect(theme.scaffoldBackgroundColor, GoRoles.light.background);
  });

  test('역할 조합이 스펙과 같다', () {
    const r = GoRoles.light;
    expect(r.actionPrimary.bg, GoColors.coralComponent);
    expect(r.actionPrimary.fg, GoColors.white);
    expect(r.actionComplete.bg, GoColors.green);
    expect(r.actionComplete.fg, GoColors.lime);
    expect(r.actionSecondary.fg, GoColors.coralText);
    expect(r.actionSecondary.border, GoColors.coralText);
    expect(r.statusRunning.bg, GoColors.coral);
    expect(r.statusRunning.fg, GoColors.ink);
    expect(r.statusOnline.bg, GoColors.green);
    expect(r.statusOnline.fg, GoColors.white);
    expect(r.reward.bg, GoColors.lime);
    expect(r.reward.fg, GoColors.ink);
    expect(r.positive, GoColors.green);
    expect(r.textPrimary, GoColors.ink);
    expect(r.textSecondary, GoColors.mid);
    expect(r.link, GoColors.coralText);
  });

  /// 채도 전면 수정(2026-09-08): 보조색은 전부 선명해야 하고, 그래도 글자
  /// 대비는 지켜야 한다
  double _lum(Color c) {
    double f(double v) =>
        v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
  }

  double contrast(Color a, Color b) {
    final la = _lum(a), lb = _lum(b);
    return (math.max(la, lb) + .05) / (math.min(la, lb) + .05);
  }

  double saturation(Color c) => HSVColor.fromColor(c).saturation;

  test('보조색은 선명하고(채도 .75+), 글자 대비는 지킨다', () {
    for (final c in [
      GoColors.coralComponent,
      GoColors.coralText,
      GoColors.green,
    ]) {
      expect(saturation(c), greaterThanOrEqualTo(.75), reason: '$c');
    }
    const r = GoRoles.light;
    // 밝은 바탕 위 색 글자 4.5:1
    for (final c in [r.textSecondary, r.link, r.positive, r.partner, r.attention]) {
      expect(contrast(c, r.background), greaterThanOrEqualTo(4.5), reason: '$c');
    }
    // 면 위 본문 크기 글자 4.5:1
    expect(contrast(r.statusRunning.fg, r.statusRunning.bg), greaterThanOrEqualTo(4.5));
    expect(contrast(r.statusOnline.fg, r.statusOnline.bg), greaterThanOrEqualTo(4.5));
    expect(contrast(r.reward.fg, r.reward.bg), greaterThanOrEqualTo(4.5));
    // 굵은 큰 글자 3:1
    expect(contrast(r.actionPrimary.fg, r.actionPrimary.bg), greaterThanOrEqualTo(3));
    expect(contrast(r.actionComplete.fg, r.actionComplete.bg), greaterThanOrEqualTo(3));
  });

  testWidgets('코랄 위 흰 글자는 md 크기 버튼이어도 굵은 16pt', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: GoTheme.light(),
      home: Scaffold(
        body: Center(
          child: GoButton('시작', size: GoButtonSize.md, onTap: () {}),
        ),
      ),
    ));
    final text = tester.widget<Text>(find.text('시작'));
    expect(text.style!.fontSize, greaterThanOrEqualTo(16));
    expect(text.style!.fontWeight, FontWeight.w700);
    expect(text.style!.color, GoRoles.light.actionPrimary.fg);
  });
}
