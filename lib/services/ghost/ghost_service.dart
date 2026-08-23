// 고스트의 저장·조회. Firestore 접근은 전부 여기 모은다.
//
// **세션 시작 전에 받아둔다**(§3-3 2막). 달리는 중에 네트워크를 기다리면
// 그 순간 러너는 화면을 보게 되고, 그건 §0 원칙 1을 깨는 일이다.
import 'package:cloud_firestore/cloud_firestore.dart';

import 'ghost_engine.dart';
import 'ghost_run.dart';

class GhostService {
  GhostService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _runs => _db.collection('runs');

  /// 러닝이 끝나면 고스트로 남긴다. **모든 러닝이 고스트가 된다**(§3-2)
  Future<String> save(GhostRun run) async {
    final ref = _runs.doc();
    await ref.set({...run.toMap(), 'createdAt': FieldValue.serverTimestamp()});
    return ref.id;
  }

  /// 세션 시작 전에 통째로 받아둔다
  Future<GhostRun?> fetch(String runId) async {
    final snap = await _runs.doc(runId).get();
    return GhostRun.fromMap(snap.id, snap.data());
  }

  /// '오늘의 상대' 후보 — 페이스메이트의 최근 러닝(§3-3 1막 우선순위 ①).
  ///
  /// 안부 가치가 가장 큰 것이 맨 앞이라 최신순이다. 알고리즘 큐레이션은
  /// 넣지 않는다(§6-2, v1) — 누구와 달릴지는 사람이 고른다
  Future<List<GhostRun>> recentFrom(List<String> uids, {int limit = 20}) async {
    if (uids.isEmpty) return const [];
    final out = <GhostRun>[];
    // whereIn은 30개까지라 나눠 던진다
    for (var i = 0; i < uids.length; i += 30) {
      final chunk = uids.sublist(i, (i + 30).clamp(0, uids.length));
      final q = await _runs
          .where('uid', whereIn: chunk)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      out.addAll(q.docs
          .map((d) => GhostRun.fromMap(d.id, d.data()))
          .whereType<GhostRun>());
    }
    out.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return out.where((g) => g.isUsable).take(limit).toList();
  }

  /// 나의 과거(§3-3 1막 우선순위 ②) — 처음 온 사람에게도 상대가 있다
  Future<List<GhostRun>> myOwn(String uid, {int limit = 20}) async {
    final q = await _runs
        .where('uid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return q.docs
        .map((d) => GhostRun.fromMap(d.id, d.data()))
        .whereType<GhostRun>()
        .where((g) => g.isUsable)
        .toList();
  }

  /// 함께 달렸다는 사실을 남긴다 → 서버가 이것을 보고 알림을 보낸다.
  /// **앱은 문서를 만들 뿐 발송하지 않는다**(CLAUDE.md)
  Future<void> recordCompanionship(GhostCompanionship c) async {
    if (!c.worthNotifying) return;
    await _runs
        .doc(c.ghostRunId)
        .collection('companions')
        .doc(c.companionUid)
        .set(c.toMap(), SetOptions(merge: true));
  }

  /// 공개 범위 변경 — 남긴 뒤에도 언제든 좁힐 수 있어야 한다
  Future<void> setVisibility(String runId, GhostVisibility v) =>
      _runs.doc(runId).update({'visibility': v.wire});
}
