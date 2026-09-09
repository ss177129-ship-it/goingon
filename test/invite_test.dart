import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goingon/services/invite.dart';
import 'package:goingon/services/session_rules.dart';

/// 세션 문서를 "내가 지금 무엇을 할 수 있는가"로 접는 층.
///
/// 여기가 틀리면 화면이 조용히 거짓말을 한다 — 이미 거절당했는데 기다리는
/// 중이라고 하거나, 30분이 지났는데 아직 답을 기다린다고 하거나.
void main() {
  const me = 'me';
  const you = 'you';
  final now = DateTime.utc(2026, 9, 9, 12);

  Map<String, dynamic> doc({
    String host = me,
    String guest = you,
    String status = SessionRules.invited,
    DateTime? createdAt,
    String? declineMessage,
  }) =>
      {
        'hostId': host,
        'guestId': guest,
        'status': status,
        if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt),
        if (declineMessage != null) 'declineMessage': declineMessage,
      };

  Invite invite(Map<String, dynamic> d) => Invite.from('s1', d, me)!;

  group('방향 — 같은 문서라도 관점이 다르다', () {
    test('내가 host면 outgoing, 상대가 partner', () {
      final i = invite(doc());
      expect(i.direction, InviteDirection.outgoing);
      expect(i.partnerUid, you);
    });

    test('내가 guest면 incoming, host가 partner', () {
      final i = Invite.from('s1', doc(host: you, guest: me), me)!;
      expect(i.direction, InviteDirection.incoming);
      expect(i.partnerUid, you);
    });

    test('내가 안 낀 세션은 null', () {
      expect(Invite.from('s1', doc(host: 'a', guest: 'b'), me), isNull);
      expect(Invite.from('s1', const {}, me), isNull);
    });
  });

  group('카드 상태', () {
    test('부른 쪽은 기다리고, 불린 쪽은 답해야 한다', () {
      final out = invite(doc(createdAt: now));
      expect(out.cardFor(now), InviteCard.waitingAnswer);

      final inc = Invite.from('s1', doc(host: you, guest: me, createdAt: now), me)!;
      expect(inc.cardFor(now), InviteCard.needsAnswer);
    });

    test('수락되면 양쪽 다 입장할 수 있다', () {
      for (final d in [
        doc(status: SessionRules.accepted),
        doc(host: you, guest: me, status: SessionRules.accepted),
      ]) {
        expect(Invite.from('s1', d, me)!.cardFor(now), InviteCard.joinable);
      }
    });

    test('30분이 지나면 문서가 아직 invited여도 만료로 그린다', () {
      // 서버 정리는 15분마다 돈다. 그 사이를 "기다리는 중"이라고 그리면
      // 화면이 거짓말을 한다
      final stale = invite(doc(createdAt: now.subtract(const Duration(minutes: 31))));
      expect(stale.cardFor(now), InviteCard.expired);
    });

    test('29분은 아직 살아 있다', () {
      final alive = invite(doc(createdAt: now.subtract(const Duration(minutes: 29))));
      expect(alive.cardFor(now), InviteCard.waitingAnswer);
    });

    test('서버 시각이 아직 없으면 만료로 몰지 않는다', () {
      // createdAt은 serverTimestamp라 만든 직후엔 null이다. 이때 만료라고
      // 하면 방금 보낸 요청이 보내자마자 죽은 것으로 보인다
      expect(invite(doc()).cardFor(now), InviteCard.waitingAnswer);
      expect(invite(doc()).remaining(now), isNull);
    });

    test('러닝은 제안이 아니다', () {
      for (final st in [SessionRules.running, SessionRules.finished]) {
        expect(invite(doc(status: st)).cardFor(now), InviteCard.none);
      }
    });

    test('끝난 것들은 각자 다른 얼굴을 갖는다', () {
      expect(invite(doc(status: SessionRules.declined)).cardFor(now),
          InviteCard.declined);
      expect(invite(doc(status: SessionRules.expired)).cardFor(now),
          InviteCard.expired);
      expect(invite(doc(status: SessionRules.cancelled)).cardFor(now),
          InviteCard.cancelled);
    });
  });

  group('남은 시간', () {
    test('답을 기다리는 중에만 센다', () {
      expect(invite(doc(status: SessionRules.accepted, createdAt: now))
          .remaining(now), isNull);
    });

    test('음수를 돌려주지 않는다 — 시간이 다 된 것은 만료다', () {
      final over = invite(doc(createdAt: now.subtract(const Duration(hours: 2))));
      expect(over.remaining(now), Duration.zero);
    });

    test('10분 지났으면 20분 남았다', () {
      final i = invite(doc(createdAt: now.subtract(const Duration(minutes: 10))));
      expect(i.remaining(now), const Duration(minutes: 20));
    });
  });

  group('한 사람에 대해 무엇을 보여줄지 — 살아 있는 것이 이긴다', () {
    test('오가는 것이 없으면 null', () {
      expect(currentInviteFor(const [], you, now), isNull);
    });

    test('지난 거절이 남아 있어도 지금 부르는 것이 이긴다', () {
      // 이 순서가 뒤집히면 상대가 지금 부르고 있는데 화면에는 지난주
      // 거절 문구가 떠 있게 된다
      final old = invite(doc(
          status: SessionRules.declined,
          createdAt: now.subtract(const Duration(hours: 5))));
      final live = Invite.from('s2',
          doc(host: you, guest: me, createdAt: now), me)!;

      expect(currentInviteFor([old, live], you, now)?.sessionId, 's2');
      expect(currentInviteFor([live, old], you, now)?.sessionId, 's2');
    });

    test('살아 있는 것이 없으면 가장 최근 결과를 보여준다', () {
      final older = Invite.from('s1',
          doc(status: SessionRules.expired,
              createdAt: now.subtract(const Duration(hours: 5))), me)!;
      final newer = Invite.from('s2',
          doc(status: SessionRules.declined,
              createdAt: now.subtract(const Duration(hours: 1))), me)!;
      expect(currentInviteFor([older, newer], you, now)?.sessionId, 's2');
    });

    test('다른 사람의 제안은 섞이지 않는다', () {
      final other = Invite.from('s9',
          doc(guest: 'someone', createdAt: now), me)!;
      expect(currentInviteFor([other], you, now), isNull);
    });

    test('막 보낸 것(createdAt 없음)이 가장 최신이다', () {
      // 방금 GO?를 누른 요청이 지난 요청에 가려지면, 눌렀는데 아무 일도
      // 안 일어난 것처럼 보인다
      final old = invite(doc(createdAt: now.subtract(const Duration(minutes: 5))));
      final fresh = Invite.from('s2', doc(), me)!;
      expect(currentInviteFor([old, fresh], you, now)?.sessionId, 's2');
    });
  });
}
