import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// MVP 인증 전략: 익명 로그인 + 닉네임을 기본으로 하되, Apple 로그인을
/// 기존 익명 계정에 "연결"할 수 있게 함 — 마찰 0 온보딩은 유지하면서
/// 로그아웃/재설치 후에도 복구 가능하게 하는 게 목적. 카카오/구글 등
/// 다른 소셜로그인은 도입 시 'Sign in with Apple' 의무가 생기므로 v1.1로 미룸
/// (Apple 하나만 추가하는 건 그 규정과 무관해서 지금 넣어도 안전함).
class AuthService {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  User? get user => _auth.currentUser;
  String get uid => _auth.currentUser!.uid;

  /// 앱 첫 실행: 익명 계정 생성 + 프로필/초대 코드 발급
  Future<void> signInAnonymously(String nickname) async {
    if (_auth.currentUser == null) {
      await _auth.signInAnonymously();
    }
    await _ensureProfile(nickname);
  }

  /// Apple로 로그인. 이미 익명 세션이 있으면(설정에서 "계정 연결") 같은 uid에
  /// 자격증명만 덧붙여 친구·기록을 그대로 보존하고, 세션이 없으면(로그인 화면
  /// 최초 진입) 새로 로그인 — 예전에 같은 Apple 계정으로 가입했다면 Firebase가
  /// 같은 uid를 그대로 돌려줘서 재설치 후 복구가 됨.
  ///
  /// Apple은 이름을 최초 인가 시 단 한 번만 내려주므로, 받았으면 그 자리에서
  /// 프로필까지 만들고 이름을 반환함. 못 받았으면 null을 반환 — 이미 프로필이
  /// 있는 재로그인인지, 이름을 새로 물어봐야 하는 신규인지는 호출부에서
  /// myProfile()로 판단.
  Future<String?> signInWithApple() async {
    final rawNonce = _generateNonce();
    final nonce = _sha256(rawNonce);
    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: nonce,
    );
    final oauthCredential = OAuthProvider('apple.com').credential(
      idToken: appleCredential.identityToken,
      rawNonce: rawNonce,
      accessToken: appleCredential.authorizationCode,
    );

    if (_auth.currentUser != null && _auth.currentUser!.isAnonymous) {
      await _auth.currentUser!.linkWithCredential(oauthCredential);
    } else {
      await _auth.signInWithCredential(oauthCredential);
    }

    final name = [appleCredential.givenName, appleCredential.familyName]
        .whereType<String>()
        .join(' ')
        .trim();
    if (name.isEmpty) return null;
    await _ensureProfile(name);
    return name;
  }

  /// 초대 코드 발급을 포함한 프로필 생성 — 이미 프로필 문서가 있으면
  /// (계정 연결 케이스) 아무것도 하지 않음. 그렇지 않으면 친구 목록/
  /// 초대코드가 새로 덮어써져 기존 데이터를 잃게 됨
  Future<void> _ensureProfile(String nickname) async {
    final ref = _db.collection('users').doc(uid);
    final existing = await ref.get();
    if (existing.exists) return;

    final code = _generateInviteCode();
    final batch = _db.batch();
    batch.set(ref, {
      'name': nickname,
      'inviteCode': code,
      'friends': <String>[],
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(_db.collection('inviteCodes').doc(code), {'uid': uid});
    await batch.commit();
  }

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final r = Random.secure();
    return List.generate(length, (_) => charset[r.nextInt(charset.length)])
        .join();
  }

  String _sha256(String input) => sha256.convert(utf8.encode(input)).toString();

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
