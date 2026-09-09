import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goingon/theme.dart';
import 'package:goingon/widgets/avatar_photo.dart';
import 'package:goingon/widgets/pressable.dart';

/// 사진을 눌러 크게 보기. 핵심은 **사진이 없으면 아무 일도 없다**는 것 —
/// 기본 실루엣은 확대해도 볼 것이 없고, 눌리는데 반응이 없는 것보다
/// 애초에 안 눌리는 편이 정직하다.
void main() {
  Future<void> pump(WidgetTester tester, String? url) => tester.pumpWidget(
        MaterialApp(
          theme: GoTheme.light(),
          home: Scaffold(
            body: Center(
              child: AvatarPhotoTap(
                photoUrl: url,
                name: '지수',
                child: const SizedBox(width: 52, height: 52),
              ),
            ),
          ),
        ),
      );

  testWidgets('사진이 없으면 눌리는 껍데기를 씌우지 않는다', (tester) async {
    await pump(tester, null);
    expect(find.byType(Pressable), findsNothing);

    await pump(tester, '');
    expect(find.byType(Pressable), findsNothing);
  });

  testWidgets('사진이 있으면 눌린다', (tester) async {
    await pump(tester, 'https://example.test/a.jpg');
    expect(find.byType(Pressable), findsOneWidget);
  });

  testWidgets('열리는 것은 화면이 아니라 카드 — 이름이 같이 온다',
      (tester) async {
    await pump(tester, 'https://example.test/a.jpg');
    await tester.tap(find.byType(Pressable));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    // 사진만 떠 있으면 누구인지 다시 묻게 된다
    expect(find.text('지수'), findsOneWidget);
  });

  testWidgets('확대된 사진도 화면을 덮지 않는다', (tester) async {
    await pump(tester, 'https://example.test/a.jpg');
    await tester.tap(find.byType(Pressable));
    await tester.pumpAndSettle();

    final screen = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final photo = tester.getSize(find.byType(ClipOval));
    expect(photo.width, lessThan(screen));
    // 260pt 상한 — 큰 기기에서 사진만 계속 커지면 카드가 아니라 뷰어가 된다
    expect(photo.width, lessThanOrEqualTo(260));
    expect(photo.width, greaterThan(52));
  });

  testWidgets('아무 데나 누르면 닫힌다 — 닫기 버튼을 두지 않았다',
      (tester) async {
    await pump(tester, 'https://example.test/a.jpg');
    await tester.tap(find.byType(Pressable));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });
}
