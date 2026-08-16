import 'package:flutter_test/flutter_test.dart';
import 'package:goingon/services/app_version_gate.dart';

/// 낡은 빌드를 막는 판단.
///
/// 이 판단이 틀리면 앱이 통째로 열리지 않는다. 그래서 **막는 쪽으로 틀리지
/// 않는 것**이 정확도보다 중요하다 — 서버가 아무 말도 안 했거나 읽지
/// 못했으면 무조건 통과다.
void main() {
  bool blocked(int current, int? min) =>
      AppVersionGate.isBlocked(currentBuild: current, minBuild: min);

  test('최소 번호보다 낮으면 막는다', () {
    expect(blocked(9, 10), isTrue);
    expect(blocked(1, 11), isTrue);
  });

  test('같거나 높으면 통과', () {
    expect(blocked(10, 10), isFalse);
    expect(blocked(11, 10), isFalse);
  });

  test('서버가 아무 말도 안 했으면 통과 — 문서나 필드가 없는 경우', () {
    // 설정 문서를 만들기 전이거나 실수로 지운 상태에서 앱이 잠기면 안 된다
    expect(blocked(1, null), isFalse);
  });

  test('0이나 음수를 적어둬도 아무도 막히지 않는다', () {
    // 실수로 0을 넣는 것이 "전부 잠금"이 되면 사고가 크다
    expect(blocked(1, 0), isFalse);
    expect(blocked(1, -5), isFalse);
  });
}
