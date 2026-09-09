import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goingon/services/avatar_service.dart';
import 'package:goingon/theme.dart';
import 'package:goingon/widgets/go_avatar.dart';

/// 아바타는 앱에서 가장 많이 반복되는 조각이라(홈·우리·친구 검색·차단 목록·
/// GO? 시트) 여기가 비거나 깨지면 여러 화면이 한꺼번에 무너진다.
/// "사진이 없거나 실패하면 반드시 실루엣으로 되돌아간다"는 약속을 못 박아 둠.
void main() {
  Future<void> pump(WidgetTester tester, Widget avatar) =>
      tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: avatar))));

  Finder silhouette() => find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is AvatarSilhouettePainter);

  group('GoAvatar', () {
    testWidgets('사진이 없으면 실루엣을 그린다', (tester) async {
      await pump(tester, const GoAvatar(size: 60, roleColor: Colors.black));

      expect(silhouette(), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });

    testWidgets('photoUrl이 빈 문자열이면 사진을 띄우지 않는다', (tester) async {
      // 문서에 빈 값이 들어간 계정(옛 데이터, 저장 도중 실패)이 있어도
      // 빈 이미지를 요청하지 않아야 함
      await pump(
        tester,
        const GoAvatar(size: 60, roleColor: Colors.black, photoUrl: ''),
      );

      expect(silhouette(), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });

    testWidgets('photoUrl이 있으면 사진 위젯을 쓰되 받아오기 전엔 실루엣을 보여준다',
        (tester) async {
      await pump(
        tester,
        const GoAvatar(
          size: 60,
          roleColor: Colors.black,
          photoUrl: 'https://example.test/avatars/abc.jpg',
        ),
      );

      expect(find.byType(CachedNetworkImage), findsOneWidget);
      // placeholder가 실루엣이라, 느린 네트워크에서도 자리가 비지 않음
      expect(silhouette(), findsOneWidget);
    });

    testWidgets('관계색을 넘기면 실루엣은 그 색의 55%', (tester) async {
      // 알파는 위젯이 정해서 넘긴다 — 페인터는 받은 색을 그대로 칠한다
      await pump(tester, const GoAvatar(size: 60, roleColor: Colors.red));

      final paint = tester.widget<CustomPaint>(silhouette());
      expect((paint.painter as AvatarSilhouettePainter).color,
          Colors.red.withValues(alpha: .55));
    });

    testWidgets('관계색이 없으면 라임 기본 프로필 — 면은 라임, 실루엣은 올리브',
        (tester) async {
      // 명부·목록·내 프로필의 아바타. 사람마다 색이 갈리지 않는다
      await pump(tester, const GoAvatar(size: 60));

      final paint = tester.widget<CustomPaint>(silhouette());
      expect((paint.painter as AvatarSilhouettePainter).color,
          GoRoles.light.avatarDefault.fg);

      final box = tester.widget<Container>(find.descendant(
          of: find.byType(GoAvatar), matching: find.byType(Container)));
      expect((box.decoration as BoxDecoration).color,
          GoRoles.light.avatarDefault.bg);
    });

    testWidgets('기본 프로필도 사진이 있으면 사진이 이긴다', (tester) async {
      await pump(
        tester,
        const GoAvatar(size: 60, photoUrl: 'https://example.test/a.jpg'),
      );

      expect(find.byType(CachedNetworkImage), findsOneWidget);
    });
  });

  group('AvatarService.contentTypeOf', () {
    // Storage 규칙이 contentType을 image/*로 검사하므로 여기가 틀리면
    // 업로드가 통째로 권한 거부됨
    test('png 원본은 image/png로 올린다', () {
      expect(AvatarService.contentTypeOf('IMG_0001.PNG'), 'image/png');
      expect(AvatarService.contentTypeOf('shot.png'), 'image/png');
    });

    test('그 외에는 image/jpeg', () {
      expect(AvatarService.contentTypeOf('IMG_0002.jpg'), 'image/jpeg');
      expect(AvatarService.contentTypeOf('scaled_photo.jpeg'), 'image/jpeg');
      expect(AvatarService.contentTypeOf('no_extension'), 'image/jpeg');
    });
  });
}
