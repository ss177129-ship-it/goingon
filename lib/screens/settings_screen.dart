import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/friend_service.dart';
import '../services/push_service.dart';
import '../theme.dart';
import '../widgets/go_dialog.dart';
import '../widgets/initial_avatar.dart';
import '../widgets/go_toast.dart';
import 'lobby_screen.dart';
import 'login_screen.dart';
import 'profile_edit_screen.dart';

const _kAppVersion = '0.1.0';

/// '설정' 탭 — 프로토타입 s-settings. MVP 범위: 프로필(이름 변경),
/// 아이디(검색용 핸들), 알림(준비 중 — FCM 미구현), 로그아웃, 회원탈퇴, 버전.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _auth = AuthService();
  Map<String, dynamic>? _me;
  bool _busy = false;

  bool get _pushRegistered => (_me?['fcmTokens'] as List?)?.isNotEmpty ?? false;

  String get _myName {
    final raw = _me?['name'];
    return (raw is String) ? raw.trim() : '';
  }

  String? get _myPhotoUrl {
    final raw = _me?['photoUrl'];
    return (raw is String && raw.isNotEmpty) ? raw : null;
  }

  String get _profileSummary {
    final username = (_me?['username'] as String?) ?? '';
    if (username.isEmpty) return '아이디를 설정하면 친구가 검색으로 찾을 수 있어요';
    return _myName.isEmpty ? '@$username' : '$_myName · @$username';
  }

  String get _pushStatus {
    if (_pushRegistered) return '이 기기로 알림을 받아요';
    final err = PushService.instance.lastRegistrationError;
    if (err != null) return '등록 실패 — 눌러서 다시 시도 ($err)';
    return '아직 등록되지 않았어요 — 눌러서 다시 시도';
  }

  /// 등록이 실패했을 때 사용자가 직접 다시 시도. iOS 알림 권한 자체를
  /// 거부했다면 앱에서는 되돌릴 수 없어 시스템 설정으로 안내함
  Future<void> _retryPush() async {
    if (_pushRegistered) {
      if (mounted) GoToast.show(context, '이미 알림을 받고 있어요.');
      return;
    }
    setState(() => _busy = true);
    await PushService.instance.retry(_auth.uid);
    await _load();
    if (!mounted) return;
    setState(() => _busy = false);
    if (_pushRegistered) {
      GoToast.show(context, '알림 등록이 끝났어요.');
    } else {
      GoToast.error(context,
          '아직 안 됐어요. iOS 설정 → 알림 → Goingon에서 알림이 켜져 있는지 확인해 주세요.');
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await _auth.myProfile();
      if (!mounted) return;
      setState(() => _me = profile);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (mounted) {
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) _load();
        });
      }
    }
  }

  /// 이름·아이디·사진은 '프로필 편집'(ProfileEditScreen)에서 한꺼번에 다룸.
  /// 돌아오면 여기 요약(이름·아이디 줄)도 갱신해야 하므로 다시 읽음
  Future<void> _openProfileEdit() async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => const ProfileEditScreen()));
    if (mounted) _load();
  }

  /// 차단 목록 — 차단은 되돌릴 수 있어야 하므로 해제 경로를 반드시 둠
  void _showBlockedList() {
    final friends = FriendService();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: GoColors.paper,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .5,
        maxChildSize: .9,
        builder: (_, scrollController) =>
            StreamBuilder<List<Map<String, dynamic>>>(
          stream: friends.blockedStream(_auth.uid),
          builder: (context, snap) {
            final blocked = snap.data ?? const [];
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
              children: [
                Text('차단 목록', style: GoTheme.serif(24)),
                const SizedBox(height: 6),
                const Text('차단한 사람은 나를 검색하거나 요청을 보낼 수 없어요.',
                    style: TextStyle(fontSize: 13, color: GoColors.mid)),
                const SizedBox(height: 20),
                if (snap.connectionState == ConnectionState.waiting)
                  const Center(child: CircularProgressIndicator())
                else if (blocked.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: Text('차단한 사람이 없어요',
                          style: GoTheme.serif(17, color: GoColors.mid)),
                    ),
                  )
                else
                  ...blocked.map((b) => _blockedRow(b, friends)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _blockedRow(Map<String, dynamic> b, FriendService friends) {
    final rawName = b['name'];
    final name = (rawName is String && rawName.trim().isNotEmpty)
        ? rawName.trim()
        : '이름 없음';
    final username = b['username'] as String?;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GoColors.line),
      ),
      child: Row(children: [
        InitialAvatar(
          letter: name[0],
          size: 40,
          fontSize: 16,
          borderColor: GoColors.line,
          borderWidth: 1.5,
          photoUrl: b['photoUrl'] as String?,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: GoColors.ink)),
                if (username != null && username.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text('@$username',
                      style:
                          const TextStyle(fontSize: 11, color: GoColors.dim)),
                ],
              ]),
        ),
        TextButton(
          onPressed: () => _unblock(b['uid'] as String, name, friends),
          child: const Text('차단 해제',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: GoColors.ink)),
        ),
      ]),
    );
  }

  Future<void> _unblock(
      String uid, String name, FriendService friends) async {
    try {
      await friends.unblockUser(_auth.uid, uid);
      if (!mounted) return;
      GoToast.show(context, '$name님의 차단을 해제했어요. 다시 친구가 되려면 요청이 필요해요.');
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (!mounted) return;
      GoToast.error(context, '차단을 해제하지 못했어요. 다시 시도해 주세요.');
    }
  }

  /// 모든 계정이 Apple 로그인에 묶여 있으므로 로그아웃해도 항상 복구 가능
  Future<void> _logout() async {
    final confirmed = await GoDialog.confirm(
      context,
      title: '로그아웃할까요?',
      body: 'Apple 계정으로 연결되어 있어서, 다시 로그인하면 지금 기록 그대로 돌아와요.',
      confirmLabel: '로그아웃',
    );
    if (confirmed != true) return;
    try {
      await _auth.signOut();
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (!mounted) return;
      GoToast.error(context, '로그아웃에 실패했어요. 다시 시도해 주세요.');
      return;
    }
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context,
        MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  Future<void> _deleteAccount() async {
    final confirmed = await GoDialog.confirm(
      context,
      title: '정말 탈퇴할까요?',
      body: '내 기록과 친구 연결이 모두 사라져요.\n이 작업은 되돌릴 수 없어요.',
      confirmLabel: '탈퇴하기',
      destructive: true,
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await _auth.deleteAccount();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(context,
          MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (!mounted) return;
      setState(() => _busy = false);
      GoToast.error(context, '탈퇴에 실패했어요. 다시 시도해 주세요.');
    }
  }


  @override
  Widget build(BuildContext context) {
    return ListView(padding: EdgeInsets.zero, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 6),
        child: Text('설정', style: GoTheme.serif(28)),
      ),
      // 프로토타입 s-settings의 '프로필 편집' 한 줄. 사진·이름·아이디를
      // 한 화면에서 다루므로 여기서는 지금 상태만 요약해 보여줌
      _row(
        leading: InitialAvatar(
          letter: _myName.isEmpty ? '' : _myName[0],
          size: 24,
          fontSize: 11,
          borderColor: GoColors.limeDark,
          borderWidth: 1.2,
          emptyIcon: Icons.person_outline,
          photoUrl: _myPhotoUrl,
        ),
        title: '프로필 편집',
        subtitle: _profileSummary,
        onTap: _openProfileEdit,
      ),
      // 푸시가 안 될 때 폰에서 바로 원인이 보이게 함. 실기기 검증이
      // TestFlight밖에 없어서(한 사이클 20~40분) 로그를 볼 수 없기 때문에,
      // 진단을 화면에 띄우는 게 유일하게 빠른 길임
      _row(
        icon: _pushRegistered
            ? Icons.notifications_active_outlined
            : Icons.notifications_off_outlined,
        title: '알림',
        subtitle: _pushStatus,
        titleColor: _pushRegistered ? null : GoColors.amber,
        onTap: _retryPush,
      ),
      _row(
        icon: Icons.block,
        title: '차단 목록',
        subtitle: '차단한 사람을 확인하고 해제해요',
        onTap: _showBlockedList,
      ),
      // 친구가 없어도 로비 → 러닝 → 완료 전체를 볼 수 있는 통로.
      // 홈의 링크는 친구가 생기면 사라지므로, 항상 찾을 수 있는 자리에도 둠
      _row(
        icon: Icons.play_circle_outline,
        title: '혼자 미리 체험하기',
        subtitle: '가상의 친구와 전체 흐름을 둘러봐요',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const LobbyScreen(
                sessionId: 'demo', partnerName: '지수', demo: true),
          ),
        ),
      ),
      _row(
        icon: Icons.logout,
        title: '로그아웃',
        onTap: _busy ? null : _logout,
      ),
      _row(
        icon: Icons.person_remove_outlined,
        title: '회원탈퇴',
        titleColor: GoColors.coralDark,
        onTap: _busy ? null : _deleteAccount,
      ),
      _row(
        icon: Icons.info_outline,
        title: '버전',
        trailing: const Text(_kAppVersion,
            style: TextStyle(fontSize: 13, color: GoColors.mid)),
      ),
      const SizedBox(height: 12),
    ]);
  }

  Widget _row({
    IconData? icon,
    Widget? leading,
    required String title,
    String? subtitle,
    Color? titleColor,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    assert(icon != null || leading != null);
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: GoColors.line)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
        child: Row(children: [
          SizedBox(
            width: 24,
            child: leading ??
                Icon(icon, size: 20, color: titleColor ?? GoColors.ink),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                      color: titleColor ?? GoColors.ink)),
              if (subtitle != null && subtitle.isNotEmpty) ...[
                const SizedBox(height: 1),
                Text(subtitle,
                    style: const TextStyle(fontSize: 11, color: GoColors.mid)),
              ],
            ]),
          ),
          trailing ??
              (onTap != null
                  ? const Icon(Icons.chevron_right, size: 20, color: GoColors.dim)
                  : const SizedBox.shrink()),
        ]),
      ),
    );
  }
}
