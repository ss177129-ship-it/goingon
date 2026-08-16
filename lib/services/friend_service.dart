import 'package:cloud_firestore/cloud_firestore.dart';

import 'shared_stream.dart';

/// 친구 연결 — 아이디로 찾아 **요청을 보내고, 상대가 수락해야** 연결됨
/// (인스타 팔로우 요청 방식). 아이디를 아는 사람이 곧 연결 권한이 되는
/// 카톡 방식은 폐기함 — 동의 없는 연락을 막는 게 목적.
///
/// `friendRequests/{보낸사람uid}_{받는사람uid}`
///   문서의 **존재 자체가 "대기 중"**이고, 수락·거절·취소는 전부 삭제로 처리함.
///   그래서 status 필드가 없고, 받은 요청 조회도 toUid 단일 조건이라
///   복합 인덱스가 필요 없음. id가 고정이라 중복 요청도 구조적으로 불가능.
///
/// 차단(`users/{uid}.blocked`)은 요청·수락만으로 못 막는 반복 요청을 끊는 수단.
/// 차단한 상대에게는 검색에서도 내가 보이지 않음.
class FriendService {
  final _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _req(String from, String to) =>
      _db.collection('friendRequests').doc('${from}_$to');

  // ── 검색 ────────────────────────────────────────────────────────────

  /// 아이디로 상대 찾기. 연결하지 않고 "누구인지 + 지금 어떤 사이인지"만 돌려줌.
  /// 나를 차단한 상대는 아예 못 찾는 것으로 처리함(있다는 사실도 알리지 않음)
  Future<FriendCandidate?> lookupByUsername(String rawUsername, String myUid) async {
    final username = normalizeUsername(rawUsername);
    if (username.isEmpty) return null;

    final handle = await _db.collection('usernames').doc(username).get();
    if (!handle.exists) return null;
    final uid = handle.data()?['uid'] as String?;
    if (uid == null) return null;

    final them = await _db.collection('users').doc(uid).get();
    if (!them.exists) return null; // 탈퇴 등으로 아이디 문서만 남은 경우

    final theirBlocked = List<String>.from(them.data()?['blocked'] ?? const []);
    if (theirBlocked.contains(myUid)) return null; // 나를 차단함 → 없는 사람 취급

    return FriendCandidate(
      uid: uid,
      name: (them.data()?['name'] as String?) ?? '이름 없음',
      username: username,
      photoUrl: them.data()?['photoUrl'] as String?,
      relation: await _relationWith(myUid, uid),
    );
  }

  Future<FriendRelation> _relationWith(String myUid, String otherUid) async {
    if (otherUid == myUid) return FriendRelation.self;

    final me = await _db.collection('users').doc(myUid).get();
    final myFriends = List<String>.from(me.data()?['friends'] ?? const []);
    final myBlocked = List<String>.from(me.data()?['blocked'] ?? const []);
    if (myBlocked.contains(otherUid)) return FriendRelation.blockedByMe;
    if (myFriends.contains(otherUid)) return FriendRelation.friend;

    final sent = await _req(myUid, otherUid).get();
    if (sent.exists) return FriendRelation.requestSent;
    final received = await _req(otherUid, myUid).get();
    if (received.exists) return FriendRelation.requestReceived;

    return FriendRelation.none;
  }

  // ── 요청 ────────────────────────────────────────────────────────────

  /// 요청 보내기. 문서 id가 고정이라 여러 번 눌러도 요청은 하나만 남음
  Future<void> sendRequest(String myUid, String toUid) async {
    await _req(myUid, toUid).set({
      'fromUid': myUid,
      'toUid': toUid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// 보낸 요청 취소
  Future<void> cancelRequest(String myUid, String toUid) =>
      _req(myUid, toUid).delete();

  /// 나에게 온 대기 중 요청 (보낸 사람 프로필까지 붙여서).
  /// 친구 목록과 같은 이유로 개별 조회를 감싸둠 — 한 명을 못 읽어도
  /// 목록 전체가 죽지 않게
  Stream<List<FriendRequest>> incomingRequestsStream(String myUid) {
    return _db
        .collection('friendRequests')
        .where('toUid', isEqualTo: myUid)
        .snapshots()
        .asyncMap((snap) async {
      final senders = await Future.wait(
          snap.docs.map((d) => _tryGetUser(d.data()['fromUid'] as String)));
      final out = <FriendRequest>[];
      for (var i = 0; i < snap.docs.length; i++) {
        final sender = senders[i];
        if (sender == null || !sender.exists) continue;
        out.add(FriendRequest(
          fromUid: sender.id,
          name: (sender.data()?['name'] as String?) ?? '이름 없음',
          username: (sender.data()?['username'] as String?) ?? '',
          photoUrl: sender.data()?['photoUrl'] as String?,
          createdAt: (snap.docs[i].data()['createdAt'] as Timestamp?)?.toDate(),
        ));
      }
      out.sort((a, b) => (b.createdAt ?? DateTime(0))
          .compareTo(a.createdAt ?? DateTime(0)));
      return out;
    });
  }

  /// 수락 — 요청을 지우면서 양쪽 friends에 서로를 추가.
  /// 배치 안에서 요청 문서를 지워도 보안 규칙은 배치 이전 상태를 보므로
  /// "대기 중 요청이 있다"는 검사가 통과함
  Future<void> acceptRequest(String myUid, String fromUid) async {
    final batch = _db.batch();
    batch.delete(_req(fromUid, myUid));
    // 서로 요청을 보낸 상태라면 반대쪽도 정리 — 남겨두면 상대 목록에 유령
    // 요청이 남고, 이미 친구라 수락이 규칙에서 거부됨.
    // (존재하지 않는 문서를 지우려 하면 규칙이 resource를 못 읽어 거부되므로
    //  반드시 확인 후에만 배치에 넣어야 함)
    if ((await _req(myUid, fromUid).get()).exists) {
      batch.delete(_req(myUid, fromUid));
    }
    batch.update(_db.collection('users').doc(myUid), {
      'friends': FieldValue.arrayUnion([fromUid]),
    });
    batch.update(_db.collection('users').doc(fromUid), {
      'friends': FieldValue.arrayUnion([myUid]),
    });
    await batch.commit();
  }

  /// 거절 — 조용히 지움. 상대에게는 알리지 않음(거절 통보는 상처를 주고
  /// 재요청을 유발함). 상대가 다시 보내는 것은 막지 않으며, 반복되면 차단으로 해결
  Future<void> declineRequest(String myUid, String fromUid) =>
      _req(fromUid, myUid).delete();

  // ── 연결 끊기 / 차단 ────────────────────────────────────────────────

  /// 친구 삭제 (양방향). 지난 세션 기록은 남지만 서로의 목록에서 사라지고,
  /// 세션 생성 규칙상 상대는 더 이상 GO? 요청을 보낼 수 없게 됨
  Future<void> removeFriend(String myUid, String friendUid) async {
    final batch = _db.batch();
    batch.update(_db.collection('users').doc(myUid), {
      'friends': FieldValue.arrayRemove([friendUid]),
    });
    batch.update(_db.collection('users').doc(friendUid), {
      'friends': FieldValue.arrayRemove([myUid]),
    });
    await batch.commit();
  }

  /// 차단 — 연결을 끊고, 오가던 요청을 지우고, 다시 붙지 못하게 막음.
  /// 차단된 상대는 검색에서 나를 찾지 못하고 요청도 보낼 수 없음(규칙에서 거부)
  Future<void> blockUser(String myUid, String otherUid) async {
    final outgoing = await _req(myUid, otherUid).get();
    final incoming = await _req(otherUid, myUid).get();

    final batch = _db.batch();
    if (outgoing.exists) batch.delete(_req(myUid, otherUid));
    if (incoming.exists) batch.delete(_req(otherUid, myUid));
    batch.update(_db.collection('users').doc(myUid), {
      'blocked': FieldValue.arrayUnion([otherUid]),
      'friends': FieldValue.arrayRemove([otherUid]),
    });
    batch.update(_db.collection('users').doc(otherUid), {
      'friends': FieldValue.arrayRemove([myUid]),
    });
    await batch.commit();
  }

  Future<void> unblockUser(String myUid, String otherUid) async {
    await _db.collection('users').doc(myUid).update({
      'blocked': FieldValue.arrayRemove([otherUid]),
    });
  }

  /// 차단 목록 (프로필 붙여서) — 설정 화면에서 해제할 수 있게
  Stream<List<Map<String, dynamic>>> blockedStream(String myUid) =>
      _profilesFromField(myUid, 'blocked');

  // ── 친구 목록 ───────────────────────────────────────────────────────

  /// 내 친구 목록 실시간 스트림.
  ///
  /// 내 문서는 러닝이 끝날 때마다(monthKm 등) 갱신되므로, uid 목록이 실제로
  /// 바뀐 경우에만 상대 문서를 다시 읽음.
  ///
  /// 홈 탭과 '우리' 탭이 각각 구독하는데 `IndexedStack`이라 둘 다 살아 있다.
  /// 그대로 두면 같은 목록을 Firestore에서 두 번 듣게 되므로 [_shared]로
  /// 원본 구독을 하나로 묶는다 — 호출부는 평범한 스트림으로 쓰면 된다
  Stream<List<Map<String, dynamic>>> friendsStream(String myUid) =>
      _shared.of(myUid, () => _profilesFromField(myUid, 'friends'));

  /// 인스턴스가 화면마다 새로 만들어지므로 공유 캐시는 클래스 전체가 나눠 씀
  static final _shared = SharedStream<List<Map<String, dynamic>>>();

  Stream<List<Map<String, dynamic>>> _profilesFromField(
      String myUid, String field) {
    return _db
        .collection('users')
        .doc(myUid)
        .snapshots()
        .map((doc) => List<String>.from(doc.data()?[field] ?? const []))
        .distinct(_sameIds)
        .asyncMap(_loadProfiles);
  }

  Future<List<Map<String, dynamic>>> _loadProfiles(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final snaps = await Future.wait(ids.map(_tryGetUser));
    return [
      for (final s in snaps)
        if (s != null && s.exists) {'uid': s.id, ...s.data()!},
    ];
  }

  Future<DocumentSnapshot<Map<String, dynamic>>?> _tryGetUser(String id) async {
    try {
      return await _db.collection('users').doc(id).get();
    } catch (_) {
      return null;
    }
  }

  static bool _sameIds(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 입력한 아이디를 저장·검색 형태로 통일 (앞뒤 공백 제거 + 소문자)
  /// 검색어를 저장된 아이디 형태로 맞춘다.
  ///
  /// **앞의 `@`를 떼는 것이 핵심.** 앱은 아이디를 어디서나 `@ruty`로 보여주는데
  /// 검색창에는 `ruty`만 받으면, 화면에서 본 그대로 입력한 사람이 "그런 아이디
  /// 없음"을 보게 된다(2026-08-16 실제 제보). 저장은 `[a-z0-9_]`만 허용하므로
  /// `@`는 어떤 아이디에도 들어 있을 수 없어, 떼어내도 잃는 것이 없다.
  ///
  /// 가운데 공백도 지운다 — 복사해 붙이면 "@ ruty"처럼 끼어드는 일이 흔하다
  static String normalizeUsername(String raw) => raw
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s'), '')
      .replaceAll(RegExp(r'^@+'), '');
}

/// 검색으로 찾은 상대 — 연결 전에 "이 사람이 맞는지"와 "지금 어떤 사이인지"를
/// 함께 보여주기 위한 값
class FriendCandidate {
  final String uid;
  final String name;
  final String username;

  /// 프로필 사진(Storage 주소). 없으면 이름 첫 글자로 그림
  final String? photoUrl;
  final FriendRelation relation;
  const FriendCandidate({
    required this.uid,
    required this.name,
    required this.username,
    required this.relation,
    this.photoUrl,
  });
}

/// 나에게 온 대기 중 요청
class FriendRequest {
  final String fromUid;
  final String name;
  final String username;

  /// 프로필 사진(Storage 주소). 없으면 이름 첫 글자로 그림
  final String? photoUrl;
  final DateTime? createdAt;
  const FriendRequest({
    required this.fromUid,
    required this.name,
    required this.username,
    this.photoUrl,
    this.createdAt,
  });
}

enum FriendRelation {
  /// 아무 사이도 아님 — 요청을 보낼 수 있음
  none,

  /// 이미 친구
  friend,

  /// 내가 요청을 보내고 기다리는 중
  requestSent,

  /// 상대가 나에게 요청을 보내둠 — 수락하면 바로 연결
  requestReceived,

  /// 내가 차단한 상대
  blockedByMe,

  /// 나 자신
  self,
}
