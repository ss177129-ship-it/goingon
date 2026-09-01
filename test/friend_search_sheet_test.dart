import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goingon/widgets/friend_search_sheet.dart';

/// 친구 찾기 시트의 입력 모양.
///
/// 이 시트는 홈에서 버튼을 눌러야 열려서 스크린샷 검증이 어렵다(이 환경은
/// 시뮬레이터 합성 입력이 막혀 있다). 대신 "@가 화면에 실제로 붙어 있는가"를
/// 여기서 고정한다 — 앱이 아이디를 어디서나 @ruty로 보여주는데 검색창만
/// 그렇지 않으면, 본 대로 입력한 사람이 못 찾는다.
void main() {
  Future<void> openSheet(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showFriendSearchSheet(context),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  testWidgets('@가 입력칸 왼쪽에 고정으로 보인다', (tester) async {
    await openSheet(tester);

    expect(find.text('@'), findsOneWidget);
    expect(find.widgetWithText(Scaffold, '친구 찾기'), findsNothing,
        reason: '시트 안에서만 쓰는 제목이라 Scaffold 타이틀이 아니다');
    expect(find.text('친구 찾기'), findsOneWidget);
  });

  testWidgets('아무것도 입력하지 않아도 @는 사라지지 않는다', (tester) async {
    // prefixText였다면 포커스나 입력 여부에 따라 사라진다. 그러면 빈 칸을
    // 보고 "@를 같이 쳐야 하나?"를 다시 고민하게 된다
    await openSheet(tester);
    expect(find.text('@'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'ruty');
    await tester.pump();
    expect(find.text('@'), findsOneWidget);
  });

  testWidgets('입력칸에는 아이디만 남는다 — @는 입력값이 아니다', (tester) async {
    await openSheet(tester);
    await tester.enterText(find.byType(TextField), 'ruty');
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, 'ruty');
  });
}
