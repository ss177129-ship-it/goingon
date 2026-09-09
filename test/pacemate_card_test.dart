import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goingon/services/invite.dart';
import 'package:goingon/services/session_rules.dart';
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

  testWidgets('최근 기록이 없으면 상태 줄이 통째로 사라진다 — 빈 줄을 남기지 않는다',
      (tester) async {
    await pump(tester, {'uid': 'u1'});
    expect(find.text('지수'), findsOneWidget);
    // 이름과 GO? 말고는 아무 글자도 없다
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    expect(texts, unorderedEquals(['지수', 'GO?']));
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

  group('제안이 오가면 카드의 이야기가 바뀐다', () {
    Invite inv(String status, {bool incoming = false, DateTime? createdAt,
        String? msg}) =>
        Invite.from(
          's1',
          {
            'hostId': incoming ? 'u1' : 'me',
            'guestId': incoming ? 'me' : 'u1',
            'status': status,
            if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt),
            if (msg != null) 'declineMessage': msg,
          },
          'me',
        )!;

    Future<void> pumpInvite(WidgetTester tester, Invite? invite) =>
        tester.pumpWidget(MaterialApp(
          theme: GoTheme.light(),
          home: Scaffold(
            body: PacemateCard(
              user: const {'uid': 'u1'},
              name: '지수',
              invite: invite,
              now: now,
              onOpen: () {},
              onGo: () {},
              onAccept: () {},
              onDecline: () {},
              onCancelInvite: () {},
              onJoin: () {},
              onDismiss: () {},
            ),
          ),
        ));

    testWidgets('답을 기다리는 중에는 GO?가 사라진다 — 같은 사람을 두 번 부르지 않게',
        (tester) async {
      await pumpInvite(tester, inv(SessionRules.invited,
          createdAt: now.subtract(const Duration(minutes: 5))));
      expect(find.text('GO?'), findsNothing);
      expect(find.text('취소'), findsOneWidget);
      expect(find.textContaining('답을 기다리는 중'), findsOneWidget);
      expect(find.textContaining('25분 남음'), findsOneWidget);
    });

    testWidgets('나를 부르고 있으면 답할 두 가지가 선다', (tester) async {
      await pumpInvite(tester,
          inv(SessionRules.invited, incoming: true, createdAt: now));
      expect(find.text('수락'), findsOneWidget);
      expect(find.text('나중에'), findsOneWidget);
      expect(find.text('GO?'), findsNothing);
    });

    testWidgets('수락되면 입장 하나만 남는다', (tester) async {
      await pumpInvite(tester, inv(SessionRules.accepted));
      expect(find.text('입장'), findsOneWidget);
      expect(find.text('준비하러 가요'), findsOneWidget);
    });

    testWidgets('거절 답장은 그대로 보여준다 — 침묵보다 한 줄이 낫다',
        (tester) async {
      await pumpInvite(tester,
          inv(SessionRules.declined, msg: '30분 뒤 어때요?'));
      expect(find.text('"30분 뒤 어때요?"'), findsOneWidget);
      expect(find.text('확인'), findsOneWidget);
    });

    testWidgets('답장이 없는 거절에도 할 말은 있다', (tester) async {
      await pumpInvite(tester, inv(SessionRules.declined));
      expect(find.text('지금은 어렵대요'), findsOneWidget);
    });

    testWidgets('30분이 지나면 문서가 invited여도 만료로 그린다', (tester) async {
      await pumpInvite(tester, inv(SessionRules.invited,
          createdAt: now.subtract(const Duration(minutes: 31))));
      expect(find.text('답이 오지 않았어요'), findsOneWidget);
      expect(find.text('취소'), findsNothing);
    });

    testWidgets('제안이 없으면 평소 카드로 돌아온다', (tester) async {
      await pumpInvite(tester, null);
      expect(find.text('GO?'), findsOneWidget);
    });
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
