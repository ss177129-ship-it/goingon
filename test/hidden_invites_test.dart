import 'package:flutter_test/flutter_test.dart';
import 'package:goingon/services/hidden_invites.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 내가 치운 지난 제안. **문서를 지우는 것이 아니라 내 화면에서 감추는 것**이라,
/// 지켜야 할 것은 하나다 — 앱을 껐다 켜도 그대로일 것.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    HiddenInvites.instance.resetForTest();
  });

  test('치운 것은 앱을 다시 켜도 치워져 있다', () async {
    final h = HiddenInvites.instance;
    await h.load();
    await h.hide(['a', 'b']);
    expect(h.contains('a'), isTrue);

    // 다시 켠 셈 — 메모리를 비우고 저장소에서만 읽는다
    h.resetForTest();
    expect(h.contains('a'), isFalse, reason: '메모리는 비었다');
    await h.load();
    expect(h.contains('a'), isTrue, reason: '저장소에서 돌아와야 한다');
    expect(h.contains('b'), isTrue);
  });

  test('치우지 않은 것은 그대로 보인다', () async {
    final h = HiddenInvites.instance;
    await h.load();
    await h.hide(['a']);
    expect(h.contains('zzz'), isFalse);
  });

  test('같은 것을 두 번 치워도 알림이 두 번 가지 않는다', () async {
    final h = HiddenInvites.instance;
    await h.load();
    var notified = 0;
    void listener() => notified++;
    h.addListener(listener);

    await h.hide(['a']);
    expect(notified, 1);
    await h.hide(['a']);
    expect(notified, 1, reason: '바뀐 것이 없으면 다시 그릴 이유도 없다');
    h.removeListener(listener);
  });

  test('무한정 쌓이지 않는다 — 오래된 것부터 버린다', () async {
    final h = HiddenInvites.instance;
    await h.load();
    await h.hide([for (var i = 0; i < 250; i++) 's$i']);

    h.resetForTest();
    await h.load();
    expect(h.contains('s0'), isFalse, reason: '가장 오래된 것은 버려진다');
    expect(h.contains('s249'), isTrue, reason: '최근 것은 남는다');
  });
}
