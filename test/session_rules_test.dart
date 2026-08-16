import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goingon/services/session_rules.dart';

/// 세션 상태 전이(waiting → ready → running → finished) 규칙.
///
/// 전이 자체보다 **하지 말아야 할 것**이 중요하다 — 취소된 세션이 되살아나거나,
/// 함께 출발한 시각이 덮어써지거나, 재시도로 집계가 두 번 오르는 일. 전부
/// 화면으로 재현하기 어려워 그동안 검증되지 못했던 것들이다.
void main() {
  const me = 'me';
  const you = 'you';
  final now = DateTime.utc(2026, 8, 16, 12);

  Map<String, dynamic> session({
    String status = 'waiting',
    DateTime? startedAt,
    Map<String, dynamic>? results,
  }) =>
      {
        'hostId': me,
        'guestId': you,
        'status': status,
        if (startedAt != null) 'startedAt': Timestamp.fromDate(startedAt),
        if (results != null) 'results': results,
      };

  group('준비 완료', () {
    test('내 항목만 켜고 상태를 ready로 올린다', () {
      final u = SessionRules.ready(session(), me);
      expect(u, {'ready.$me': true, 'status': 'ready'});
    });

    test('취소된 세션은 되살아나지 않는다', () {
      // 상대가 취소한 직후 내가 준비를 누르면, 아무도 원하지 않는 러닝이
      // 시작될 수 있다
      expect(SessionRules.ready(session(status: 'cancelled'), me), isNull);
    });

    test('문서가 없어도 터지지 않는다', () {
      expect(SessionRules.ready(null, me), isNotNull);
    });
  });

  group('출발', () {
    test('처음 출발하면 startedAt을 찍는다', () {
      final u = SessionRules.start(session(status: 'ready'))!;
      expect(u['status'], 'running');
      expect(u.containsKey('startedAt'), isTrue);
    });

    test('이미 찍혀 있으면 덮어쓰지 않는다', () {
      // 양쪽 클라이언트가 각자 출발을 부르므로, 덮어쓰면 함께 출발한 시각이
      // 나중 사람 기준으로 밀려 두 사람의 시작점이 어긋난다
      final u = SessionRules.start(
          session(status: 'ready', startedAt: now.subtract(const Duration(minutes: 3))))!;
      expect(u['status'], 'running');
      expect(u.containsKey('startedAt'), isFalse,
          reason: '먼저 찍힌 값을 유지해야 한다');
    });

    test('취소된 세션은 출발하지 않는다', () {
      expect(SessionRules.start(session(status: 'cancelled')), isNull);
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

  group('취소', () {
    test('시작 전(waiting/ready)이면 취소된다', () {
      expect(SessionRules.cancel(session(status: 'waiting'))?['status'],
          'cancelled');
      expect(SessionRules.cancel(session(status: 'ready'))?['status'],
          'cancelled');
    });

    test('달리는 중이거나 끝난 세션은 취소하지 않는다', () {
      // 오래된 정리 로직이 뒤늦게 도착해 진행 중인 러닝을 취소하면
      // 기록이 통째로 날아간다
      expect(SessionRules.cancel(session(status: 'running')), isNull);
      expect(SessionRules.cancel(session(status: 'finished')), isNull);
    });

    test('거절 메시지는 있을 때만 담는다', () {
      expect(SessionRules.cancel(session())!.containsKey('declineMessage'),
          isFalse);
      expect(
          SessionRules.cancel(session(), declineMessage: '오늘은 어려워')![
              'declineMessage'],
          '오늘은 어려워');
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
    test('waiting → ready → running → finished가 이어진다', () {
      var data = session();

      final r = SessionRules.ready(data, me)!;
      data = {...data, 'status': r['status'], 'ready.$me': true};
      expect(data['status'], 'ready');

      final s = SessionRules.start(data)!;
      data = {...data, 'status': s['status'], 'startedAt': Timestamp.fromDate(now)};
      expect(data['status'], 'running');

      final first = SessionRules.submit(data, me, seconds: 1800, km: 5.0, kcal: 300);
      expect(first.update.containsKey('status'), isFalse, reason: '아직 혼자');
      data = {...data, 'results': {me: first.update['results.$me']}};

      final second = SessionRules.submit(data, you, seconds: 1750, km: 4.8, kcal: 290);
      expect(second.update['status'], 'finished');

      // 끝난 세션은 취소되지 않는다
      expect(SessionRules.cancel({...data, 'status': 'finished'}), isNull);
    });
  });
}
