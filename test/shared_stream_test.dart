import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:goingon/services/shared_stream.dart';

/// 홈 탭과 '우리' 탭이 같은 친구 목록을 각각 구독해 Firestore 읽기가 두 배로
/// 나가던 문제를 막는 장치. "구독자가 둘이어도 원본은 하나"가 핵심 계약이라
/// 그것을 직접 센다.
void main() {
  test('구독자가 둘이어도 원본은 한 번만 열린다', () async {
    var created = 0;
    final source = StreamController<int>.broadcast();
    final shared = SharedStream<int>();

    Stream<int> create() {
      created++;
      return source.stream;
    }

    final a = <int>[];
    final b = <int>[];
    final subA = shared.of('me', create).listen(a.add);
    final subB = shared.of('me', create).listen(b.add);

    source.add(1);
    source.add(2);
    await Future<void>.delayed(Duration.zero);

    expect(created, 1, reason: '원본은 한 번만 만들어져야 한다');
    expect(shared.activeSourceCount, 1);
    expect(a, [1, 2]);
    expect(b, [1, 2], reason: '두 구독자 모두 같은 값을 받아야 한다');

    await subA.cancel();
    await subB.cancel();
    await shared.dispose();
    await source.close();
  });

  test('마지막 구독자가 떠나면 원본 구독도 끊긴다', () async {
    final source = StreamController<int>.broadcast();
    final shared = SharedStream<int>();

    final subA = shared.of('me', () => source.stream).listen((_) {});
    final subB = shared.of('me', () => source.stream).listen((_) {});
    expect(shared.activeSourceCount, 1);

    await subA.cancel();
    expect(shared.activeSourceCount, 1, reason: '아직 한 명 남았으면 유지');

    await subB.cancel();
    await Future<void>.delayed(Duration.zero);
    expect(shared.activeSourceCount, 0,
        reason: '화면이 사라진 뒤에도 리스너가 남으면 읽기가 계속 청구된다');

    await shared.dispose();
    await source.close();
  });

  test('모두 떠난 뒤 다시 구독하면 원본을 새로 연다', () async {
    var created = 0;
    final shared = SharedStream<int>();
    final sources = <StreamController<int>>[];

    Stream<int> create() {
      created++;
      final c = StreamController<int>.broadcast();
      sources.add(c);
      return c.stream;
    }

    final first = shared.of('me', create).listen((_) {});
    await first.cancel();
    await Future<void>.delayed(Duration.zero);

    final received = <int>[];
    final second = shared.of('me', create).listen(received.add);
    sources.last.add(9);
    await Future<void>.delayed(Duration.zero);

    expect(created, 2, reason: '끊긴 뒤 재구독하면 원본을 다시 만들어야 한다');
    expect(received, [9], reason: '재구독 후에도 값이 흘러야 한다');

    await second.cancel();
    await shared.dispose();
    for (final c in sources) {
      await c.close();
    }
  });

  test('키가 다르면 서로 다른 원본을 쓴다', () async {
    var created = 0;
    final shared = SharedStream<int>();
    final subs = <StreamSubscription<int>>[];
    final sources = <StreamController<int>>[];

    Stream<int> create() {
      created++;
      final c = StreamController<int>.broadcast();
      sources.add(c);
      return c.stream;
    }

    subs.add(shared.of('a', create).listen((_) {}));
    subs.add(shared.of('b', create).listen((_) {}));

    expect(created, 2);
    expect(shared.activeSourceCount, 2);

    for (final s in subs) {
      await s.cancel();
    }
    await shared.dispose();
    for (final c in sources) {
      await c.close();
    }
  });

  test('원본의 오류가 모든 구독자에게 전달된다', () async {
    final source = StreamController<int>.broadcast();
    final shared = SharedStream<int>();
    final errors = <Object>[];

    final subA = shared.of('me', () => source.stream).listen((_) {},
        onError: errors.add);
    final subB = shared.of('me', () => source.stream).listen((_) {},
        onError: errors.add);

    source.addError('끊김');
    await Future<void>.delayed(Duration.zero);

    // 홈 화면이 오류를 받아 재시도·배너를 띄우는 경로가 살아 있어야 한다
    expect(errors.length, 2);

    await subA.cancel();
    await subB.cancel();
    await shared.dispose();
    await source.close();
  });

  test('늦게 붙은 구독자는 마지막 값을 먼저 받는다', () async {
    // 홈과 '제안' 탭이 같은 목록을 보는데, 두 번째 화면이 다음 변경까지
    // 빈 채로 앉아 있었다 — 카드에는 제안이 떠 있고 탭은 "없어요"였다
    final shared = SharedStream<int>();
    final source = StreamController<int>.broadcast();
    Stream<int> create() => source.stream;

    final first = <int>[];
    final subA = shared.of('k', create).listen(first.add);
    await Future<void>.delayed(Duration.zero);
    source.add(7);
    await Future<void>.delayed(Duration.zero);
    expect(first, [7]);

    final second = <int>[];
    final subB = shared.of('k', create).listen(second.add);
    await Future<void>.delayed(Duration.zero);
    expect(second, [7], reason: '이미 지나간 값이라도 새 구독자는 알아야 한다');

    source.add(9);
    await Future<void>.delayed(Duration.zero);
    expect(first, [7, 9]);
    expect(second, [7, 9]);

    await subA.cancel();
    await subB.cancel();
    await source.close();
  });

  test('모두 떠나면 캐시도 비운다 — 다시 붙을 때 낡은 값을 주지 않게', () async {
    final shared = SharedStream<int>();
    var created = 0;
    final source = StreamController<int>.broadcast();
    Stream<int> create() {
      created++;
      return source.stream;
    }

    final sub = shared.of('k', create).listen((_) {});
    await Future<void>.delayed(Duration.zero);
    source.add(1);
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    await Future<void>.delayed(Duration.zero);

    final again = <int>[];
    final sub2 = shared.of('k', create).listen(again.add);
    await Future<void>.delayed(Duration.zero);
    expect(again, isEmpty, reason: '끊긴 뒤의 값은 더 이상 지금이 아니다');
    expect(created, 2);

    await sub2.cancel();
    await source.close();
  });
}
