import 'package:cloud_firestore/cloud_firestore.dart';

/// 친구 연결 — 아이디 검색 방식 (전화번호 인증 없이 가장 단순하게).
/// 이미 앱을 쓰는 사람끼리만 연결 가능 — 초대 코드로 미가입자를 데려오는
/// 방식은 의도적으로 없앰
class FriendService {
  final _db = FirebaseFirestore.instance;

  /// 아이디로 친구 추가 (양방향) — 정확히 일치하는 아이디만 찾음
  /// 반환: 성공 시 친구 이름, 실패 시 null
  Future<String?> addFriendByUsername(String myUid, String rawUsername) async {
    final username = rawUsername.trim().toLowerCase();
    final userDoc = await _db.collection('usernames').doc(username).get();
    if (!userDoc.exists) return null;
    return _connectFriend(myUid, userDoc.data()!['uid'] as String);
  }

  Future<String?> _connectFriend(String myUid, String friendUid) async {
    if (friendUid == myUid) return null; // 자기 자신

    final batch = _db.batch();
    batch.update(_db.collection('users').doc(myUid), {
      'friends': FieldValue.arrayUnion([friendUid]),
    });
    batch.update(_db.collection('users').doc(friendUid), {
      'friends': FieldValue.arrayUnion([myUid]),
    });
    await batch.commit();

    final friendDoc = await _db.collection('users').doc(friendUid).get();
    return friendDoc.data()?['name'] as String?;
  }

  /// 내 친구 목록 실시간 스트림
  Stream<List<Map<String, dynamic>>> friendsStream(String myUid) {
    return _db
        .collection('users')
        .doc(myUid)
        .snapshots()
        .asyncMap((doc) async {
      final ids = List<String>.from(doc.data()?['friends'] ?? []);
      if (ids.isEmpty) return <Map<String, dynamic>>[];
      final snaps = await Future.wait(
          ids.map((id) => _db.collection('users').doc(id).get()));
      return snaps
          .where((s) => s.exists)
          .map((s) => {'uid': s.id, ...s.data()!})
          .toList();
    });
  }
}
