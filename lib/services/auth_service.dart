import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// MVP 인증 전략: 익명 로그인 + 닉네임.
/// 이유: Apple 심사에서 소셜로그인(카카오 등)을 쓰면 'Sign in with Apple' 의무가 생겨요.
/// 익명+닉네임이면 그 의무가 없어 첫 출시가 가장 빨라요. 카카오/애플 로그인은 v1.1에서.
class AuthService {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  User? get user => _auth.currentUser;
  String get uid => _auth.currentUser!.uid;

  /// 앱 첫 실행: 익명 계정 생성 + 초대 코드 발급
  Future<void> signInAnonymously(String nickname) async {
    if (_auth.currentUser == null) {
      await _auth.signInAnonymously();
    }
    final code = _generateInviteCode();
    await _db.collection('users').doc(uid).set({
      'name': nickname,
      'inviteCode': code,
      'friends': <String>[],
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _db.collection('inviteCodes').doc(code).set({'uid': uid});
  }

  Future<Map<String, dynamic>?> myProfile() async {
    if (user == null) return null;
    final doc = await _db.collection('users').doc(uid).get();
    return doc.data();
  }

  Future<void> updateName(String name) async {
    await _db.collection('users').doc(uid).update({'name': name});
  }

  Future<void> signOut() => _auth.signOut();

  /// 회원탈퇴 — 친구들의 목록에서 나를 지우고 내 계정/초대코드를 삭제
  Future<void> deleteAccount() async {
    final myUid = uid;
    final doc = await _db.collection('users').doc(myUid).get();
    final data = doc.data();
    final code = data?['inviteCode'] as String?;
    final friends = List<String>.from(data?['friends'] ?? []);

    final batch = _db.batch();
    for (final f in friends) {
      batch.update(_db.collection('users').doc(f), {
        'friends': FieldValue.arrayRemove([myUid]),
      });
    }
    batch.delete(_db.collection('users').doc(myUid));
    if (code != null) {
      batch.delete(_db.collection('inviteCodes').doc(code));
    }
    await batch.commit();
    await _auth.currentUser?.delete();
  }

  /// GO-XXXX 형식 초대 코드 (혼동 문자 I/O/0/1 제외)
  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    final body = List.generate(4, (_) => chars[r.nextInt(chars.length)]).join();
    return 'GO-$body';
  }
}
