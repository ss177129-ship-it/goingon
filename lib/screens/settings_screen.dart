import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/auth_service.dart';
import '../theme.dart';
import 'login_screen.dart';

const _kNotifPrefKey = 'notifications_enabled';
const _kAppVersion = '0.1.0';

/// '설정' 탭 — 프로토타입 s-settings. MVP 범위: 프로필(이름 변경),
/// 초대 코드, 알림 토글(로컬 저장), 로그아웃, 회원탈퇴, 버전.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _auth = AuthService();
  Map<String, dynamic>? _me;
  bool _notifOn = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await _auth.myProfile();
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _me = profile;
      _notifOn = prefs.getBool(_kNotifPrefKey) ?? true;
    });
  }

  Future<void> _toggleNotif(bool v) async {
    setState(() => _notifOn = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kNotifPrefKey, v);
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

  void _copyInviteCode() {
    final code = _me?['inviteCode'] ?? '';
    if (code.isEmpty) return;
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('초대 코드를 복사했어요'), duration: Duration(seconds: 2)),
    );
  }

  Future<void> _deleteAccount() async {
    final confirmed = await _confirm(
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('탈퇴에 실패했어요. 다시 시도해 주세요.')),
      );
    }
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String confirmLabel,
    bool destructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: GoColors.paper,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18)),
        title: Text(title, style: GoTheme.serif(20)),
        content: Text(body,
            style: const TextStyle(fontSize: 13, color: GoColors.mid, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소', style: TextStyle(color: GoColors.mid)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor:
                    destructive ? GoColors.coralDark : GoColors.ink),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel,
                style: GoTheme.serif(15, color: GoColors.paper)),
          ),
        ],
      ),
    );
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
        icon: Icons.mail_outline,
        title: '내 초대 코드',
        subtitle: _me?['inviteCode'] ?? '',
        trailing: const Icon(Icons.copy_outlined, size: 18, color: GoColors.dim),
        onTap: _copyInviteCode,
      ),
      _row(
        icon: Icons.notifications_outlined,
        title: '알림',
        subtitle: '약속·합류 알림',
        trailing: Switch(
          value: _notifOn,
          activeThumbColor: GoColors.limeDark,
          onChanged: _toggleNotif,
        ),
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
