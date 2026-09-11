import 'package:cloud_firestore/cloud_firestore.dart';

/// DM — 두 사람 사이의 한 줄기.
///
/// ## 왜 DM이 채팅이 아닌가
///
/// `pacemate_status.dart`가 적어둔 그대로, 이 앱은 **presence를 만들 수 없다** —
/// 보안 규칙이 세션을 hostId/guestId 직접 비교로만 열어 주므로 "상대가 지금
/// 달릴 수 있는가"는 구조적으로 읽히지 않고, 가장 세밀한 신호가 주 단위
/// `lastRunWeek`다. 그래서 "친구 상태를 확인하고 → 제안하고 → 수락하고"의
/// **1번이 앱에 없었다.** 실제로는 어둠 속에 GO?를 쏘고 30분 기다리는 것이었다.
///
/// DM은 그 빈 자리를 메우는 물건이다. 상대가 거기 있는지 볼 수 없으니
/// **물어보는 것**이 이 구조가 허락하는 유일한 존재 신호다.
///
/// ## 설계에서 지키는 것 넷
///
/// 1. **threadId는 두 uid를 사전순으로 이은 것**이다(`friendRequests`·`follows`와
///    같은 결정적 id). 같은 쌍에 스레드가 둘 생기는 것을 구조적으로 막고,
///    쿼리 없이 경로로 바로 찾고, 규칙이 문서를 안 읽고 id만으로 판정한다.
///
/// 2. **스레드 문서는 여기서 만들지 않는다.** 첫 메시지가 쓰이면 서버
///    트리거가 만든다. 그래서 두 사람이 동시에 말을 걸어도 경합이 없고,
///    왕복이 하나 줄고, 맞팔 게이트가 규칙 한 곳에만 있으면 된다.
///
/// 3. **안 읽음은 서버가 센다.** 여기서는 내 칸을 0으로 만드는 것만 한다.
///    클라이언트가 상대 칸을 올릴 수 있으면 배지가 조작된다.
///
/// 4. **목록의 출처는 `threads`가 아니라 `users.following`이다.** 스레드로
///    목록을 만들면 아직 말을 나눈 적 없는 페이스메이트가 목록에서 사라져,
///    정작 대화를 시작할 자리가 없어진다. 스레드는 그 목록에 **얹는** 것이다
///    ([mergeThreads] 참고).
class ThreadService {
  ThreadService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// 본문 상한. 규칙에도 같은 값이 걸려 있다 — 여기서 먼저 막아야
  /// 사용자가 긴 글을 다 쓰고 나서 거부당하지 않는다
  static const maxTextLength = 1000;

  /// 두 uid를 사전순으로 이어 만든 결정적 id.
  ///
  /// Firebase Auth uid는 영숫자라 `_`가 없다. 커스텀 uid를 쓰게 되면
  /// 이 가정이 가장 먼저 깨진다 — 규칙도 같은 split에 기대고 있다
  static String idFor(String a, String b) =>
      a.compareTo(b) < 0 ? '${a}_$b' : '${b}_$a';

  /// threadId에서 상대 uid를 꺼낸다. 쌍이 아니면 null
  static String? partnerIn(String threadId, String myUid) {
    final pair = threadId.split('_');
    if (pair.length != 2 || !pair.contains(myUid)) return null;
    return pair[0] == myUid ? pair[1] : pair[0];
  }

  DocumentReference<Map<String, dynamic>> _thread(String threadId) =>
      _db.collection('threads').doc(threadId);

  CollectionReference<Map<String, dynamic>> _messages(String threadId) =>
      _thread(threadId).collection('messages');

  /// 내 스레드 목록.
  ///
  /// **[SharedStream]을 쓰지 않는다.** 목록을 보는 곳이 둘이지만('대화' 탭과
  /// 배지를 세는 루트 셸), SharedStream은 *마지막 구독자가 떠날 때*만 원본을
  /// 닫고 다음 구독에서 새로 연다. 셸이 앱 수명 내내 붙어 있으면 그 순간이
  /// 영영 오지 않으므로, 권한 거부나 인덱스 누락으로 원본이 한 번 끝나면
  /// **'다시 시도' 버튼이 죽은 스트림에 다시 붙는다.** 리스너 하나를 아끼려다
  /// 복구 경로를 잃는 거래라, 여기서는 각자 구독한다(문서 30개짜리 쿼리다).
  ///
  /// 안 읽음 수가 문서에 이미 들어 있으므로 **추가 읽기가 0이다.**
  /// 메시지를 세서 배지를 만들면 스레드 수만큼 쿼리가 늘고 비용이 폭발한다.
  ///
  /// `participants` arrayContains로 좁히는 것이 **필수**다 — 목록 규칙에서
  /// `resource.data`는 문서 내용이 아니라 쿼리 조건이라, 안 좁히면 쿼리
  /// 전체가 거부된다(`runs`에서 배운 것)
  Stream<QuerySnapshot<Map<String, dynamic>>> threads(String myUid) =>
      _db
          .collection('threads')
          .where('participants', arrayContains: myUid)
          .orderBy('lastAt', descending: true)
          .limit(30)
          .snapshots();

  /// 열어 둔 대화. 최신이 먼저 오므로 화면에서 reverse로 그린다
  Stream<QuerySnapshot<Map<String, dynamic>>> messages(String threadId,
          {int limit = 50}) =>
      _messages(threadId)
          .orderBy('at', descending: true)
          .limit(limit)
          .snapshots();

  /// 텍스트 한 줄.
  ///
  /// 스레드 문서를 먼저 만들지 않는다 — 서버가 이 쓰기를 보고 만든다.
  /// `at`은 반드시 서버 시각이어야 한다(규칙이 `request.time`과 대조한다):
  /// 클라이언트가 시각을 직접 적을 수 있으면 과거로 적어 남의 말 위에
  /// 끼워 넣을 수 있다.
  ///
  /// 던지는 예외는 부르는 쪽이 받는다 — 맞팔이 끊겼거나 차단당했으면
  /// `permission-denied`가 오고, 그때 화면이 "지금은 말을 보낼 수 없어요"를
  /// 말해야 한다. 조용히 삼키면 보낸 줄 알고 기다리게 된다
  Future<void> sendText({
    required String myUid,
    required String partnerUid,
    required String text,
  }) async {
    final body = text.trim();
    if (body.isEmpty) return;
    if (body.length > maxTextLength) {
      throw ArgumentError('메시지는 $maxTextLength자를 넘을 수 없어요');
    }
    await _messages(idFor(myUid, partnerUid)).add({
      'senderId': myUid,
      'type': 'text',
      'at': FieldValue.serverTimestamp(),
      'text': body,
    });
  }

  /// 대화를 열었다 — 내 칸만 0으로.
  ///
  /// **부르는 쪽이 [ThreadSummary.isEmpty]일 때는 부르지 말 것.** 아직 아무도
  /// 말한 적 없는 사이에는 스레드 문서가 없고, 없는 문서의 `update`는
  /// `not-found`가 아니라 **`permission-denied`로 돌아온다** — 규칙의
  /// `diff(resource.data)`가 null을 참조해 평가 단계에서 먼저 거부되기
  /// 때문이고, 쓰기 전제조건까지 가지도 못한다. friendRequests에서 읽기
  /// 경로에 났던 그 함정이 쓰기 경로에도 그대로 있다.
  ///
  /// 그래서 여기서는 둘 다 삼킨다. 다만 `permission-denied`를 삼키는 것은
  /// **진짜 거부까지 감추는** 일이라, 호출부에서 걸러주는 것이 먼저다
  Future<void> markRead(String threadId, String myUid) async {
    try {
      await _thread(threadId).update({'unread.$myUid': 0});
    } on FirebaseException catch (e) {
      if (e.code == 'not-found' || e.code == 'permission-denied') return;
      rethrow;
    }
  }

  /// 이 대화의 알림만 끄고 켠다. 껐어도 안 읽음은 계속 센다 —
  /// 껐다는 것은 "지금 울리지 말라"이지 "없던 일로 하라"가 아니다
  ///
  /// 아직 아무도 말한 적 없는 사이에는 스레드 문서가 없다. 끌 알림도 없다 —
  /// [markRead]와 같은 이유로 둘 다 삼킨다. set/merge를 쓰면 그 경우가
  /// '생성'이 되어 규칙에 막힌다(스레드는 서버만 만든다)
  Future<void> setMuted(String threadId, String myUid, bool muted) async {
    try {
      await _thread(threadId).update({'muted.$myUid': muted});
    } on FirebaseException catch (e) {
      if (e.code == 'not-found' || e.code == 'permission-denied') return;
      rethrow;
    }
  }

  /// 신고 한 건. 읽기는 아무에게도 열려 있지 않다 —
  /// 신고당한 사람이 자기 신고를 볼 수 있으면 보복이 시작된다
  Future<void> report({
    required String myUid,
    required String targetUid,
    required String threadId,
    String? messageId,
    String? reason,
  }) =>
      _db.collection('reports').add({
        'reporterUid': myUid,
        'targetUid': targetUid,
        'threadId': threadId,
        if (messageId != null) 'messageId': messageId,
        if (reason != null) 'reason': reason,
        'at': FieldValue.serverTimestamp(),
      });

  /// 페이스메이트 목록에 스레드를 얹는다.
  ///
  /// 목록의 출처는 언제나 `following`이다(클래스 주석 4번). 스레드가 없는
  /// 사람은 마지막 줄이 비고 안 읽음이 0인 [ThreadSummary]가 된다 —
  /// 화면은 그 자리에 "아직 나눈 말이 없어요"를 그린다.
  ///
  /// 정렬: 말이 오간 순서가 먼저, 그다음이 이름이다. 대화가 없는 사람이
  /// 목록 맨 아래로 밀려나야 방금 온 말이 눈에 띈다
  static List<ThreadSummary> mergeThreads({
    required String myUid,
    required List<({String uid, String name})> pacemates,
    required Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> threadDocs,
  }) {
    final byPartner = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final d in threadDocs) {
      final partner = partnerIn(d.id, myUid);
      if (partner != null) byPartner[partner] = d;
    }

    final out = <ThreadSummary>[];
    for (final p in pacemates) {
      final d = byPartner[p.uid];
      final data = d?.data();
      out.add(ThreadSummary(
        partnerUid: p.uid,
        partnerName: p.name,
        threadId: idFor(myUid, p.uid),
        lastPreview: data?['lastPreview'] as String?,
        lastAt: (data?['lastAt'] as Timestamp?)?.toDate(),
        lastSenderId: data?['lastSenderId'] as String?,
        // 서버가 아직 안 쓴 스레드는 unread 자체가 없다
        unread: _readCount(data?['unread'], myUid),
        muted: (data?['muted'] as Map?)?[myUid] == true,
      ));
    }

    // Dart의 sort는 안정 정렬이 아니다. 동점에서 0을 돌려주면 같은 스트림을
    // 다시 그릴 때마다 두 줄이 자리를 바꾼다
    out.sort((a, b) {
      final at = a.lastAt, bt = b.lastAt;
      if (at != null && bt != null) {
        final byTime = bt.compareTo(at);
        if (byTime != 0) return byTime;
      } else if (at != null) {
        return -1;
      } else if (bt != null) {
        return 1;
      }
      return a.partnerName.compareTo(b.partnerName);
    });
    return out;
  }

  /// 안 읽음 칸은 서버가 쓰므로 타입을 믿지 않는다 —
  /// `entry.value as Map`으로 구독이 통째로 죽은 적이 있다
  static int _readCount(Object? unread, String myUid) {
    if (unread is! Map) return 0;
    final v = unread[myUid];
    return v is num ? v.toInt() : 0;
  }
}

/// 대화 탭의 한 줄. 스레드가 없는 페이스메이트도 한 줄을 갖는다
class ThreadSummary {
  const ThreadSummary({
    required this.partnerUid,
    required this.partnerName,
    required this.threadId,
    required this.lastPreview,
    required this.lastAt,
    required this.lastSenderId,
    required this.unread,
    required this.muted,
  });

  final String partnerUid;
  final String partnerName;
  final String threadId;
  final String? lastPreview;
  final DateTime? lastAt;
  final String? lastSenderId;
  final int unread;
  final bool muted;

  /// 아직 아무도 말한 적 없는 사이
  bool get isEmpty => lastAt == null;
}
