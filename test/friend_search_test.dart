import 'package:flutter_test/flutter_test.dart';
import 'package:goingon/services/friend_service.dart';

/// 아이디 검색어 정규화.
///
/// 저장 쪽은 `^[a-z0-9_]{3,20}$`만 통과시키므로(닉네임 화면·프로필 편집),
/// 검색 쪽이 같은 형태로 맞춰주지 않으면 **화면에 보이는 그대로 입력한 사람이
/// 못 찾는다.** 앱은 아이디를 어디서나 `@ruty`로 보여준다.
void main() {
  String n(String raw) => FriendService.normalizeUsername(raw);

  test('앞의 @를 뗀다 — 화면에 보이는 그대로 입력해도 찾아져야 한다', () {
    // 2026-08-16 실제 제보: "@ruty"로 검색하니 그런 아이디가 없다고 했다
    expect(n('@ruty'), 'ruty');
    expect(n('@@ruty'), 'ruty');
  });

  test('대소문자를 가리지 않는다', () {
    expect(n('RUTY'), 'ruty');
    expect(n('Ruty'), 'ruty');
  });

  test('앞뒤와 가운데 공백을 지운다', () {
    // 복사해 붙이면 "@ ruty"처럼 끼어드는 일이 흔하다
    expect(n('  ruty  '), 'ruty');
    expect(n('@ ruty'), 'ruty');
    expect(n('ru ty'), 'ruty');
  });

  test('아이디 가운데의 밑줄과 숫자는 건드리지 않는다', () {
    expect(n('@big_man2'), 'big_man2');
  });

  test('@만 입력하면 빈 문자열 — 호출부가 조회 없이 끝낸다', () {
    expect(n('@'), '');
    expect(n('   '), '');
  });
}
