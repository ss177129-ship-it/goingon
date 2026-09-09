import 'package:cloud_firestore/cloud_firestore.dart';

import 'session_rules.dart';

/// 오가는 러닝 제안 하나 — 세션 문서를 화면이 쓰기 좋은 모양으로 옮긴 것.
///
/// **방향이 전부다.** 같은 문서라도 내가 부른 것과 내가 불린 것은 할 수 있는
/// 일이 다르다(취소 vs 수락·거절). 그래서 세션을 그대로 넘기지 않고 여기서
/// 한 번 내 관점으로 접는다.
enum InviteDirection { incoming, outgoing }

/// 홈 카드와 '제안' 탭이 그리는 상태. 문서의 status와 1:1이 아니다 —
/// 같은 `invited`라도 부른 쪽과 불린 쪽이 다른 것을 봐야 하고, 30분이
/// 지났으면 서버 정리가 아직 안 돌았어도 만료로 보여야 한다.
enum InviteCard {
  /// 오가는 것이 없다 — GO?
  none,

  /// 내가 불렀고 답을 기다린다
  waitingAnswer,

  /// 나를 불렀고 아직 답하지 않았다
  needsAnswer,

  /// 수락됐다 — 어느 쪽이든 로비로 들어갈 수 있다
  joinable,

  /// 거절당했다(한 줄 답장이 있을 수 있다)
  declined,

  /// 답이 오지 않은 채 시간이 다 됐다
  expired,

  /// 누군가 그만뒀다
  cancelled,
}

class Invite {
  final String sessionId;

  /// 나에게 이 제안의 상대 — incoming이면 hostId, outgoing이면 guestId
  final String partnerUid;
  final InviteDirection direction;

  /// 세션 문서의 status 그대로
  final String status;

  /// serverTimestamp라 만들어진 직후에는 아직 null이다
  final DateTime? createdAt;
  final String? declineMessage;

  const Invite({
    required this.sessionId,
    required this.partnerUid,
    required this.direction,
    required this.status,
    this.createdAt,
    this.declineMessage,
  });

  /// 세션 문서 하나를 내 관점으로 접는다. 내가 낀 세션이 아니면 `null`
  static Invite? from(
    String id,
    Map<String, dynamic> data,
    String myUid,
  ) {
    final host = data['hostId'] as String?;
    final guest = data['guestId'] as String?;
    if (host == null || guest == null) return null;
    final incoming = guest == myUid;
    if (!incoming && host != myUid) return null;
    final ts = data['createdAt'];
    return Invite(
      sessionId: id,
      partnerUid: incoming ? host : guest,
      direction: incoming ? InviteDirection.incoming : InviteDirection.outgoing,
      status: (data['status'] as String?) ?? '',
      createdAt: ts is Timestamp ? ts.toDate() : null,
      declineMessage: data['declineMessage'] as String?,
    );
  }

  /// 답을 기다릴 수 있는 시간이 얼마나 남았나. 답을 기다리는 중이 아니거나
  /// 서버 시각이 아직 안 찍혔으면 `null`.
  ///
  /// **음수를 돌려주지 않는다** — 시간이 다 된 것은 '남은 시간 -3분'이 아니라
  /// 만료다. 그 판정은 [cardFor]가 한다
  Duration? remaining(DateTime now) {
    if (status != SessionRules.invited) return null;
    final made = createdAt;
    if (made == null) return null;
    final left = SessionRules.requestTtl - now.difference(made);
    return left.isNegative ? Duration.zero : left;
  }

  /// 화면이 그릴 상태.
  ///
  /// **시간 만료를 여기서 본다.** 서버 정리는 15분마다 돌기 때문에, 30분이
  /// 지난 요청이 문서에는 아직 `invited`로 남아 있다. 그걸 그대로 "기다리는
  /// 중"이라고 그리면 화면이 거짓말을 한다
  InviteCard cardFor(DateTime now) {
    switch (status) {
      case SessionRules.invited:
        final left = remaining(now);
        if (left != null && left == Duration.zero) return InviteCard.expired;
        return direction == InviteDirection.outgoing
            ? InviteCard.waitingAnswer
            : InviteCard.needsAnswer;
      case SessionRules.accepted:
        return InviteCard.joinable;
      case SessionRules.declined:
        return InviteCard.declined;
      case SessionRules.expired:
        return InviteCard.expired;
      case SessionRules.cancelled:
        return InviteCard.cancelled;
      default:
        // running·finished는 제안이 아니라 러닝이다 — '우리' 탭의 것
        return InviteCard.none;
    }
  }

  /// 아직 무언가 할 수 있는 제안인가 — '제안' 탭의 위쪽에 서는 것들
  bool isOpen(DateTime now) {
    final c = cardFor(now);
    return c == InviteCard.waitingAnswer ||
        c == InviteCard.needsAnswer ||
        c == InviteCard.joinable;
  }

  /// 이미 끝났지만 아직 보여줄 만한 것 — 거절 답장, 만료 안내.
  ///
  /// 이게 없으면 부른 사람은 상대가 거절했다는 사실을 영영 모른다.
  /// 카드가 조용히 GO?로 돌아갈 뿐이다
  bool isOutcome(DateTime now) {
    final c = cardFor(now);
    return c == InviteCard.declined ||
        c == InviteCard.expired ||
        c == InviteCard.cancelled;
  }
}

/// 한 사람에 대해 지금 화면이 따라야 할 제안 하나를 고른다.
///
/// 같은 상대와 여러 세션이 겹칠 수 있다 — 만료된 옛 요청이 남아 있는데 새로
/// 부르거나, 양쪽이 동시에 GO?를 눌러 두 개가 생기거나. 그때 **살아 있는 것이
/// 언제나 이긴다.** 지난 결과 때문에 지금 부르고 있는 사람이 가려지면 안 된다.
Invite? currentInviteFor(
  Iterable<Invite> invites,
  String partnerUid,
  DateTime now,
) {
  Invite? open, outcome;
  for (final i in invites) {
    if (i.partnerUid != partnerUid) continue;
    if (i.isOpen(now)) {
      // 살아 있는 것 중에서는 나중에 만들어진 것
      if (open == null || _newer(i, open)) open = i;
    } else if (i.isOutcome(now)) {
      if (outcome == null || _newer(i, outcome)) outcome = i;
    }
  }
  return open ?? outcome;
}

/// createdAt이 아직 없는 것(막 만든 것)은 가장 최신으로 본다
bool _newer(Invite a, Invite b) {
  final x = a.createdAt, y = b.createdAt;
  if (x == null) return true;
  if (y == null) return false;
  return x.isAfter(y);
}

/// 양쪽이 거의 동시에 GO?를 눌러 세션이 둘 생겼을 때, 어느 쪽을 살릴지.
///
/// **왜 생기나.** 세션은 hostId/guestId로 방향이 박혀 있어서, 내가 부른 것과
/// 상대가 부른 것은 서로 다른 문서다. 둘 다 누르면 A→B와 B→A가 동시에
/// 존재하고, 두 사람 모두 "내가 불렀는데 상대도 나를 부르고 있다"는 화면을
/// 보게 된다. 답할 것이 둘인데 하고 싶은 일은 하나다.
///
/// **어떻게 접나.** 두 기기가 서로 상의하지 않고 같은 답을 내야 하므로,
/// 데이터에만 의존하는 고정된 기준을 쓴다 — **uid 사전순으로 앞선 사람이
/// 호스트인 쪽을 살린다.** 시간(createdAt)으로 정하면 서버 시각이 아직
/// 안 찍힌 문서가 있어 두 기기가 다른 답을 낼 수 있다.
///
/// 살아남은 쪽은 **수락된 것으로 본다.** 둘 다 GO?를 눌렀다는 것은 둘 다
/// 달리고 싶다는 뜻이고, 거기서 다시 "수락하시겠어요?"를 묻는 것은 이미
/// 한 대답을 또 시키는 것이다.
class InviteMerge {
  /// 살릴 세션
  final Invite keep;

  /// 접을 세션
  final Invite drop;

  /// 내가 [keep]의 게스트인가 — 수락을 쓸 수 있는 사람은 게스트뿐이다
  final bool iAmGuestOfKeep;

  const InviteMerge({
    required this.keep,
    required this.drop,
    required this.iAmGuestOfKeep,
  });
}

/// 겹친 제안들을 어떻게 접을지. 겹치지 않으면 빈 목록
List<InviteMerge> inviteCollisions(
  Iterable<Invite> invites,
  String myUid,
  DateTime now,
) {
  final byPartner = <String, List<Invite>>{};
  for (final i in invites) {
    if (!i.isOpen(now)) continue;
    (byPartner[i.partnerUid] ??= []).add(i);
  }

  final merges = <InviteMerge>[];
  byPartner.forEach((partnerUid, list) {
    final mine = list.where((i) => i.direction == InviteDirection.outgoing);
    final theirs = list.where((i) => i.direction == InviteDirection.incoming);
    if (mine.isEmpty || theirs.isEmpty) return;

    // 이미 수락된 쪽이 있으면 그쪽이 이긴다 — 사람이 내린 답이 규칙보다 앞선다
    final accepted = list.where((i) => i.status == SessionRules.accepted);
    final Invite keep;
    if (accepted.isNotEmpty) {
      keep = accepted.first;
    } else {
      // uid 사전순으로 앞선 사람이 호스트인 쪽
      final iAmCanonicalHost = myUid.compareTo(partnerUid) < 0;
      keep = iAmCanonicalHost ? mine.first : theirs.first;
    }
    for (final other in list) {
      if (identical(other, keep)) continue;
      merges.add(InviteMerge(
        keep: keep,
        drop: other,
        iAmGuestOfKeep: keep.direction == InviteDirection.incoming &&
            keep.status == SessionRules.invited,
      ));
    }
  });
  return merges;
}
