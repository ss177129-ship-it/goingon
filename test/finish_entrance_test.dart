import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goingon/screens/finish_screen.dart';
import 'package:goingon/theme.dart';

void main() {
  Widget host({bool reduce = false}) => MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: MaterialApp(
          theme: GoTheme.light(),
          home: const FinishScreen(
            sessionId: 'demo',
            partnerName: '지수',
            mySeconds: 1130,
            myKm: 3.2,
            myKcal: 210,
            demo: true,
          ),
        ),
      );

  double opacityOf(WidgetTester tester, String text) {
    final fade = find.ancestor(
        of: find.text(text), matching: find.byType(FadeTransition));
    return tester.widget<FadeTransition>(fade.first).opacity.value;
  }

  testWidgets('완료 화면은 타이틀 → 합산 카드 → 개인 기록 → CTA 순으로 떠오른다',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pump(); // post-frame: forward()
    await tester.pump(const Duration(milliseconds: 120));
    final title = opacityOf(tester, '함께 달린 것');
    final cta = opacityOf(tester, '다음에 또 함께 달려요');
    expect(title, greaterThan(0));
    expect(cta, lessThan(title), reason: 'CTA는 마지막에 온다');

    await tester.pump(const Duration(milliseconds: 700));
    expect(opacityOf(tester, '다음에 또 함께 달려요'), 1);
    expect(opacityOf(tester, '함께 달린 것'), 1);
    // 데모의 상대 기록 도착 타이머까지 흘려보낸다
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('동작 줄이기: 처음부터 완성 상태', (tester) async {
    await tester.pumpWidget(host(reduce: true));
    await tester.pump();
    await tester.pump();
    expect(opacityOf(tester, '다음에 또 함께 달려요'), 1);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}
