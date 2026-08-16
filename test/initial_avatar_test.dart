import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goingon/services/avatar_service.dart';
import 'package:goingon/widgets/initial_avatar.dart';

/// 아바타는 앱에서 가장 많이 반복되는 조각이라(홈·우리·친구 검색·차단 목록·
/// GO? 시트) 여기가 비거나 깨지면 여러 화면이 한꺼번에 무너진다.
/// 프로필 사진이 붙은 뒤에도 "사진이 없거나 실패하면 반드시 첫 글자로
/// 되돌아간다"는 약속이 유지되는지 못 박아 둠.
void main() {
  Future<void> pump(WidgetTester tester, Widget avatar) =>
      tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: avatar))));

  group('InitialAvatar', () {
    testWidgets('사진이 없으면 이름 첫 글자를 그린다', (tester) async {
      await pump(
        tester,
        const InitialAvatar(
            letter: '찬', size: 60, fontSize: 26, borderColor: Colors.black),
      );

      expect(find.text('찬'), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });

    testWidgets('photoUrl이 빈 문자열이면 사진을 띄우지 않는다', (tester) async {
      // 문서에 빈 값이 들어간 계정(옛 데이터, 저장 도중 실패)이 있어도
      // 빈 이미지를 요청하지 않아야 함
      await pump(
        tester,
        const InitialAvatar(
          letter: '찬',
          size: 60,
          fontSize: 26,
          borderColor: Colors.black,
          photoUrl: '',
        ),
      );

      expect(find.text('찬'), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });

    testWidgets('이름이 비어 있으면 emptyIcon으로 대체된다', (tester) async {
      await pump(
        tester,
        const InitialAvatar(
          letter: '',
          size: 60,
          fontSize: 26,
          borderColor: Colors.black,
          emptyIcon: Icons.person_outline,
        ),
      );

      expect(find.byIcon(Icons.person_outline), findsOneWidget);
    });

    testWidgets('photoUrl이 있으면 사진 위젯을 쓰되 받아오기 전엔 첫 글자를 보여준다',
        (tester) async {
      await pump(
        tester,
        const InitialAvatar(
          letter: '찬',
          size: 60,
          fontSize: 26,
          borderColor: Colors.black,
          photoUrl: 'https://example.test/avatars/abc.jpg',
        ),
      );

      expect(find.byType(CachedNetworkImage), findsOneWidget);
      // placeholder가 첫 글자라, 느린 네트워크에서도 자리가 비지 않음
      expect(find.text('찬'), findsOneWidget);
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
