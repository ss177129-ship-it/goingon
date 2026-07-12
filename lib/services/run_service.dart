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

  /// 둘 다 준비되면 호출 — 동시에 출발
  Future<void> startRun(String sessionId) async {
    await _db.collection('sessions').doc(sessionId).update({
      'status': 'running',
      'startedAt': FieldValue.serverTimestamp(),
    });
  }

  /// 내 결과 업로드. 상대 결과가 이미 있으면 세션 종료 처리
  Future<void> submitResult(String sessionId, String uid,
      {required int seconds, required double km, required int kcal}) async {
    final ref = _db.collection('sessions').doc(sessionId);
    await ref.update({
      'results.$uid': {'seconds': seconds, 'km': km, 'kcal': kcal},
    });
    final doc = await ref.get();
    final results = (doc.data()?['results'] ?? {}) as Map;
    if (results.length >= 2) {
      await ref.update({'status': 'finished'});
    }
  }

  Future<void> cancelSession(String sessionId) async {
    await _db.collection('sessions').doc(sessionId).update({
      'status': 'cancelled',
    });
  }

  /// 특정 상대와 함께 끝낸 세션들 — '우리' 탭 집계용
  /// (hostId/guestId 직접 비교 — participants arrayContains는 규칙상 거부됨)
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
    ]);
    final list = [...snaps[0].docs, ...snaps[1].docs]
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
