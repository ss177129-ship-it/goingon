import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goingon/theme.dart';
import 'package:goingon/widgets/go_button.dart';
import 'package:goingon/widgets/go_card.dart';

/// 눌림 반응은 "축소"만으로는 부족하다 — 손끝이 버튼을 가리기 때문에,
/// 색이 가라앉고 그림자가 접히는 것이 실제로 눌렸다고 말해주는 부분이다.
/// 이 테스트가 지키는 것은 그 두 가지가 **실제로 바뀐다**는 사실이다.
void main() {
  BoxDecoration animatedDecorationOf(WidgetTester tester) {
    final c = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
    return c.decoration! as BoxDecoration;
  }

  testWidgets('주 버튼은 눌리면 배경이 가라앉는다', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: GoTheme.light(),
      home: Scaffold(body: Center(child: GoButton('달리기', onTap: () {}))),
    ));
    final before = animatedDecorationOf(tester).color;
    expect(before, GoRoles.light.actionPrimary.bg);

    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(GoButton)));
    await tester.pump();
    expect(animatedDecorationOf(tester).color, isNot(before),
        reason: '눌린 동안 배경색이 그대로면 아무 일도 안 일어난 것처럼 보인다');

    await gesture.up();
    await tester.pumpAndSettle();
    expect(animatedDecorationOf(tester).color, before);
  });

  testWidgets('주 버튼은 눌리면 그림자가 접힌다', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: GoTheme.light(),
      home: Scaffold(body: Center(child: GoButton('달리기', onTap: () {}))),
    ));
    expect(animatedDecorationOf(tester).boxShadow, GoShadow.raised);

    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(GoButton)));
    await tester.pump();
    expect(animatedDecorationOf(tester).boxShadow, GoShadow.pressed);
    await gesture.up();
  });

  testWidgets('글자 버튼은 그림자를 갖지 않는다', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: GoTheme.light(),
      home: Scaffold(
        body: Center(
          child: GoButton('나중에',
              kind: GoButtonKind.text, onTap: () {}),
        ),
      ),
    ));
    expect(animatedDecorationOf(tester).boxShadow, isNull);
  });

  testWidgets('누르는 카드는 읽는 카드보다 한 층 위에 떠 있다', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: GoTheme.light(),
      home: Scaffold(
        body: Column(children: [
          const GoCard(child: Text('읽는 카드')),
          GoCard(onTap: () {}, child: const Text('누르는 카드')),
        ]),
      ),
    ));
    final decos = tester
        .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
        .map((w) => w.decoration as BoxDecoration)
        .toList();
    expect(decos[0].boxShadow, GoShadow.card);
    expect(decos[0].color, GoRoles.light.surface);
    expect(decos[1].boxShadow, GoShadow.elevated);
    expect(decos[1].color, GoRoles.light.surfaceHigh);
  });

  testWidgets('카드는 눌리면 그림자가 접혀 종이로 내려앉는다', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: GoTheme.light(),
      home: Scaffold(
        body: Center(child: GoCard(onTap: () {}, child: const Text('행'))),
      ),
    ));
    expect(animatedDecorationOf(tester).boxShadow, GoShadow.elevated);

    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(GoCard)));
    await tester.pump();
    expect(animatedDecorationOf(tester).boxShadow, GoShadow.pressed);
    await gesture.up();
  });

  testWidgets('누를 수 없는 카드는 눌린 척하지 않는다', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: GoCard(child: Text('행')))),
    ));
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(GoCard)));
    await tester.pump();
    expect(animatedDecorationOf(tester).boxShadow, GoShadow.card);
    await gesture.up();
  });

  testWidgets('면은 순백이 아니라 종이와 같은 색상을 쓴다', (tester) async {
    // 순백(#FFFFFF)은 따뜻한 페이퍼 위에서 "차가운 구멍"으로 읽힌다.
    // 이 규칙이 깨지면 화면 전체의 인상이 조용히 무너진다
    expect(GoColors.surface, isNot(const Color(0xFFFFFFFF)));
    expect(GoColors.surface.r, greaterThan(GoColors.surface.b),
        reason: '면은 파랑보다 빨강이 많아야 — 즉 따뜻해야 — 종이와 어울린다');
  });
}
