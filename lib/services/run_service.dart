import 'package:cloud_firestore/cloud_firestore.dart';

import 'week_key.dart';

/// GO? 요청이 살아 있는 시간. 이보다 오래된 대기 세션은 뒤늦게 수락 시트로
/// 띄우지 않고 정리하고, 같은 상대에게 다시 보낼 때도 재사용하지 않음
const kRequestTtl = Duration(minutes: 30);

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
  Future<String> createSession(String hostId, String guestId) async {
    final existing = await _findPendingSession(hostId, guestId);
    if (existing != null) return existing;

    final ref = await _db.collection('sessions').add({
      'hostId': hostId,
      'guestId': guestId,
      'participants': [hostId, guestId],
      'status': 'waiting',
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
          .where('status', whereIn: ['waiting', 'ready']).get();
      for (final doc in snap.docs) {
        final createdAt = doc.data()['createdAt'] as Timestamp?;
        if (createdAt == null) continue; // 서버 시각 반영 전 — 판단 보류
        if (DateTime.now().difference(createdAt.toDate()) < kRequestTtl) {
          return doc.id;
        }
      }
    } catch (_) {
      // 인덱스/네트워크 문제로 확인에 실패하면 새로 만드는 쪽으로 — 중복
      // 세션은 불편할 뿐이지만, 여기서 던지면 GO? 자체가 막힘
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

  /// 나에게 온 대기 중 세션 감지 (홈 화면에서 구독)
  Stream<QuerySnapshot<Map<String, dynamic>>> incomingSessions(String myUid) {
    return _db
        .collection('sessions')
        .where('guestId', isEqualTo: myUid)
        .where('status', whereIn: ['waiting', 'ready']).snapshots();
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

  /// 취소된 세션이 뒤늦게 부활하지 않도록 트랜잭션으로 상태를 먼저 확인
  Future<void> setReady(String sessionId, String uid) async {
    final ref = _db.collection('sessions').doc(sessionId);
    await _db.runTransaction((tx) async {
      final doc = await tx.get(ref);
      if (doc.data()?['status'] == 'cancelled') return;
      tx.update(ref, {
        'ready.$uid': true,
        'status': 'ready',
      });
    });
  }

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
      final data = doc.data();
      if (data?['status'] == 'cancelled') return;
      final alreadyStarted = data?['startedAt'] != null;
      tx.update(ref, {
        'status': 'running',
        if (!alreadyStarted) 'startedAt': FieldValue.serverTimestamp(),
      });
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
      final results = Map<String, dynamic>.from(doc.data()?['results'] ?? {});
      final alreadySubmitted = results.containsKey(uid);
      results[uid] = {
        'seconds': seconds,
        'km': km,
        'kcal': kcal,
        if (mood != null) 'mood': mood,
      };
      tx.update(ref, {
        'results.$uid': results[uid],
        if (results.length >= 2) 'status': 'finished',
      });
      return !alreadySubmitted;
    });
    // 재시도로 같은 세션을 두 번 제출해도 이번 달 거리/횟수가 두 번 더해지지
    // 않도록, 이 세션에 내 기록이 처음 올라간 경우에만 집계를 올림
    if (isFirstSubmit) await _bumpMonthlyStats(uid, km);
  }

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
        'totalRuns': FieldValue.increment(1),
        'lastRunWeek': weekKey,
        'weekStreak': weekStreak,
      });
    });
  }

  /// 아직 시작 전(waiting/ready)인 세션만 취소함 — 이미 달리는 중이거나
  /// 끝난 세션을 오래된 정리 로직이 뒤늦게 취소해 기록을 날리지 않도록
  Future<void> cancelSession(String sessionId, {String? declineMessage}) async {
    final ref = _db.collection('sessions').doc(sessionId);
    await _db.runTransaction((tx) async {
      final doc = await tx.get(ref);
      final status = doc.data()?['status'];
      if (status != 'waiting' && status != 'ready') return;
      tx.update(ref, {
        'status': 'cancelled',
        if (declineMessage != null) 'declineMessage': declineMessage,
      });
    });
  }

  /// GO? 요청을 거절하며 한 줄 답장을 남김 (침묵 대신 대화)
  Future<void> declineSession(String sessionId, String message) =>
      cancelSession(sessionId, declineMessage: message);

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
    final stuckRunning = [...snaps[2].docs, ...snaps[3].docs].where((d) {
      final data = d.data();
      final startedAt = data['startedAt'] as Timestamp?;
      if (startedAt == null) return false;
      final results = data['results'];
      final hasMyResult = results is Map && results.containsKey(myUid);
      return hasMyResult &&
          DateTime.now().difference(startedAt.toDate()) >
              const Duration(hours: 24);
    });
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
