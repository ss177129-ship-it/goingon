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

  test('역할 조합이 스펙과 같다 (2026-09-09 세 묶음)', () {
    const r = GoRoles.light;
    // 브랜드 — 주 액션·뛰는 중·리워드에만
    expect(r.actionPrimary.bg, GoColors.coralComponent);
    expect(r.actionPrimary.fg, GoColors.white);
    expect(r.statusRunning.bg, GoColors.coral);
    expect(r.statusRunning.fg, GoColors.ink);
    expect(r.reward.bg, GoColors.lime);
    expect(r.reward.fg, GoColors.ink);
    // 확정은 잉크, 보조는 중성
    expect(r.actionComplete.bg, GoColors.ink);
    expect(r.actionComplete.fg, GoColors.paper);
    expect(r.actionSecondary.fg, GoColors.ink);
    expect(r.actionSecondary.border, GoColors.neutral400);
    expect(r.textPrimary, GoColors.ink);
    expect(r.textSecondary, GoColors.neutral600);
    expect(r.link, GoColors.neutral700);
    // 시맨틱
    expect(r.statusOnline.bg, GoColors.successSolid);
    expect(r.statusOnline.fg, GoColors.white);
    expect(r.success.fg, GoColors.successText);
    expect(r.warning.fg, GoColors.warningText);
    expect(r.error.fg, GoColors.errorText);
    expect(r.info.fg, GoColors.infoText);
    // 관계색은 시맨틱과 다른 값 — 나 ≠ 성공, 상대 ≠ 오류
    expect(r.self, isNot(r.success.fg));
    expect(r.partner, isNot(r.error.fg));
    // 옛 이름은 새 역할로 이어진다
    // ignore: deprecated_member_use_from_same_package
    expect(r.positive, r.success.fg);
    // ignore: deprecated_member_use_from_same_package
    expect(r.attention, r.warning.fg);
  });

  double lum(Color c) {
    double f(double v) =>
        v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
  }

  double contrast(Color a, Color b) {
    final la = lum(a), lb = lum(b);
    return (math.max(la, lb) + .05) / (math.min(la, lb) + .05);
  }

  double hue(Color c) => HSVColor.fromColor(c).hue;

  test('밝은 바탕 위 색 글자는 전부 4.5:1', () {
    const r = GoRoles.light;
    final text = {
      'textSecondary': r.textSecondary,
      'link': r.link,
      'success': r.success.fg,
      'warning': r.warning.fg,
      'error': r.error.fg,
      'info': r.info.fg,
      'self': r.self,
      'partner': r.partner,
    };
    for (final bg in [r.background, r.surface, r.canvas]) {
      text.forEach((name, c) {
        expect(contrast(c, bg), greaterThanOrEqualTo(4.5),
            reason: '$name on $bg');
      });
    }
  });

  test('면 위 글자 대비', () {
    const r = GoRoles.light;
    // 진한 면 위 본문 크기 4.5:1
    for (final role in [r.statusRunning, r.statusOnline, r.reward, r.dark,
        r.actionComplete, r.success, r.warning, r.error, r.info]) {
      expect(contrast(role.fg, role.bg), greaterThanOrEqualTo(4.5),
          reason: '${role.fg} on ${role.bg}');
    }
    // 코랄 위 흰 글자는 굵은 큰 글자 3:1
    expect(contrast(r.actionPrimary.fg, r.actionPrimary.bg), greaterThanOrEqualTo(3));
    // 잉크 위 원색
    expect(contrast(r.selfOnDark, r.dark.bg), greaterThanOrEqualTo(4.5));
    expect(contrast(r.partnerOnDark, r.dark.bg), greaterThanOrEqualTo(4.5));
  });

  test('관계색과 시맨틱은 색상(hue)이 다르다', () {
    const r = GoRoles.light;
    // 나(올리브, ~75°) vs 성공(초록, ~140°)
    expect((hue(r.self) - hue(r.success.fg)).abs(), greaterThan(40));
    // 상대(코랄 파생, ~8°) vs 오류(빨강, ~0°) — 이웃하므로 상태는 아이콘·문구 동반
    expect(r.partner, isNot(r.error.fg));
  });

  test('중성 램프는 페이퍼의 색상을 따른다(웜 그레이)', () {
    for (final c in [
      GoColors.neutral100, GoColors.neutral200, GoColors.neutral300,
      GoColors.neutral400, GoColors.neutral500, GoColors.neutral600,
      GoColors.neutral700, GoColors.neutral800,
    ]) {
      expect(c.r, greaterThanOrEqualTo(c.g), reason: '$c');
      expect(c.g, greaterThan(c.b), reason: '$c');
    }
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
