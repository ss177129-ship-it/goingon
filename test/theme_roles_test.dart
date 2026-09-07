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
    expect(r.actionComplete.bg, GoColors.pine);
    expect(r.actionComplete.fg, GoColors.lime);
    expect(r.actionSecondary.fg, GoColors.rust);
    expect(r.actionSecondary.border, GoColors.rust);
    expect(r.statusRunning.bg, GoColors.coralTint);
    expect(r.statusRunning.fg, GoColors.rust);
    expect(r.statusOnline.bg, GoColors.pineTint);
    expect(r.statusOnline.fg, GoColors.pine);
    expect(r.reward.bg, GoColors.limeTint);
    expect(r.reward.fg, GoColors.olive);
    expect(r.textPrimary, GoColors.ink);
    expect(r.textSecondary, GoColors.stone);
    expect(r.link, GoColors.coralText);
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
