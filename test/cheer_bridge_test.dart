import 'package:flutter_test/flutter_test.dart';
import 'package:goingon/services/cheer/cheer.dart';

Cheer _c(String id, String from, int minutesAgo,
        {CheerStatus status = CheerStatus.queued}) =>
    Cheer(
      id: id,
      fromUid: from,
      toUid: 'me',
      status: status,
      createdAt: DateTime(2026, 8, 23, 12).subtract(Duration(minutes: minutesAgo)),
    );

/// 이월의 규칙을 지키는 테스트.
///
/// 틀리면 조용히 나쁘다 — 전부 틀면 출발선이 알림 폭탄이 되고, 묶는 걸
/// 잘못하면 한 사람이 세 자리를 차지해 나머지가 영영 밀린다.
void main() {
  group('무엇을 들려줄 것인가', () {
    test('같은 사람의 것은 가장 최근 하나로 묶인다', () {
      final picked = CheerBridge.pick([
        _c('a', '지수', 30),
        _c('b', '지수', 10),
        _c('c', '민재', 20),
      ]);
      expect(picked.map((c) => c.id), ['c', 'b']);
    });

    test('먼저 기다린 사람이 먼저다', () {
      final picked = CheerBridge.pick([
        _c('new', '민재', 5),
        _c('old', '지수', 50),
      ]);
      expect(picked.first.fromUid, '지수');
    });

    test('한 번에 셋까지', () {
      final picked = CheerBridge.pick([
        for (var i = 0; i < 6; i++) _c('c$i', 'p$i', 60 - i),
      ]);
      expect(picked.length, CheerBridge.kMaxPerIntro);
    });

    test('이미 들려준 것은 후보가 아니다', () {
      final picked = CheerBridge.pick([
        _c('done', '지수', 30, status: CheerStatus.bridged),
      ]);
      expect(picked, isEmpty);
    });

    test('아무것도 없으면 아무것도 틀지 않는다', () {
      expect(CheerBridge.pick(const []), isEmpty);
    });
  });

  group('문서로 오가는 값', () {
    test('왕복해도 그대로다', () {
      final c = _c('x', '지수', 3);
      final back = Cheer.fromMap('x', c.toMap().cast<String, dynamic>());
      expect(back!.fromUid, '지수');
      expect(back.toUid, 'me');
      expect(back.status, CheerStatus.queued);
      expect(back.createdAt.toUtc(), c.createdAt.toUtc());
    });

    test('모르는 상태는 아직 안 들려준 것으로 본다', () {
      expect(CheerStatus.fromWire('무엇'), CheerStatus.queued);
      expect(CheerStatus.fromWire(null), CheerStatus.queued);
    });
  });
}
