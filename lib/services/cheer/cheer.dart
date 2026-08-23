// 응원 — 도착은 오늘, 재생은 **다음 러닝의 출발선**(§5-4).
//
// 반응을 즉시 소모하면 도파민이 그 자리에서 끝난다. 다음 러닝 시작에
// 아껴두면 여운이 연료가 되고, 세션이 직선이 아니라 고리가 된다.
// 그래서 응원에는 상태가 있다: 도착했지만 아직 안 들려준 것(queued)과
// 들려준 것(bridged).
import 'package:cloud_firestore/cloud_firestore.dart';

enum CheerStatus {
  /// 도착했다. 푸시로 **예고만** 나갔고 내용은 아직 재생되지 않았다
  queued('queued'),

  /// 다음 러닝 intro에서 재생됐다
  bridged('bridged');

  const CheerStatus(this.wire);

  final String wire;

  static CheerStatus fromWire(String? s) =>
      values.firstWhere((v) => v.wire == s, orElse: () => queued);
}

class Cheer {
  const Cheer({
    required this.id,
    required this.fromUid,
    required this.toUid,
    required this.createdAt,
    this.runId,
    this.status = CheerStatus.queued,
  });

  final String id;
  final String fromUid;
  final String toUid;

  /// 어떤 러닝을 보고 보낸 응원인가. 고스트런이면 그 고스트의 러닝
  final String? runId;

  final CheerStatus status;
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
        'fromUid': fromUid,
        'toUid': toUid,
        'status': status.wire,
        if (runId != null) 'runId': runId,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  static Cheer? fromMap(String id, Map<String, dynamic>? m) {
    if (m == null) return null;
    final at = DateTime.tryParse((m['createdAt'] as String?) ?? '');
    final from = m['fromUid'] as String?;
    final to = m['toUid'] as String?;
    if (at == null || from == null || to == null) return null;
    return Cheer(
      id: id,
      fromUid: from,
      toUid: to,
      runId: m['runId'] as String?,
      status: CheerStatus.fromWire(m['status'] as String?),
      createdAt: at,
    );
  }
}

/// 다음 러닝의 intro에서 **무엇을 들려줄 것인가**.
///
/// 쌓인 것을 전부 트는 것이 성의처럼 보이지만 아니다 — intro는 1분이고,
/// 응원 소리가 열 번 연달아 울리면 그건 응원이 아니라 알림 폭탄이다.
/// 그리고 한 사람이 세 번 보냈다고 그 사람이 세 배 반가운 것도 아니다.
class CheerBridge {
  const CheerBridge._();

  /// 한 번의 intro가 담을 수 있는 수. 셋을 넘기면 마지막 것이 첫 것의
  /// 여운을 지운다
  static const kMaxPerIntro = 3;

  /// 재생할 것을 고른다. **같은 사람의 것은 가장 최근 하나로 묶고**,
  /// 오래된 사람부터 들려준다 — 먼저 기다린 쪽이 먼저다.
  ///
  /// 고르고 남은 것도 호출부가 bridged로 표시해야 한다. 안 그러면 다음
  /// 러닝에서 같은 응원이 또 후보가 되고, 영영 밀린 사람이 생긴다
  static List<Cheer> pick(List<Cheer> queued, {int max = kMaxPerIntro}) {
    final latestByPerson = <String, Cheer>{};
    for (final c in queued) {
      if (c.status != CheerStatus.queued) continue;
      final seen = latestByPerson[c.fromUid];
      if (seen == null || c.createdAt.isAfter(seen.createdAt)) {
        latestByPerson[c.fromUid] = c;
      }
    }
    final out = latestByPerson.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return out.take(max).toList();
  }
}

class CheerService {
  CheerService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _cheers =>
      _db.collection('cheers');

  /// 응원을 남긴다. **발송은 서버가 한다** — 앱은 문서를 만들 뿐이고
  /// Cloud Function이 그걸 보고 예고 푸시를 보낸다(CLAUDE.md)
  Future<void> send({
    required String fromUid,
    required String toUid,
    String? runId,
    DateTime? now,
  }) async {
    if (fromUid == toUid) return; // 나에게 보내는 응원은 만들지 않는다
    await _cheers.add(Cheer(
      id: '',
      fromUid: fromUid,
      toUid: toUid,
      runId: runId,
      createdAt: now ?? DateTime.now(),
    ).toMap());
  }

  /// 다음 러닝 시작에 들려줄 후보. 세션 시작 **전에** 받아둔다 —
  /// 달리는 중에 네트워크를 기다리면 그 순간 러너는 화면을 보게 된다
  Future<List<Cheer>> queuedFor(String uid, {int limit = 20}) async {
    final q = await _cheers
        .where('toUid', isEqualTo: uid)
        .where('status', isEqualTo: CheerStatus.queued.wire)
        .orderBy('createdAt')
        .limit(limit)
        .get();
    return q.docs
        .map((d) => Cheer.fromMap(d.id, d.data()))
        .whereType<Cheer>()
        .toList();
  }

  /// 들려준 것으로 표시한다. 고른 것뿐 아니라 **같이 묶인 것까지** 표시해야
  /// 다음 러닝에서 같은 응원이 또 후보가 되지 않는다
  Future<void> markBridged(Iterable<String> ids) async {
    if (ids.isEmpty) return;
    final batch = _db.batch();
    for (final id in ids) {
      batch.update(_cheers.doc(id), {'status': CheerStatus.bridged.wire});
    }
    await batch.commit();
  }
}
