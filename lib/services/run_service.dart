import 'package:cloud_firestore/cloud_firestore.dart';

/// 함께 달리기 세션 (MVP 전략: 실시간 위치 동기화 없음 —
/// 함께 '시작'하고, 끝나면 결과를 '합산'. 라이브 합산은 v1.1)
///
/// sessions/{id}:
///   hostId, guestId, status: waiting|ready|running|finished
///   ready: {uid: bool}, startedAt
///   results: {uid: {seconds, km, kcal}}
class RunService {
  final _db = FirebaseFirestore.instance;

  /// GO? — 세션 생성 (상대는 홈에서 스냅샷으로 감지)
  Future<String> createSession(String hostId, String guestId) async {
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

  /// 나에게 온 대기 중 세션 감지 (홈 화면에서 구독)
  Stream<QuerySnapshot<Map<String, dynamic>>> incomingSessions(String myUid) {
    return _db
        .collection('sessions')
        .where('guestId', isEqualTo: myUid)
        .where('status', whereIn: ['waiting', 'ready']).snapshots();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> sessionStream(String id) =>
      _db.collection('sessions').doc(id).snapshots();

  Future<void> setReady(String sessionId, String uid) async {
    await _db.collection('sessions').doc(sessionId).update({
      'ready.$uid': true,
      'status': 'ready',
    });
  }

  /// "조금 늦을 것 같아요" — 상대 로비 화면에 실시간으로 반영됨
  Future<void> setLate(String sessionId, String uid, bool isLate) async {
    await _db.collection('sessions').doc(sessionId).update({
      'late.$uid': isLate,
    });
  }

  /// 둘 다 준비되면 호출 — 동시에 출발
  Future<void> startRun(String sessionId) async {
    await _db.collection('sessions').doc(sessionId).update({
      'status': 'running',
      'startedAt': FieldValue.serverTimestamp(),
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
    await _db.runTransaction((tx) async {
      final doc = await tx.get(ref);
      final results = Map<String, dynamic>.from(doc.data()?['results'] ?? {});
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
    });
    await _bumpMonthlyStats(uid, km);
  }

  /// 홈 프로필 카드의 '이번 달 km / 함께 달림', finish 타이틀 변주용
  /// 주간 스트릭 — 전체 재조회 대신 users/{uid}에 집계 필드로 유지
  /// (읽기 비용을 늘리지 않기 위함)
  Future<void> _bumpMonthlyStats(String uid, double km) async {
    final now = DateTime.now();
    final monthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final weekKey = _weekKey(now);
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
      } else if (lastRunWeek != null && _isPrevWeek(lastRunWeek, weekKey)) {
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

  /// 그 주 월요일 날짜(YYYY-MM-DD)를 키로 사용
  String _weekKey(DateTime d) {
    final monday =
        DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));
    return '${monday.year}-${monday.month.toString().padLeft(2, '0')}-'
        '${monday.day.toString().padLeft(2, '0')}';
  }

  bool _isPrevWeek(String lastWeekKey, String currentWeekKey) {
    final last = DateTime.parse(lastWeekKey);
    final current = DateTime.parse(currentWeekKey);
    return current.difference(last).inDays == 7;
  }

  Future<void> cancelSession(String sessionId) async {
    await _db.collection('sessions').doc(sessionId).update({
      'status': 'cancelled',
    });
  }

  /// GO? 요청을 거절하며 한 줄 답장을 남김 (침묵 대신 대화)
  Future<void> declineSession(String sessionId, String message) async {
    await _db.collection('sessions').doc(sessionId).update({
      'status': 'cancelled',
      'declineMessage': message,
    });
  }

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
