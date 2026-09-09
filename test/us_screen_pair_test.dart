import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 겹쳐 놓인 아바타 짝. **음수 margin을 쓰면 Flutter가 assert로 막는다.**
///
/// 이걸 실제로 밟은 적이 있다 — '우리' 탭의 짝 아바타가 `left: -12`로
/// 겹쳐 있었는데, 함께 달린 기록이 없는 동안에는 그 위젯이 그려지지 않아
/// 몇 달을 조용했다. 첫 완주가 생기는 순간부터 매 프레임 예외가 났고,
/// RootScreen이 IndexedStack이라 다른 탭에 있어도 함께 터졌다.
///
/// 화면 전체를 띄우려면 Firebase가 필요해서, 여기서는 **겹침을 만드는
/// 방식 자체**를 지킨다: 자리를 차지하는 겹침은 Stack으로 만든다.
void main() {
  test('음수 margin은 Container가 거부한다 — 겹침의 수단이 될 수 없다', () {
    // 그리는 시점이 아니라 **만드는 시점**에 터진다. 그래서 코드 경로가
    // 처음 실행되는 순간까지 조용히 숨어 있었다
    expect(
        () => Container(margin: const EdgeInsets.only(left: -12)),
        throwsA(isA<AssertionError>()),
        reason: '이 방식이 조용히 통과하면 같은 버그가 다시 들어온다');
  });

  testWidgets('Stack으로 겹치면 자리도 겹친 만큼만 차지한다', (tester) async {
    const size = 30.0, overlap = 12.0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            key: const ValueKey('pair'),
            width: size * 2 - overlap,
            height: size,
            child: Stack(children: [
              Container(
                  key: const ValueKey('a'),
                  width: size,
                  height: size,
                  color: const Color(0xFF000000)),
              Positioned(
                left: size - overlap,
                child: Container(
                    key: const ValueKey('b'),
                    width: size,
                    height: size,
                    color: const Color(0xFF888888)),
              ),
            ]),
          ),
        ),
      ),
    ));

    expect(tester.takeException(), isNull);
    final a = tester.getTopLeft(find.byKey(const ValueKey('a')));
    final b = tester.getTopLeft(find.byKey(const ValueKey('b')));
    expect(b.dx - a.dx, size - overlap, reason: '두 번째가 12만큼 파고든다');
    // 둘이 따로 서면 60을 먹는데, 겹쳐서 48만 쓴다
    expect(tester.getSize(find.byKey(const ValueKey('pair'))).width,
        size * 2 - overlap);
  });
}
