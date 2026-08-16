import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../services/avatar_service.dart';
import '../theme.dart';
import '../widgets/go_dialog.dart';
import '../widgets/go_toast.dart';
import '../widgets/initial_avatar.dart';

/// '설정 → 프로필 편집' — 프로토타입 s-setdetail의 '프로필' 항목.
///
/// 프로토타입에는 '한 줄 소개'도 있지만 넣지 않음. 지금 이 앱의 자유 입력
/// 텍스트는 이름·아이디뿐이라 심사 대응의 초점이 유해 텍스트가 아니라
/// '동의 없는 연락 차단'에 맞춰져 있는데(CLAUDE.md), 소개글은 그 전제를 깬다.
class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _auth = AuthService();
  final _avatars = AvatarService();

  Map<String, dynamic>? _me;
  bool _uploading = false;

  String get _name {
    final raw = _me?['name'];
    return (raw is String) ? raw.trim() : '';
  }

  String? get _photoUrl {
    final raw = _me?['photoUrl'];
    return (raw is String && raw.isNotEmpty) ? raw : null;
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
      if (!mounted) return;
      GoToast.error(context, '프로필을 불러오지 못했어요. 잠시 뒤 다시 시도해 주세요.');
    }
  }

  // ── 사진 ────────────────────────────────────────────────────────────

  /// 사진이 없으면 바로 사진첩을 열고, 있으면 '바꾸기 / 삭제'를 먼저 물음
  Future<void> _tapPhoto() async {
    if (_uploading) return;
    if (_photoUrl == null) {
      await _pickPhoto();
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: GoColors.paper,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          _sheetAction(ctx, Icons.photo_library_outlined, '사진첩에서 고르기',
              _pickPhoto),
          _sheetAction(ctx, Icons.delete_outline, '사진 지우기', _removePhoto,
              color: GoColors.coralDark),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  Widget _sheetAction(
      BuildContext sheetContext, IconData icon, String label, Future<void> Function() action,
      {Color? color}) {
    return InkWell(
      onTap: () {
        Navigator.pop(sheetContext);
        action();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        child: Row(children: [
          Icon(icon, size: 20, color: color ?? GoColors.ink),
          const SizedBox(width: 14),
          Text(label,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: color ?? GoColors.ink)),
        ]),
      ),
    );
  }

  Future<void> _pickPhoto() async {
    setState(() => _uploading = true);
    try {
      final url = await _avatars.pickAndUpload(_auth.uid);
      if (!mounted) return;
      setState(() {
        _uploading = false;
        if (url != null) _me = {...?_me, 'photoUrl': url};
      });
      // url == null은 사용자가 사진첩을 그냥 닫은 것 — 실패가 아니므로 조용히
      if (url != null) {
        HapticFeedback.lightImpact();
        GoToast.show(context, '프로필 사진을 바꿨어요.');
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (!mounted) return;
      setState(() => _uploading = false);
      GoToast.error(context, '사진을 올리지 못했어요. 다시 시도해 주세요.');
    }
  }

  Future<void> _removePhoto() async {
    final confirmed = await GoDialog.confirm(
      context,
      title: '사진을 지울까요?',
      body: '이름 첫 글자로 된 기본 아바타로 돌아가요.',
      confirmLabel: '지우기',
      destructive: true,
    );
    if (confirmed != true) return;
    setState(() => _uploading = true);
    try {
      await _avatars.remove(_auth.uid);
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _me = {...?_me}..remove('photoUrl');
      });
      GoToast.show(context, '프로필 사진을 지웠어요.');
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (!mounted) return;
      setState(() => _uploading = false);
      GoToast.error(context, '사진을 지우지 못했어요. 다시 시도해 주세요.');
    }
  }

  // ── 이름 / 아이디 ───────────────────────────────────────────────────

  Future<void> _editName() async {
    final name = await _askText(
      title: '이름 변경',
      initial: _name,
      maxLength: 10,
    );
    if (name == null || name.isEmpty) return;
    try {
      await _auth.updateName(name);
      if (!mounted) return;
      setState(() => _me = {...?_me, 'name': name});
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (!mounted) return;
      GoToast.error(context, '저장에 실패했어요. 다시 시도해 주세요.');
    }
  }

  /// 아이디(검색용 고유 핸들) 설정/변경 — 다른 사람이 "아이디로 찾기"에서
  /// 이 값으로 나를 찾아 친구 요청을 보낼 수 있음
  Future<void> _editUsername() async {
    final input = await _askText(
      title: '아이디 설정',
      initial: (_me?['username'] as String?) ?? '',
      maxLength: 20,
      hint: 'yourname123',
      helper: '영문 소문자·숫자·_ 로 3~20자',
    );
    if (input == null || input.isEmpty) return;
    final username = input.toLowerCase();
    if (!RegExp(r'^[a-z0-9_]{3,20}$').hasMatch(username)) {
      if (!mounted) return;
      GoToast.error(context, '영문 소문자·숫자·_ 로 3~20자로 입력해 주세요.');
      return;
    }
    try {
      final ok = await _auth.setUsername(username);
      if (!mounted) return;
      if (!ok) {
        GoToast.error(context, '이미 사용 중인 아이디예요.');
        return;
      }
      setState(() => _me = {...?_me, 'username': username});
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (!mounted) return;
      GoToast.error(context, '저장에 실패했어요. 다시 시도해 주세요.');
    }
  }

  Future<String?> _askText({
    required String title,
    required String initial,
    required int maxLength,
    String? hint,
    String? helper,
  }) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: GoColors.paper,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(title, style: GoTheme.serif(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              maxLength: maxLength,
              autofocus: true,
              decoration: InputDecoration(
                hintText: hint,
                counterText: '',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: GoColors.line),
                ),
              ),
            ),
            if (helper != null) ...[
              const SizedBox(height: 6),
              Text(helper,
                  style: const TextStyle(fontSize: 11, color: GoColors.dim)),
            ],
          ],
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
  }

  // ── 화면 ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final username = (_me?['username'] as String?) ?? '';
    return Scaffold(
      backgroundColor: GoColors.paper,
      body: SafeArea(
        bottom: false,
        child: ListView(padding: EdgeInsets.zero, children: [
          // 프로토타입 .af-head — 뒤로 12px/dim, 타이틀 28px 세리프
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text('← 설정으로',
                      style: TextStyle(fontSize: 12, color: GoColors.dim)),
                ),
              ),
              const SizedBox(height: 2),
              Text('프로필 편집', style: GoTheme.serif(28)),
            ]),
          ),
          const SizedBox(height: 22),
          _photoBlock(),
          const SizedBox(height: 22),
          _row('이름', _name.isEmpty ? '설정 안 함' : _name, _editName),
          _row('아이디', username.isEmpty ? '설정 안 함' : '@$username',
              _editUsername),
          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text('이름과 사진은 친구와 나에게 온 요청 목록에 보여요.',
                style: TextStyle(fontSize: 11, color: GoColors.dim, height: 1.6)),
          ),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  Widget _photoBlock() {
    return Center(
      child: Column(children: [
        GestureDetector(
          onTap: _tapPhoto,
          child: Stack(alignment: Alignment.center, children: [
            InitialAvatar(
              letter: _name.isEmpty ? '' : _name[0],
              size: 96,
              fontSize: 40,
              fill: GoColors.lime.withValues(alpha: .18),
              borderColor: GoColors.limeDark,
              emptyIcon: Icons.person_outline,
              photoUrl: _photoUrl,
            ),
            if (_uploading)
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: GoColors.ink.withValues(alpha: .45),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: _uploading ? null : _tapPhoto,
          child: Text(_photoUrl == null ? '사진첩에서 고르기' : '사진 바꾸기',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: GoColors.ink)),
        ),
      ]),
    );
  }

  /// 프로토타입 .sd-row — 좌우 24, 상하 15, 상단 라인
  Widget _row(String title, String value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: GoColors.line)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
        child: Row(children: [
          Expanded(
            child: Text(title,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: GoColors.ink)),
          ),
          Text(value,
              style: const TextStyle(fontSize: 13, color: GoColors.mid)),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right, size: 18, color: GoColors.dim),
        ]),
      ),
    );
  }
}
