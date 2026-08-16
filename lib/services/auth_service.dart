import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'avatar_service.dart';
import 'push_service.dart';

/// 인증 전략: Apple 또는 Google 로그인 필수 — 익명 로그인 없음.
/// 어떤 방법으로 로그인하든 성공 후에는 항상 닉네임 설정 화면(NicknameScreen)을
/// 거쳐 홈으로 이동 — 제공자가 이름을 줬든 안 줬든 흐름이 하나로 통일됨.
/// 카카오 등 Apple 이외의 다른 소셜로그인은 도입 시 'Sign in with Apple' 의무가
/// 생기므로 계속 미룸 — Apple이 이미 있으므로 Google 추가는 그 규정과 무관.
class AuthService {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  User? get user => _auth.currentUser;
  String get uid => _auth.currentUser!.uid;

  /// Apple로 로그인/재로그인. 예전에 같은 Apple 계정으로 가입했다면 Firebase가
  /// 같은 uid를 그대로 돌려줘서 재설치 후 복구가 됨.
  ///
  /// 프로필은 여기서 만들지 않음 — Apple이 이름을 줬는지 여부와 관계없이
  /// 항상 NicknameScreen을 거쳐 ensureProfile()을 호출하는 것으로 통일.
  /// 반환값은 Apple이 최초 인가 시에만 주는 이름(있으면 닉네임 화면의
  /// 초기값으로 사용, 없으면 null).
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
    await _auth.signInWithCredential(oauthCredential);

    final name = [appleCredential.givenName, appleCredential.familyName]
        .whereType<String>()
        .join(' ')
        .trim();
    return name.isEmpty ? null : name;
  }

  /// Google로 로그인/재로그인. Apple과 동일하게 프로필은 여기서 만들지 않고
  /// 이름만 반환 — 항상 NicknameScreen을 거쳐 홈으로 가는 흐름으로 통일.
  /// Google은 매번 이름을 주므로 대부분 닉네임 화면에 바로 채워질 것.
  Future<String?> signInWithGoogle() async {
    final googleUser = await GoogleSignIn.instance.authenticate();
    final idToken = googleUser.authentication.idToken;
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    await _auth.signInWithCredential(credential);
    return googleUser.displayName;
  }

  /// 프로필이 **쓸 수 있는 상태**인가. 문서가 있는 것만으로는 부족하다 —
  /// 아이디가 없으면 아무도 그 사람을 검색으로 찾을 수 없고, 이름이 없으면
  /// 상대 화면에 빈칸이 뜬다.
  ///
  /// 예전에는 문서 존재만 확인해서, 아이디 없는 계정이 그대로 홈까지
  /// 들어갔다. 실제로 7명 중 6명이 아이디 없이 쓰고 있었다(2026-08-16 확인)
  static bool isProfileComplete(Map<String, dynamic>? profile) {
    if (profile == null) return false;
    final name = (profile['name'] as String?)?.trim() ?? '';
    final username = (profile['username'] as String?)?.trim() ?? '';
    return name.isNotEmpty && username.isNotEmpty;
  }

  /// 프로필 생성 또는 **모자란 부분 채우기**.
  ///
  /// 문서가 이미 있어도 이름이나 아이디가 비어 있으면 그것만 채운다.
  /// 예전에는 문서가 있으면 곧바로 true를 돌려줘서, 아이디 없는 기존 계정이
  /// 이 화면을 지나가도 **아무것도 저장되지 않았다.**
  ///
  /// 아이디가 이미 다른 사람 것이면 false(호출부가 다시 묻게 함).
  /// 이름보다 아이디를 먼저 처리하는 이유: 충돌로 되돌아갈 때 이름만
  /// 바뀐 어정쩡한 상태가 남지 않게 하기 위해
  Future<bool> ensureProfile(String nickname, String username) async {
    final ref = _db.collection('users').doc(uid);
    final existing = await ref.get();
    if (existing.exists) {
      final data = existing.data();
      if (isProfileComplete(data)) return true;

      final hasUsername =
          ((data?['username'] as String?)?.trim() ?? '').isNotEmpty;
      if (!hasUsername && !await setUsername(username)) return false;

      final hasName = ((data?['name'] as String?)?.trim() ?? '').isNotEmpty;
      if (!hasName) await updateName(nickname);
      return true;
    }

    final usernameRef = _db.collection('usernames').doc(username);
    final usernameDoc = await usernameRef.get();
    if (usernameDoc.exists) return false;

    final batch = _db.batch();
    batch.set(ref, {
      'name': nickname,
      'username': username,
      'friends': <String>[],
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(usernameRef, {'uid': uid});
    await batch.commit();
    return true;
  }

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
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

  /// 아이디(검색용 고유 핸들) 설정/변경. 이미 다른 사람이 쓰고 있으면
  /// false를 반환함 — 흔히 있는 "충돌" 상황이라 예외로 다루지 않음
  Future<bool> setUsername(String username) async {
    final newRef = _db.collection('usernames').doc(username);
    final existing = await newRef.get();
    if (existing.exists && existing.data()!['uid'] != uid) return false;

    final myRef = _db.collection('users').doc(uid);
    final myDoc = await myRef.get();
    final oldUsername = myDoc.data()?['username'] as String?;

    final batch = _db.batch();
    if (oldUsername != null && oldUsername != username) {
      batch.delete(_db.collection('usernames').doc(oldUsername));
    }
    batch.set(newRef, {'uid': uid});
    batch.update(myRef, {'username': username});
    await batch.commit();
    return true;
  }

  Future<void> signOut() async {
    // 이 기기 푸시 토큰을 먼저 떼어냄 — 안 지우면 다음에 이 폰으로 로그인한
    // 사람에게 이전 사용자의 알림이 갈 수 있음
    if (user != null) await PushService.instance.unregister(uid);
    // Apple로만 로그인한 경우 구글 세션이 없어 실패할 수 있음 — 무시
    await GoogleSignIn.instance.signOut().catchError((_) {});
    await _auth.signOut();
  }

  /// 회원탈퇴 — 친구들의 목록에서 나를 지우고 내 계정/아이디를 삭제
  Future<void> deleteAccount() async {
    final myUid = uid;
    final doc = await _db.collection('users').doc(myUid).get();
    final data = doc.data();
    final username = data?['username'] as String?;
    final friends = List<String>.from(data?['friends'] ?? []);

    final batch = _db.batch();
    for (final f in friends) {
      batch.update(_db.collection('users').doc(f), {
        'friends': FieldValue.arrayRemove([myUid]),
      });
    }
    batch.delete(_db.collection('users').doc(myUid));
    if (username != null) {
      batch.delete(_db.collection('usernames').doc(username));
    }
    await batch.commit();

    // 프로필 사진은 Storage에 따로 있어서 배치로 지워지지 않음. Auth 계정을
    // 지우기 전에 처리해야 함 — 로그인이 풀리면 규칙상 내 파일도 못 지움.
    // 사진이 없는 계정이 대부분이고 여기서 실패해도 탈퇴는 이어져야 하므로
    // 예외를 삼킴(고아 파일은 나중에 정리 가능)
    try {
      await AvatarService().deleteFile(myUid);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
    }

    // Auth 계정 삭제는 세션이 오래됐으면 requires-recent-login으로 실패할 수
    // 있음. 그 시점엔 Firestore 데이터가 이미 지워진 뒤라 '탈퇴 실패'로 보이면
    // 안 되므로, 실패해도 최소한 로그아웃까지는 시켜 데이터/로그인 상태가
    // 어긋나지 않게 함
    try {
      await _auth.currentUser?.delete();
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      await _auth.signOut();
    }
    await GoogleSignIn.instance.disconnect().catchError((_) {});
  }
}
