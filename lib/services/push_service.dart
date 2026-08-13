import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// 앱을 켜지 않아도 친구 요청·러닝 요청을 받기 위한 푸시 알림.
///
/// 실제 발송은 Cloud Functions(`functions/src/index.ts`)가 하고, 여기서는
/// 기기 토큰을 `users/{uid}.fcmTokens`에 등록·정리하고 알림 탭을 처리한다.
///
/// 토큰을 **배열로** 두는 이유: 한 사람이 아이폰과 아이패드를 같이 쓸 수 있고,
/// 재설치하면 새 토큰이 생긴다. 죽은 토큰은 발송 시점에 서버가 걸러 지운다.
class PushService {
  PushService._();
  static final instance = PushService._();

  final _messaging = FirebaseMessaging.instance;
  StreamSubscription? _refreshSub;

  /// 알림 탭으로 앱이 열렸을 때 흘려보낼 이벤트. RootScreen이 구독해서
  /// 해당 화면으로 보낸다
  final _taps = StreamController<PushTap>.broadcast();
  Stream<PushTap> get taps => _taps.stream;

  /// 앱이 완전히 꺼진 상태에서 알림을 눌러 실행된 경우, 구독자가 붙기 전에
  /// 이벤트가 지나가버리므로 여기에 담아뒀다가 나중에 꺼내 쓴다
  PushTap? _pendingTap;
  PushTap? takePendingTap() {
    final tap = _pendingTap;
    _pendingTap = null;
    return tap;
  }

  /// 로그인·프로필 설정이 끝난 뒤 호출. 권한을 아직 안 물었으면 여기서 묻는다.
  ///
  /// 앱 첫 실행에 바로 묻지 않는 이유: 왜 알림이 필요한지 모르는 상태에서
  /// 거절당하면 iOS는 다시 물을 수 없고, 설정에 들어가야만 되돌릴 수 있다
  Future<void> start(String uid) async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('푸시 권한 거부됨 — 요청은 앱을 열었을 때만 보이게 됨');
        return;
      }

      await _registerToken(uid);
      _refreshSub?.cancel();
      // 토큰은 재설치·복원 등으로 바뀔 수 있음. 바뀌면 즉시 다시 등록하지
      // 않으면 그 기기로는 알림이 영영 안 감
      _refreshSub = _messaging.onTokenRefresh.listen((token) {
        _saveToken(uid, token);
      });

      FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _pendingTap = _tapFrom(initial);
    } catch (e, stack) {
      // 푸시가 안 되더라도 앱 자체는 정상 동작해야 함 (앱을 켜면 요청이 보임)
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
    }
  }

  Future<void> _registerToken(String uid) async {
    // iOS는 APNs 토큰이 준비된 뒤에야 FCM 토큰이 나옴. 아직이면 조용히 넘어가고
    // onTokenRefresh가 나중에 채워준다
    final token = await _messaging.getToken();
    if (token != null) await _saveToken(uid, token);
  }

  Future<void> _saveToken(String uid, String token) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'fcmTokens': FieldValue.arrayUnion([token]),
      });
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
    }
  }

  /// 로그아웃·탈퇴 시 이 기기 토큰을 지움 — 안 지우면 다음 사용자에게
  /// 이전 사용자의 알림이 갈 수 있음
  Future<void> unregister(String uid) async {
    try {
      _refreshSub?.cancel();
      _refreshSub = null;
      final token = await _messaging.getToken();
      if (token == null) return;
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'fcmTokens': FieldValue.arrayRemove([token]),
      });
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
    }
  }

  void _handleTap(RemoteMessage message) => _taps.add(_tapFrom(message));

  PushTap _tapFrom(RemoteMessage m) => PushTap(
        type: m.data['type'] as String? ?? '',
        sessionId: m.data['sessionId'] as String?,
        fromUid: m.data['fromUid'] as String?,
      );
}

/// 사용자가 누른 알림
class PushTap {
  final String type; // friendRequest | friendAccepted | runRequest
  final String? sessionId;
  final String? fromUid;
  const PushTap({required this.type, this.sessionId, this.fromUid});
}
