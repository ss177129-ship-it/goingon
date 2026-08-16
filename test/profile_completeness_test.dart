import 'package:flutter_test/flutter_test.dart';
import 'package:goingon/services/auth_service.dart';

/// "프로필이 완성됐는가" 판정.
///
/// 이 판정이 문서 존재 여부였을 때, **아이디 없는 계정이 그대로 홈까지
/// 들어갔다.** 그런 사람은 친구 찾기에 영영 안 잡힌다 — 실제로 계정 7개 중
/// 6개가 아이디 없이 쓰이고 있었다(2026-08-16 확인). 로그인 분기가 이 함수
/// 하나에 달려 있어서 여기서 고정한다.
void main() {
  test('이름과 아이디가 모두 있어야 완성', () {
    expect(
        AuthService.isProfileComplete({'name': '빅맨', 'username': 'ruty'}),
        isTrue);
  });

  test('아이디가 없으면 미완성 — 검색으로 찾을 수 없는 상태다', () {
    expect(AuthService.isProfileComplete({'name': '빅맨'}), isFalse);
    expect(
        AuthService.isProfileComplete({'name': '빅맨', 'username': ''}), isFalse);
    expect(AuthService.isProfileComplete({'name': '빅맨', 'username': '   '}),
        isFalse);
  });

  test('이름이 없으면 미완성 — 상대 화면에 빈칸이 뜬다', () {
    expect(AuthService.isProfileComplete({'username': 'ruty'}), isFalse);
    expect(AuthService.isProfileComplete({'name': '  ', 'username': 'ruty'}),
        isFalse);
  });

  test('문서 자체가 없으면 미완성', () {
    expect(AuthService.isProfileComplete(null), isFalse);
    expect(AuthService.isProfileComplete({}), isFalse);
  });

  test('다른 필드가 아무리 많아도 둘이 없으면 소용없다', () {
    // 러닝 기록만 쌓이고 아이디는 없는 계정이 실제로 있었다
    expect(
        AuthService.isProfileComplete(
            {'name': '가파링', 'totalRuns': 12, 'monthKm': 30.5}),
        isFalse);
  });
}
