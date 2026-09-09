import 'package:cloud_firestore/cloud_firestore.dart';

import 'live_share.dart';
import 'session_rules.dart';
import 'week_key.dart';

/// GO? 요청이 살아 있는 시간. 이보다 오래된 대기 세션은 뒤늦게 수락 시트로
/// 띄우지 않고 정리하고, 같은 상대에게 다시 보낼 때도 재사용하지 않음
/// 값의 출처는 [SessionRules.requestTtl] 하나뿐이다 — 두 곳에 적어두면
/// 언젠가 한쪽만 바뀐다. 홈 화면이 이 이름으로 쓰고 있어 별칭만 남긴다
const kRequestTtl = SessionRules.requestTtl;

/// 데모 모드가 쓰는 가짜 세션 id. Firestore에 이런 문서는 존재하지 않으므로,
/// 이 id로 결과를 제출하거나 복구를 시도하면 반드시 실패함
const kDemoSessionId = 'demo';

/// 함께 달리기 세션 (MVP 전략: 실시간 위치 동기화 없음 —
/// 함께 '시작'하고, 끝나면 결과를 '합산'. 라이브 합산은 v1.1)
///
/// sessions/{id}:
///   hostId, guestId, status: waiting|ready|running|finished
///   ready: {uid: bool}, startedAt
///   results: {uid: {seconds, km, kcal}}
class RunService {
  final _db = FirebaseFirestore.instance;

  /// GO? — 세션 생성 (상대는 홈에서 스냅샷으로 감지).
  ///
  /// 같은 친구에게 아직 응답 없는 요청이 남아 있으면 새로 만들지 않고 그것을
  /// 재사용함 — 안 그러면 GO?를 여러 번 누를 때마다 waiting 세션이 쌓이고,
  /// 상대는 수락한 뒤에도 남은 요청 시트를 계속 보게 됨
  /// 상대가 이미 나를 부르고 있으면 **새로 만드는 대신 그것을 수락한다.**
  /// 둘 다 GO?를 눌렀다는 건 둘 다 달리고 싶다는 뜻이고, 세션을 하나 더
  /// 만들면 두 사람 모두 "내가 불렀는데 상대도 나를 부른다"를 보게 된다.
  ///
  /// 이걸로도 완전한 동시 입력은 못 막는다(둘 다 상대 문서를 보기 전에
  /// 만들면 두 개가 생긴다) — 그건 [inviteCollisions]가 뒤에서 접는다
  Future<String> createSession(String hostId, String guestId) async {
    final theirs = await _findIncomingInvite(myUid: hostId, fromUid: guestId);
    if (theirs != null) {
      await acceptSession(theirs);
      return theirs;
    }
    final existing = await _findPendingSession(hostId, guestId);
    if (existing != null) return existing;

    final ref = await _db.collection('sessions').add({
      'hostId': hostId,
      'guestId': guestId,
      'participants': [hostId, guestId],
      'status': SessionRules.invited,
      'ready': {hostId: false, guestId: false},
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// 내가 이 친구에게 보낸, 아직 살아 있는(30분 이내) 요청이 있으면 그 id
  Future<String?> _findPendingSession(String hostId, String guestId) async {
    try {
      final snap = await _db
          .collection('sessions')
          .where('hostId', isEqualTo: hostId)
          .where('guestId', isEqualTo: guestId)
          .where('status', whereIn: SessionRules.openStatuses).get();
      for (final doc in snap.docs) {
        final createdAt = doc.data()['createdAt'] as Timestamp?;
        if (SessionRules.isRequestAlive(createdAt, DateTime.now())) {
          return doc.id;
        }
      }
    } catch (_) {
      // 인덱스/네트워크 문제로 확인에 실패하면 새로 만드는 쪽으로 — 중복
      // 세션은 불편할 뿐이지만, 여기서 던지면 GO? 자체가 막힘
    }
    return null;
  }

  /// 그 사람이 나에게 보낸, 아직 답하지 않은 요청
  Future<String?> _findIncomingInvite({
    required String myUid,
    required String fromUid,
  }) async {
    try {
      final snap = await _db
          .collection('sessions')
          .where('hostId', isEqualTo: fromUid)
          .where('guestId', isEqualTo: myUid)
          .where('status', isEqualTo: SessionRules.invited)
          .get();
      for (final doc in snap.docs) {
        final createdAt = doc.data()['createdAt'] as Timestamp?;
        if (SessionRules.isRequestAlive(createdAt, DateTime.now())) {
          return doc.id;
        }
      }
    } catch (_) {
      // 확인에 실패하면 평소대로 새로 만든다 — 겹침은 불편할 뿐이지만
      // 여기서 던지면 GO? 자체가 막힌다
    }
    return null;
  }

  /// 로비에 들어왔음을 알림 — 상대 로비에서 "함께 준비 중"으로 보임.
  /// 이게 없으면 호스트는 상대가 앱을 안 켠 건지 준비운동 중인 건지 구분 못 함.
  ///
  /// 재사용된 세션에 지난번 준비/늦음 상태가 남아 있을 수 있으므로 내 항목만
  /// 초기화함 — 로비는 항상 1단계부터 시작하는데 상대 화면에만 "준비완료"로
  /// 보이는 어긋남을 막기 위함
  Future<void> enterLobby(String sessionId, String uid) async {
    await _db.collection('sessions').doc(sessionId).update({
      'joined.$uid': true,
      'ready.$uid': false,
      'late.$uid': false,
    });
  }

  /// 제안이 화면에 남아 있는 창. 30분 TTL이 지난 뒤에도 결과(거절 답장·만료)를
  /// 한동안 보여줘야 하므로 TTL보다 넉넉하다
  static const recentWindow = Duration(hours: 12);

  /// 나에게 온 제안 — 아직 답하지 않은 것, 내가 수락해 둔 것, 그리고 최근 결과.
  ///
  /// **status로 거르지 않고 시간으로 자른다.** 이유가 둘이다:
  /// - 수락한 것까지 있어야 '제안' 탭이 로비 입구를 계속 들고 있다. 시트를
  ///   닫거나 앱을 껐다 켠 사람이 들어갈 길을 잃지 않는다
  /// - 거절·만료된 문서는 지워지지 않고 영영 쌓인다. status로만 거르면
  ///   쿼리가 해가 갈수록 무거워진다
  ///
  /// `createdAt`은 serverTimestamp라 만든 직후에는 null이고, 그동안 이
  /// 범위 조건에 걸리지 않는다 — 서버 시각이 찍히면 스트림이 다시 울린다
  Stream<QuerySnapshot<Map<String, dynamic>>> incomingSessions(String myUid) =>
      _recent('guestId', myUid);

  /// 내가 보낸 제안. 보낸 사람은 홈에 머무르므로(2026-09-09) 이 스트림이
  /// 그 카드의 상태이고, 거절 답장이 도착하는 곳도 여기다
  Stream<QuerySnapshot<Map<String, dynamic>>> outgoingSessions(String myUid) =>
      _recent('hostId', myUid);

  Stream<QuerySnapshot<Map<String, dynamic>>> _recent(String field, String uid) {
    final since = Timestamp.fromDate(DateTime.now().subtract(recentWindow));
    return _db
        .collection('sessions')
        .where(field, isEqualTo: uid)
        .where('createdAt', isGreaterThan: since)
        .orderBy('createdAt', descending: true)
        .limit(30)
        .snapshots();
  }

  /// 게스트의 수락
  Future<void> acceptSession(String sessionId) =>
      _transition(sessionId, SessionRules.accept);

  /// 게스트의 거절 — 침묵 대신 한 줄 답장을 남길 수 있다
  Future<void> declineSession(String sessionId, String message) =>
      _transition(sessionId, (d) => SessionRules.decline(d, message: message));

  /// 답 없이 30분이 지난 요청 정리
  Future<void> expireSession(String sessionId) =>
      _transition(sessionId, SessionRules.expire);

  /// 읽고 → 판정하고 → 판정이 나오면 쓴다. 상태 전이는 전부 이 모양이라
  /// 트랜잭션 껍데기를 한 곳에 둔다
  Future<void> _transition(String sessionId,
      Map<String, Object?>? Function(Map<String, dynamic>?) rule) async {
    final ref = _db.collection('sessions').doc(sessionId);
    await _db.runTransaction((tx) async {
      final doc = await tx.get(ref);
      final update = rule(doc.data());
      if (update != null) tx.update(ref, update);
    });
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> sessionStream(String id) =>
      _db.collection('sessions').doc(id).snapshots();

  /// 러닝 중 상대에게 보내는 가벼운 제스처 신호(탭/스와이프/롱프레스) —
  /// 위치·페이스처럼 지속적으로 동기화하는 게 아니라 순간적인 이벤트 하나만
  /// 덮어쓰는 것이라 "러닝 중 실시간 동기화 없음" 원칙과는 무관함
  Future<void> sendGesture(String sessionId, String uid, String type) async {
    await _db.collection('sessions').doc(sessionId).update({
      'gesture': {
        'uid': uid,
        'type': type,
        'at': FieldValue.serverTimestamp(),
      },
    });
  }

  /// 러닝 중 내 상태를 상대에게 보낸다 — `live.{uid}` 한 칸만 덮어쓴다.
  ///
  /// 언제 부를지는 [LiveWriteGate]가 정한다(3초 간격 + 유의미한 변화).
  /// 여기서는 쓰기만 하고 판단하지 않는다.
  ///
  /// 실패해도 조용히 넘어간다: 이건 부가 정보라 못 보냈다고 러닝을 멈추거나
  /// 사용자를 부를 이유가 없다. 다음 갱신이 3초 뒤에 또 온다
  Future<void> pushLive(String sessionId, String uid, LiveState state) async {
    await _db.collection('sessions').doc(sessionId).update({
      'live.$uid': state.toMap(),
    });
  }

  /// 취소된 세션이 뒤늦게 부활하지 않도록 트랜잭션으로 상태를 먼저 확인
  Future<void> setReady(String sessionId, String uid) =>
      _transition(sessionId, (d) => SessionRules.ready(d, uid));

  /// 준비 취소 — 화면만 되돌리면 상대에게는 여전히 준비완료로 보인다
  Future<void> clearReady(String sessionId, String uid) =>
      _transition(sessionId, (d) => SessionRules.unready(d, uid));

  /// "조금 늦을 것 같아요" — 상대 로비 화면에 실시간으로 반영됨
  Future<void> setLate(String sessionId, String uid, bool isLate) async {
    await _db.collection('sessions').doc(sessionId).update({
      'late.$uid': isLate,
    });
  }

  /// 둘 다 준비되면 호출 — 동시에 출발.
  /// 취소된 세션이 뒤늦게 부활하지 않도록 트랜잭션으로 상태를 먼저 확인하고,
  /// 양쪽 클라이언트가 각자 이 함수를 부르므로 startedAt은 먼저 찍힌 값을
  /// 유지함 (덮어쓰면 '함께 출발한 시각'이 나중 사람 기준으로 밀림)
  Future<void> startRun(String sessionId) async {
    final ref = _db.collection('sessions').doc(sessionId);
    await _db.runTransaction((tx) async {
      final doc = await tx.get(ref);
      final update = SessionRules.start(doc.data());
      if (update != null) tx.update(ref, update);
    });
  }

  /// 내 결과 업로드. 상대 결과가 이미 있으면 세션 종료 처리
  /// (트랜잭션으로 묶어야, 양쪽이 거의 동시에 제출할 때 "읽은 시점엔
  /// 상대 결과가 없었음" 하는 경합으로 status가 영영 finished로
  /// 안 바뀌는 걸 막을 수 있음)
  Future<void> submitResult(String sessionId, String uid,
      {required int seconds,
      required double km,
      required int kcal,
      String? mood}) async {
    final ref = _db.collection('sessions').doc(sessionId);
    final isFirstSubmit = await _db.runTransaction((tx) async {
      final doc = await tx.get(ref);
      final outcome = SessionRules.submit(doc.data(), uid,
          seconds: seconds, km: km, kcal: kcal, mood: mood);
      tx.update(ref, outcome.update);
      return outcome.isFirstSubmit;
    });
    // 재시도로 같은 세션을 두 번 제출해도 이번 달 거리/횟수가 두 번 더해지지
    // 않도록, 이 세션에 내 기록이 처음 올라간 경우에만 집계를 올림
    if (isFirstSubmit) await _bumpMonthlyStats(uid, km);
  }

  /// 세션이 없는 러닝(자유런·고스트런)의 결과. 남길 것은 집계뿐이다 —
  /// 상대의 기록을 기다릴 것도, 합산할 것도 없다.
  ///
  /// 고스트는 여기서 남기지 않는다. 그건 `runs/{runId}`의 일이고, 집계와
  /// 고스트는 실패해도 되는 정도가 다르다 — 집계가 틀리면 사용자의 기록이
  /// 틀리지만, 고스트가 빠지면 내일의 동행 하나가 없을 뿐이다
  Future<void> submitSoloResult(String uid, {required double km}) =>
      _bumpMonthlyStats(uid, km);

  // 고스트(케이던스 타임라인·사연)는 여기가 아니라 `runs/{runId}`에 남는다 —
  // `lib/services/ghost/ghost_service.dart`. 세션 문서에 넣지 않은 이유는
  // **혼자 달린 러닝에는 세션이 없기 때문**이다. §3-2가 요구하는 것은
  // "모든 러닝이 고스트가 된다"이고, 세션 안에만 두면 솔로런이 영영 고스트가
  // 되지 못한다. 기록기를 러닝 화면에 배선하는 것은 P5(화면 재작성)에서 한다.

  /// 홈 프로필 카드의 '이번 달 km / 함께 달림', finish 타이틀 변주용
  /// 주간 스트릭 — 전체 재조회 대신 users/{uid}에 집계 필드로 유지
  /// (읽기 비용을 늘리지 않기 위함)
  Future<void> _bumpMonthlyStats(String uid, double km) async {
    final now = DateTime.now();
    final monthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final weekKey = weekKeyOf(now);
    final userRef = _db.collection('users').doc(uid);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(userRef);
      final data = snap.data() ?? {};
      final sameMonth = data['monthKey'] == monthKey;
      final prevMonthKm =
          sameMonth ? ((data['monthKm'] ?? 0) as num).toDouble() : 0.0;

      final lastRunWeek = data['lastRunWeek'] as String?;
      int weekStreak;
      if (lastRunWeek == weekKey) {
        weekStreak = ((data['weekStreak'] ?? 1) as num).toInt();
      } else if (lastRunWeek != null && isPrevWeek(lastRunWeek, weekKey)) {
        weekStreak = ((data['weekStreak'] ?? 0) as num).toInt() + 1;
      } else {
        weekStreak = 1;
      }

      tx.update(userRef, {
        'monthKey': monthKey,
        'monthKm': prevMonthKm + km,
        // 달이 바뀌면 monthKm은 0으로 돌아간다. '우리 여정 217km 지점'은
        // 돌아가면 안 되는 숫자라 따로 센다(§5-2 디브리핑, 결과 화면 ③)
        'totalKm': FieldValue.increment(km),
        'totalRuns': FieldValue.increment(1),
        'lastRunWeek': weekKey,
        'weekStreak': weekStreak,
      });
    });
  }

  /// 아직 시작 전(waiting/ready)인 세션만 취소함 — 이미 달리는 중이거나
  /// 끝난 세션을 오래된 정리 로직이 뒤늦게 취소해 기록을 날리지 않도록
  Future<void> cancelSession(String sessionId) =>
      _transition(sessionId, SessionRules.cancel);

  /// 특정 상대와 함께 끝낸 세션들 — '우리' 탭 집계용
  /// (hostId/guestId 직접 비교 — participants arrayContains는 규칙상 거부됨)
  /// finished뿐 아니라, 내 결과는 올렸는데 상대가 영영 마치지 않아 24시간
  /// 넘게 running으로 멈춰 있는 세션도 사실상 끝난 것으로 보고 포함시킴
  Future<List<Map<String, dynamic>>> finishedSessionsWith(
      String myUid, String partnerUid) async {
    final col = _db.collection('sessions');
    final snaps = await Future.wait([
      col
          .where('hostId', isEqualTo: myUid)
          .where('guestId', isEqualTo: partnerUid)
          .where('status', isEqualTo: 'finished')
          .get(),
      col
          .where('hostId', isEqualTo: partnerUid)
          .where('guestId', isEqualTo: myUid)
          .where('status', isEqualTo: 'finished')
          .get(),
      col
          .where('hostId', isEqualTo: myUid)
          .where('guestId', isEqualTo: partnerUid)
          .where('status', isEqualTo: 'running')
          .get(),
      col
          .where('hostId', isEqualTo: partnerUid)
          .where('guestId', isEqualTo: myUid)
          .where('status', isEqualTo: 'running')
          .get(),
    ]);
    final finished = [...snaps[0].docs, ...snaps[1].docs];
    final stuckRunning = [...snaps[2].docs, ...snaps[3].docs]
        .where((d) => SessionRules.isStaleRunning(d.data(), myUid, DateTime.now()));
    final list = [...finished, ...stuckRunning]
        .map((d) => {'id': d.id, ...d.data()})
        .toList();
    list.sort((a, b) {
      final ta = (a['startedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
      final tb = (b['startedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
      return tb.compareTo(ta);
    });
    return list;
  }
}
