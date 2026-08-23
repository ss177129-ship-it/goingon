import 'package:cloud_firestore/cloud_firestore.dart';

import 'resonance.dart' show SignalKind;
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
  /// **late**인 이유: 서비스를 만드는 것만으로 Firebase를 건드리면, 이
  /// 서비스를 필드로 갖는 위젯은 Firebase 없이는 만들어지지도 않는다.
  /// 실제로 친구 찾기 시트를 위젯 테스트로 열 수 없었다(2026-08-16)
  late final _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _req(String from, String to) =>
      _db.collection('friendRequests').doc('${from}_$to');

  /// 페이스메이트 간선 — **진실의 원천**(P6.5).
  ///
  /// `users.friends`(옛 구조)와 `users.following`(새 구조)은 규칙이 쓰려고
  /// 두는 **투영**이다. 목록 규칙이 `exists(follows/...)`를 쓰면 평가하는
  /// 문서마다 경로가 달라져 접근 한도(10)를 넘긴다 — 내 문서 하나를 읽는
  /// 배열 방식은 몇 명이든 한 번으로 끝난다.
  ///
  /// 구조가 비대칭인 이유는 v1.1의 게이트형 DM이 '맞팔' 위에 설계돼 있기
  /// 때문이다. v1.0의 UI는 단일 상태(맺어졌거나 아니거나)라 수락 시 두
  /// 간선이 함께 생기지만, 나중에 한쪽만 남는 상태를 표현할 수 있어야
  /// 그때 다시 이관하지 않는다
  DocumentReference<Map<String, dynamic>> _edge(String follower, String followee) =>
      _db.collection('follows').doc('${follower}_$followee');

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
    final myBlocked = List<String>.from(me.data()?['blocked'] ?? const []);
    if (myBlocked.contains(otherUid)) return FriendRelation.blockedByMe;
    // 이관 중에는 계정마다 어느 배열에 들어 있는지가 다르다. 둘 다 본다
    if (mateUids(me.data()).contains(otherUid)) return FriendRelation.friend;

    final sent = await _req(myUid, otherUid).get();
    if (sent.exists) return FriendRelation.requestSent;
    final received = await _req(otherUid, myUid).get();
    if (received.exists) return FriendRelation.requestReceived;

    return FriendRelation.none;
  }

  // ── 요청 ────────────────────────────────────────────────────────────

  /// 요청 보내기. 문서 id가 고정이라 여러 번 눌러도 요청은 하나만 남음.
  ///
  /// [cheer]는 요청에 얹는 **응원 사운드 하나**다. 자유 텍스트를 두지 않는
  /// 이유는 첫 접촉이 곧 자유 입력이 되면 그 순간부터 이 앱이 유해 텍스트를
  /// 걸러야 하는 제품이 되기 때문이고, 애초에 여기서 필요한 것은 문장이
  /// 아니라 "반갑다"는 소리 하나다
  Future<void> sendRequest(
    String myUid,
    String toUid, {
    SignalKind cheer = SignalKind.cheer,
  }) async {
    await _req(myUid, toUid).set({
      'fromUid': myUid,
      'toUid': toUid,
      'cheer': cheer.gestureType,
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
          cheer: SignalKind.fromGestureType(
              (snap.docs[i].data()['cheer'] as String?) ?? ''),
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
    // 두 간선을 함께 만든다. v1.0의 UI는 단일 상태라 수락은 곧 맞팔이다 —
    // 비대칭은 구조가 표현할 수 있을 뿐 아직 일어나지 않는다
    batch.set(_edge(fromUid, myUid),
        {'followerUid': fromUid, 'followeeUid': myUid,
         'createdAt': FieldValue.serverTimestamp()});
    batch.set(_edge(myUid, fromUid),
        {'followerUid': myUid, 'followeeUid': fromUid,
         'createdAt': FieldValue.serverTimestamp()});
    // 서로 요청을 보낸 상태라면 반대쪽도 정리 — 남겨두면 상대 목록에 유령
    // 요청이 남고, 이미 친구라 수락이 규칙에서 거부됨.
    // (존재하지 않는 문서를 지우려 하면 규칙이 resource를 못 읽어 거부되므로
    //  반드시 확인 후에만 배치에 넣어야 함)
    if ((await _req(myUid, fromUid).get()).exists) {
      batch.delete(_req(myUid, fromUid));
    }
    // 두 배열에 함께 쓴다(expand). friends는 이관이 끝나면 사라진다
    batch.update(_db.collection('users').doc(myUid), {
      'friends': FieldValue.arrayUnion([fromUid]),
      'following': FieldValue.arrayUnion([fromUid]),
    });
    batch.update(_db.collection('users').doc(fromUid), {
      'friends': FieldValue.arrayUnion([myUid]),
      'following': FieldValue.arrayUnion([myUid]),
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
    // 간선은 있거나 없다 — 없는 것을 지워도 규칙이 resource를 못 읽어
    // 거부되므로, 존재를 확인한 것만 배치에 넣는다(친구 요청에서 겪은 함정)
    for (final ref in [_edge(myUid, friendUid), _edge(friendUid, myUid)]) {
      if ((await ref.get()).exists) batch.delete(ref);
    }
    batch.update(_db.collection('users').doc(myUid), {
      'friends': FieldValue.arrayRemove([friendUid]),
      'following': FieldValue.arrayRemove([friendUid]),
    });
    batch.update(_db.collection('users').doc(friendUid), {
      'friends': FieldValue.arrayRemove([myUid]),
      'following': FieldValue.arrayRemove([myUid]),
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
    for (final ref in [_edge(myUid, otherUid), _edge(otherUid, myUid)]) {
      if ((await ref.get()).exists) batch.delete(ref);
    }
    batch.update(_db.collection('users').doc(myUid), {
      'blocked': FieldValue.arrayUnion([otherUid]),
      'friends': FieldValue.arrayRemove([otherUid]),
      'following': FieldValue.arrayRemove([otherUid]),
    });
    batch.update(_db.collection('users').doc(otherUid), {
      'friends': FieldValue.arrayRemove([myUid]),
      'following': FieldValue.arrayRemove([myUid]),
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
      _shared.of(myUid, () => _mateProfiles(myUid));

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

  Stream<List<Map<String, dynamic>>> _mateProfiles(String myUid) {
    return _db
        .collection('users')
        .doc(myUid)
        .snapshots()
        .map((doc) => mateUids(doc.data()))
        .distinct(_sameIds)
        .asyncMap(_loadProfiles);
  }

  /// 페이스메이트 uid — **두 구조의 합집합**(expand 단계).
  ///
  /// 이관 전 계정은 friends에만, 이관 후 계정은 following에만 들어 있다.
  /// 둘 다 보면 이관 도중 어느 시점에도 목록이 비지 않는다. contract에서
  /// following 하나만 남는다
  static List<String> mateUids(Map<String, dynamic>? user) {
    final out = <String>{
      ...List<String>.from(user?['following'] ?? const []),
      ...List<String>.from(user?['friends'] ?? const []),
    };
    return out.toList()..sort();
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

  /// 요청에 얹혀 온 응원 사운드 하나. 자유 텍스트가 없는 자리라
  /// **이것이 첫 인사의 전부**다
  final SignalKind cheer;

  const FriendRequest({
    required this.fromUid,
    required this.name,
    required this.username,
    this.photoUrl,
    this.createdAt,
    this.cheer = SignalKind.cheer,
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
