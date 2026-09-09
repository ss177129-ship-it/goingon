import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goingon/theme.dart';
import 'package:goingon/widgets/pacemate_card.dart';

/// 홈의 주인공 카드. 위계를 바꾼 것이 이 위젯이라, "무엇이 카드 안에 있고
/// 무엇이 없는가"가 곧 결정 내용이다.
void main() {
  // 2026-09-09는 수요일 — 그 주 월요일은 2026-09-07
  final now = DateTime(2026, 9, 9, 14);
  const thisWeek = '2026-09-07';

  Future<void> pump(WidgetTester tester, Map<String, dynamic> user) =>
      tester.pumpWidget(MaterialApp(
        theme: GoTheme.light(),
        home: Scaffold(
          body: PacemateCard(
            user: user,
            name: '지수',
            now: now,
            onOpen: () {},
            onGo: () {},
          ),
        ),
      ));

  testWidgets('이름과 상태 한 줄이 함께 있다 — 점만으로 뜻을 전하지 않는다', (tester) async {
    await pump(tester, {'uid': 'u1', 'lastRunWeek': thisWeek});

    expect(find.text('지수'), findsOneWidget);
    expect(find.text('이번 주 달렸어요'), findsOneWidget);
  });

  testWidgets('주 행동 GO?는 카드 안에 남아 있다', (tester) async {
    await pump(tester, {'uid': 'u1'});
    expect(find.text('GO?'), findsOneWidget);
  });

  testWidgets('최근 기록이 없으면 상태 점을 찍지 않는다', (tester) async {
    // 회색 점은 상태가 아니라 고장으로 읽히고, 목록에 뜻 없는 동그라미만
    // 늘어난다. 없을 때는 아무것도 그리지 않는 쪽이 정직하다
    await pump(tester, {'uid': 'u1'});
    expect(find.byKey(PacemateCard.dotKey), findsNothing);

    await pump(tester, {'uid': 'u1', 'lastRunWeek': thisWeek});
    expect(find.byKey(PacemateCard.dotKey), findsOneWidget);
  });

  testWidgets('카드 전체가 눌린다 — ⋯ 하나가 유일한 입구였던 자리', (tester) async {
    var opened = 0;
    await tester.pumpWidget(MaterialApp(
      theme: GoTheme.light(),
      home: Scaffold(
        body: PacemateCard(
          user: const {'uid': 'u1'},
          name: '지수',
          now: now,
          onOpen: () => opened++,
          onGo: () {},
        ),
      ),
    ));

    await tester.tap(find.text('지수'));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  testWidgets('다른 사람에게 보내는 중이면 이 카드의 GO?도 잠긴다', (tester) async {
    var went = 0;
    await tester.pumpWidget(MaterialApp(
      theme: GoTheme.light(),
      home: Scaffold(
        body: PacemateCard(
          user: const {'uid': 'u1'},
          name: '지수',
          now: now,
          goEnabled: false,
          onOpen: () {},
          onGo: () => went++,
        ),
      ),
    ));

    await tester.tap(find.text('GO?'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(went, 0);
  });
}
