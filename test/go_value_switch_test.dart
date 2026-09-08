import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goingon/widgets/go_value_switch.dart';

void main() {
  Widget host(Object? value, String text) => MaterialApp(
        home: Scaffold(
          body: Center(child: GoValueSwitch(value: value, child: Text(text))),
        ),
      );

  testWidgets('값이 바뀌면 옛 값과 새 값이 잠깐 겹쳤다가 새 값만 남는다', (tester) async {
    await tester.pumpWidget(host(0, '0.0'));
    await tester.pumpAndSettle();
    expect(find.text('0.0'), findsOneWidget);

    await tester.pumpWidget(host(3, '3.2'));
    await tester.pump(const Duration(milliseconds: 50));
    // 교차 중 — 둘 다 트리에 있다
    expect(find.text('0.0'), findsOneWidget);
    expect(find.text('3.2'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('0.0'), findsNothing);
    expect(find.text('3.2'), findsOneWidget);
  });

  testWidgets('같은 값이 다시 그려지면 아무 일도 없다', (tester) async {
    await tester.pumpWidget(host('a', '하나'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(host('a', '하나'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('하나'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(GoValueSwitch), matching: find.byType(FadeTransition)),
        findsOneWidget,
        reason: '새 전환이 시작되지 않아 트리에 하나만 있다');
  });

  testWidgets('동작 줄이기가 켜져 있으면 교차 없이 바로 바뀐다', (tester) async {
    Widget reduced(Object? v, String t) => MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: host(v, t),
        );
    await tester.pumpWidget(reduced(0, '0.0'));
    await tester.pump();
    await tester.pumpWidget(reduced(1, '1.0'));
    await tester.pump();
    expect(find.text('0.0'), findsNothing);
    expect(find.text('1.0'), findsOneWidget);
  });
}
