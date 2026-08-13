import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/friend_service.dart';
import '../theme.dart';
import '../widgets/go_dialog.dart';
import '../widgets/initial_avatar.dart';
import '../widgets/go_toast.dart';
import 'lobby_screen.dart';
import 'login_screen.dart';

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

  Future<void> _editName() async {
    final controller = TextEditingController(text: _me?['name'] ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: GoColors.paper,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18)),
        title: Text('이름 변경', style: GoTheme.serif(20)),
        content: TextField(
          controller: controller,
          maxLength: 10,
          autofocus: true,
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: GoColors.line),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(color: GoColors.mid)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: GoColors.ink),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text('저장', style: GoTheme.serif(15, color: GoColors.lime)),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await _auth.updateName(name);
    _load();
  }

  /// 아이디(검색용 고유 핸들) 설정/변경 — 다른 사람이 "아이디로 찾기"에서
  /// 이 값으로 나를 찾아 친구 추가할 수 있음
  Future<void> _editUsername() async {
    final controller = TextEditingController(text: _me?['username'] ?? '');
    final input = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: GoColors.paper,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18)),
        title: Text('아이디 설정', style: GoTheme.serif(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              maxLength: 20,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'yourname123',
                counterText: '',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: GoColors.line),
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Text('영문 소문자·숫자·_ 로 3~20자',
                style: TextStyle(fontSize: 11, color: GoColors.dim)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(color: GoColors.mid)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: GoColors.ink),
            onPressed: () =>
                Navigator.pop(ctx, controller.text.trim().toLowerCase()),
            child: Text('저장', style: GoTheme.serif(15, color: GoColors.lime)),
          ),
        ],
      ),
    );
    if (input == null || input.isEmpty) return;
    if (!RegExp(r'^[a-z0-9_]{3,20}$').hasMatch(input)) {
      if (!mounted) return;
      GoToast.error(context, '영문 소문자·숫자·_ 로 3~20자로 입력해 주세요.');
      return;
    }
    try {
      final ok = await _auth.setUsername(input);
      if (!mounted) return;
      if (!ok) {
        GoToast.error(context, '이미 사용 중인 아이디예요.');
        return;
      }
      _load();
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (!mounted) return;
      GoToast.error(context, '저장에 실패했어요. 다시 시도해 주세요.');
    }
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
      _row(
        icon: Icons.person_outline,
        title: '프로필',
        subtitle: _me?['name'] ?? '',
        onTap: _editName,
      ),
      _row(
        icon: Icons.alternate_email,
        title: '아이디',
        subtitle: _me?['username'] ?? '설정 안 함 — 친구가 검색으로 찾을 수 있어요',
        onTap: _editUsername,
      ),
      _row(
        icon: Icons.notifications_outlined,
        title: '알림',
        subtitle: '준비 중이에요',
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
    required IconData icon,
    required String title,
    String? subtitle,
    Color? titleColor,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
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
            child: Icon(icon, size: 20, color: titleColor ?? GoColors.ink),
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
