import 'package:cloud_firestore/cloud_firestore.dart';

/// 친구 연결 — 아이디 검색 방식 (전화번호 인증 없이 가장 단순하게).
/// 이미 앱을 쓰는 사람끼리만 연결 가능 — 초대 코드로 미가입자를 데려오는
/// 방식은 의도적으로 없앰
///
/// 검색과 연결은 두 단계로 나뉘어 있음: [lookupByUsername]으로 상대가
/// 누구인지 먼저 보여주고, 사용자가 확인한 뒤에야 [connect]로 실제 연결함
/// (한 번의 탭으로 되돌릴 수 없는 연결이 만들어지지 않도록)
class FriendService {
  final _db = FirebaseFirestore.instance;

  /// 아이디로 상대 찾기 — 아직 연결하지 않고 "누구인지"만 돌려줌
  Future<FriendCandidate?> lookupByUsername(String rawUsername) async {
    final username = normalizeUsername(rawUsername);
    if (username.isEmpty) return null;

    final handle = await _db.collection('usernames').doc(username).get();
    if (!handle.exists) return null;

    final uid = handle.data()?['uid'] as String?;
    if (uid == null) return null;

    // 탈퇴 등으로 아이디 문서만 남아 있는 경우 — 없는 사람으로 취급
    final user = await _db.collection('users').doc(uid).get();
    if (!user.exists) return null;

    return FriendCandidate(
      uid: uid,
      name: (user.data()?['name'] as String?) ?? '이름 없음',
      username: username,
    );
  }

  /// 실제 연결 (양방향). 어떤 이유로 실패했는지 호출부가 정확히 안내할 수
  /// 있도록 성공/실패를 결과 타입으로 구분함 — 예전에는 전부 null이라
  /// "이미 친구"도 "나 자신"도 네트워크 오류처럼 보였음
  Future<FriendAddResult> connect(String myUid, String friendUid) async {
    if (friendUid == myUid) return FriendAddResult.myself;

    final me = await _db.collection('users').doc(myUid).get();
    final myFriends = List<String>.from(me.data()?['friends'] ?? const []);
    if (myFriends.contains(friendUid)) return FriendAddResult.alreadyFriend;

    final batch = _db.batch();
    batch.update(_db.collection('users').doc(myUid), {
      'friends': FieldValue.arrayUnion([friendUid]),
    });
    batch.update(_db.collection('users').doc(friendUid), {
      'friends': FieldValue.arrayUnion([myUid]),
    });
    await batch.commit();
    return FriendAddResult.connected;
  }

  /// 친구 삭제 (양방향) — 잘못 연결했거나 더 이상 함께 달리고 싶지 않을 때.
  /// 지난 세션 기록은 남지만 서로의 목록에서는 사라지고, 세션 생성 규칙상
  /// 상대는 더 이상 나에게 GO? 요청을 보낼 수 없게 됨
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

  /// 내 친구 목록 실시간 스트림.
  ///
  /// 내 문서는 러닝이 끝날 때마다(monthKm 등) 갱신되므로, 친구 uid 목록이
  /// 실제로 바뀐 경우에만 상대 문서를 다시 읽음. 또 친구 한 명의 문서를
  /// 읽지 못해도 목록 전체가 죽지 않도록 개별로 감싸둠 — 예전에는 한 건만
  /// 실패해도 스트림이 끊겨 홈이 영영 "친구 없음"으로 굳었음
  Stream<List<Map<String, dynamic>>> friendsStream(String myUid) {
    return _db
        .collection('users')
        .doc(myUid)
        .snapshots()
        .map((doc) => List<String>.from(doc.data()?['friends'] ?? const []))
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
  static String normalizeUsername(String raw) => raw.trim().toLowerCase();
}

/// 검색으로 찾은 상대 — 연결 전에 "이 사람이 맞는지" 보여주기 위한 값
class FriendCandidate {
  final String uid;
  final String name;
  final String username;
  const FriendCandidate(
      {required this.uid, required this.name, required this.username});
}

enum FriendAddResult { connected, alreadyFriend, myself }
