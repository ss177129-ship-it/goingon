import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goingon/services/session_rules.dart';

/// 세션 상태 전이 규칙 (2026-09-09 개편).
///
/// ```
/// invited ──수락──▶ accepted ──둘 다 ready──▶ running ──▶ finished
///    │                  │
///    ├─거절─▶ declined   └─나감─▶ cancelled
///    └─만료─▶ expired
/// ```
///
/// 전이 자체보다 **하지 말아야 할 것**이 중요하다 — 취소된 세션이 되살아나거나,
/// 함께 출발한 시각이 덮어써지거나, 재시도로 집계가 두 번 오르는 일. 전부
/// 화면으로 재현하기 어려워 그동안 검증되지 못했던 것들이다.
void main() {
  const me = 'me';
  const you = 'you';
  final now = DateTime.utc(2026, 8, 16, 12);

  Map<String, dynamic> session({
    String status = SessionRules.invited,
    DateTime? startedAt,
    Map<String, dynamic>? results,
    Map<String, dynamic>? ready,
  }) =>
      {
        'hostId': me,
        'guestId': you,
        'status': status,
        if (ready != null) 'ready': ready,
        if (startedAt != null) 'startedAt': Timestamp.fromDate(startedAt),
        if (results != null) 'results': results,
      };

  group('수락과 거절 — 답할 수 있는 것은 초대뿐', () {
    test('invited면 수락된다', () {
      expect(SessionRules.accept(session())?['status'], SessionRules.accepted);
    });

    test('이미 수락했거나 끝난 것은 다시 수락되지 않는다', () {
      for (final st in [
        SessionRules.accepted,
        SessionRules.running,
        SessionRules.finished,
        SessionRules.declined,
        SessionRules.expired,
        SessionRules.cancelled,
      ]) {
        expect(SessionRules.accept(session(status: st)), isNull, reason: st);
      }
    });

    test('거절은 한 줄 답장을 담을 수 있고, 없어도 성립한다', () {
      expect(SessionRules.decline(session())?['status'], SessionRules.declined);
      expect(SessionRules.decline(session())!.containsKey('declineMessage'),
          isFalse);
      expect(SessionRules.decline(session(), message: '오늘은 어려워')![
          'declineMessage'], '오늘은 어려워');
      // 빈 문자열은 답장이 아니다
      expect(SessionRules.decline(session(), message: '')!
          .containsKey('declineMessage'), isFalse);
    });

    test('만료는 답을 기다리는 중일 때만', () {
      expect(SessionRules.expire(session())?['status'], SessionRules.expired);
      expect(SessionRules.expire(session(status: SessionRules.accepted)),
          isNull);
    });
  });

  group('준비 완료', () {
    test('내 항목만 켠다 — status는 건드리지 않는다', () {
      // 전에는 여기서 status를 'ready'로 올렸다. 한 사람만 눌러도 바뀌는
      // 값이라 "둘 다 준비됐다"는 뜻이 될 수 없었고, 그래서 보낸 사람이
      // 상대의 수락 여부와 무관하게 준비 화면으로 넘어갔다
      final u = SessionRules.ready(session(status: SessionRules.accepted), me)!;
      expect(u, {'ready.$me': true});
      expect(u.containsKey('status'), isFalse);
    });

    test('수락 전에는 준비할 수 없다', () {
      expect(SessionRules.ready(session(), me), isNull);
    });

    test('취소·거절된 세션은 되살아나지 않는다', () {
      for (final st in [SessionRules.cancelled, SessionRules.declined,
          SessionRules.expired, SessionRules.finished]) {
        expect(SessionRules.ready(session(status: st), me), isNull,
            reason: st);
      }
    });

    test('문서가 없어도 터지지 않는다', () {
      expect(SessionRules.ready(null, me), isNull);
    });

    test('취소하면 내 항목이 꺼진다 — 상대가 그것을 봐야 한다', () {
      // 전에는 화면만 뒤로 돌리고 문서는 그대로 뒀다. 상대에게는 내가
      // 여전히 준비완료였고, 상대가 준비하는 순간 아무도 취소하지 않은
      // 러닝이 시작됐다
      final u = SessionRules.unready(session(status: SessionRules.accepted), me)!;
      expect(u, {'ready.$me': false});
    });

    test('살아 있지 않은 세션에서는 취소도 없다', () {
      for (final st in [SessionRules.invited, SessionRules.running,
          SessionRules.cancelled]) {
        expect(SessionRules.unready(session(status: st), me), isNull,
            reason: st);
      }
    });
  });

  group('둘 다 준비됐는가 — 출발의 유일한 조건', () {
    test('한 명만으로는 아니다', () {
      expect(SessionRules.bothReady(session(ready: {me: true})), isFalse);
      expect(SessionRules.bothReady(session(ready: {you: true})), isFalse);
    });

    test('둘 다여야 참', () {
      expect(SessionRules.bothReady(session(ready: {me: true, you: true})),
          isTrue);
    });

    test('맵이 없거나 이상해도 터지지 않는다', () {
      expect(SessionRules.bothReady(session()), isFalse);
      expect(SessionRules.bothReady(null), isFalse);
      expect(SessionRules.bothReady({...session(), 'ready': '이상한 값'}),
          isFalse);
    });
  });

  group('출발', () {
    test('처음 출발하면 startedAt을 찍는다', () {
      final u = SessionRules.start(session(status: SessionRules.accepted))!;
      expect(u['status'], 'running');
      expect(u.containsKey('startedAt'), isTrue);
    });

    test('이미 찍혀 있으면 덮어쓰지 않는다', () {
      // 양쪽 클라이언트가 각자 출발을 부르므로, 덮어쓰면 함께 출발한 시각이
      // 나중 사람 기준으로 밀려 두 사람의 시작점이 어긋난다
      final u = SessionRules.start(
          session(status: SessionRules.accepted, startedAt: now.subtract(const Duration(minutes: 3))))!;
      expect(u['status'], 'running');
      expect(u.containsKey('startedAt'), isFalse,
          reason: '먼저 찍힌 값을 유지해야 한다');
    });

    test('수락 전에는 출발하지 않는다', () {
      expect(SessionRules.start(session()), isNull);
    });

    test('취소된 세션은 출발하지 않는다', () {
      expect(SessionRules.start(session(status: SessionRules.cancelled)), isNull);
    });
  });

  group('결과 제출', () {
    test('첫 제출이면 isFirstSubmit이 참', () {
      final o = SessionRules.submit(session(status: 'running'), me,
          seconds: 1800, km: 5.2, kcal: 300);
      expect(o.isFirstSubmit, isTrue);
      expect(o.update['results.$me'],
          {'seconds': 1800, 'km': 5.2, 'kcal': 300});
    });

    test('재제출이면 isFirstSubmit이 거짓 — 집계가 두 번 오르지 않게', () {
      // 제출이 실패해 재시도하면 같은 러닝이 두 번 올라온다. 그때마다 이번 달
      // 거리와 횟수가 또 더해지면 기록이 부풀려진다
      final data = session(status: 'running', results: {
        me: {'seconds': 1800, 'km': 5.2, 'kcal': 300}
      });
      final o = SessionRules.submit(data, me, seconds: 1810, km: 5.3, kcal: 305);
      expect(o.isFirstSubmit, isFalse);
      expect(o.update['results.$me'],
          {'seconds': 1810, 'km': 5.3, 'kcal': 305},
          reason: '값 자체는 최신으로 갱신된다');
    });

    test('혼자 냈으면 세션을 닫지 않는다', () {
      final o = SessionRules.submit(session(status: 'running'), me,
          seconds: 1800, km: 5.2, kcal: 300);
      expect(o.update.containsKey('status'), isFalse);
    });

    test('둘 다 냈으면 finished로 닫는다', () {
      final data = session(status: 'running', results: {
        you: {'seconds': 1700, 'km': 4.9, 'kcal': 280}
      });
      final o = SessionRules.submit(data, me,
          seconds: 1800, km: 5.2, kcal: 300);
      expect(o.update['status'], 'finished');
      expect(o.isFirstSubmit, isTrue, reason: '상대 것만 있었으니 내 것은 첫 제출');
    });

    test('mood는 있을 때만 담는다', () {
      final without = SessionRules.submit(session(), me,
          seconds: 60, km: .2, kcal: 10);
      expect((without.update['results.$me'] as Map).containsKey('mood'), isFalse);
      final with_ = SessionRules.submit(session(), me,
          seconds: 60, km: .2, kcal: 10, mood: '상쾌했어요');
      expect((with_.update['results.$me'] as Map)['mood'], '상쾌했어요');
    });
  });

  group('그만두기', () {
    test('시작 전(invited/accepted)이면 취소된다', () {
      expect(SessionRules.cancel(session())?['status'], SessionRules.cancelled);
      expect(SessionRules.cancel(session(status: SessionRules.accepted))?['status'],
          SessionRules.cancelled);
    });

    test('달리는 중이거나 끝난 세션은 취소하지 않는다', () {
      // 오래된 정리 로직이 뒤늦게 도착해 진행 중인 러닝을 취소하면
      // 기록이 통째로 날아간다
      for (final st in [SessionRules.running, SessionRules.finished,
          SessionRules.declined, SessionRules.expired, SessionRules.cancelled]) {
        expect(SessionRules.cancel(session(status: st)), isNull, reason: st);
      }
    });

    test('취소는 답장을 담지 않는다 — 그건 거절의 것이다', () {
      expect(SessionRules.cancel(session())!.containsKey('declineMessage'),
          isFalse);
    });
  });

  group('요청 수명', () {
    test('30분 이내면 살아 있다', () {
      final t = Timestamp.fromDate(now.subtract(const Duration(minutes: 29)));
      expect(SessionRules.isRequestAlive(t, now), isTrue);
    });

    test('30분이 지나면 죽은 요청', () {
      final t = Timestamp.fromDate(now.subtract(const Duration(minutes: 31)));
      expect(SessionRules.isRequestAlive(t, now), isFalse);
    });

    test('createdAt이 없으면 살아 있다고 보지 않는다', () {
      // 서버 시각이 아직 안 찍힌 상태 — 판단을 보류한다
      expect(SessionRules.isRequestAlive(null, now), isFalse);
    });
  });

  group('멈춰 있는 running 세션', () {
    test('내 결과가 있고 24시간이 지났으면 사실상 끝난 것', () {
      // 상대가 영영 마치지 않아도 내 기록은 '우리' 탭에 남아야 한다
      final data = session(
        status: 'running',
        startedAt: now.subtract(const Duration(hours: 25)),
        results: {me: {'seconds': 1800, 'km': 5.0, 'kcal': 300}},
      );
      expect(SessionRules.isStaleRunning(data, me, now), isTrue);
    });

    test('내 결과가 없으면 아니다', () {
      final data = session(
        status: 'running',
        startedAt: now.subtract(const Duration(hours: 25)),
        results: {you: {'seconds': 1800, 'km': 5.0, 'kcal': 300}},
      );
      expect(SessionRules.isStaleRunning(data, me, now), isFalse);
    });

    test('24시간이 안 지났으면 아니다 — 아직 달리는 중일 수 있다', () {
      final data = session(
        status: 'running',
        startedAt: now.subtract(const Duration(hours: 23)),
        results: {me: {'seconds': 1800, 'km': 5.0, 'kcal': 300}},
      );
      expect(SessionRules.isStaleRunning(data, me, now), isFalse);
    });

    test('startedAt이 없으면 아니다', () {
      final data = session(status: 'running', results: {
        me: {'seconds': 1800, 'km': 5.0, 'kcal': 300}
      });
      expect(SessionRules.isStaleRunning(data, me, now), isFalse);
    });
  });

  group('전체 흐름', () {
    test('invited → accepted → running → finished가 이어진다', () {
      var data = session();

      data = {...data, ...SessionRules.accept(data)!};
      expect(data['status'], SessionRules.accepted);

      // 한 사람이 준비해도 status는 그대로다
      data = {...data, 'ready': {me: true}};
      expect(data['status'], SessionRules.accepted);
      expect(SessionRules.bothReady(data), isFalse);

      data = {...data, 'ready': {me: true, you: true}};
      expect(SessionRules.bothReady(data), isTrue);

      final s = SessionRules.start(data)!;
      data = {...data, 'status': s['status'],
          'startedAt': Timestamp.fromDate(now)};
      expect(data['status'], SessionRules.running);

      final first =
          SessionRules.submit(data, me, seconds: 1800, km: 5.0, kcal: 300);
      expect(first.update.containsKey('status'), isFalse, reason: '아직 혼자');
      data = {...data, 'results': {me: first.update['results.$me']}};

      final second =
          SessionRules.submit(data, you, seconds: 1750, km: 4.8, kcal: 290);
      expect(second.update['status'], SessionRules.finished);

      // 끝난 세션은 취소되지 않는다
      expect(SessionRules.cancel({...data, 'status': SessionRules.finished}),
          isNull);
    });

    test('거절로 끝난 세션은 어느 쪽으로도 못 간다', () {
      final dead = session(status: SessionRules.declined);
      expect(SessionRules.accept(dead), isNull);
      expect(SessionRules.ready(dead, me), isNull);
      expect(SessionRules.start(dead), isNull);
      expect(SessionRules.cancel(dead), isNull);
      expect(SessionRules.expire(dead), isNull);
    });
  });
}
