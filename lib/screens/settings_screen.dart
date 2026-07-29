import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/go_dialog.dart';
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('영문 소문자·숫자·_ 로 3~20자로 입력해 주세요.')),
      );
      return;
    }
    try {
      final ok = await _auth.setUsername(input);
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이미 사용 중인 아이디예요.')),
        );
        return;
      }
      _load();
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('저장에 실패했어요. 다시 시도해 주세요.')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그아웃에 실패했어요. 다시 시도해 주세요.')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('탈퇴에 실패했어요. 다시 시도해 주세요.')),
      );
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
