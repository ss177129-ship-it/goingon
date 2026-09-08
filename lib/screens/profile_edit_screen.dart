import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../services/avatar_service.dart';
import '../theme.dart';
import '../widgets/go_group.dart';
import '../widgets/go_button.dart';
import '../widgets/go_dialog.dart';
import '../widgets/go_toast.dart';
import '../widgets/go_avatar.dart';
import '../widgets/pressable.dart';

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
    final roles = GoRoles.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: roles.surfaceHigh,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: GoSpace.m),
          _sheetAction(
              ctx, Icons.photo_library_outlined, '사진첩에서 고르기', _pickPhoto),
          _sheetAction(ctx, Icons.delete_outline, '사진 지우기', _removePhoto,
              color: roles.attention),
          const SizedBox(height: GoSpace.m),
        ]),
      ),
    );
  }

  Widget _sheetAction(BuildContext sheetContext, IconData icon, String label,
      Future<void> Function() action,
      {Color? color}) {
    // 시트의 행 — 목록 행과 같은 눌림(축소 없이 면이 가라앉는다)
    final roles = GoRoles.of(sheetContext);
    return Pressable(
      scale: 1,
      onTap: () {
        Navigator.pop(sheetContext);
        action();
      },
      builder: (context, pressed, child) => AnimatedContainer(
        duration: pressed ? Duration.zero : Pressable.releaseDuration,
        curve: GoMotion.curve,
        color: pressed ? roles.surfacePressed : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        child: child,
      ),
      child: Row(children: [
        Icon(icon, size: 20, color: color ?? roles.textPrimary),
        const SizedBox(width: 14),
        Text(label,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color ?? roles.textPrimary)),
      ]),
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
      body: '기본 프로필로 돌아가요.',
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
    final roles = GoRoles.of(context);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: roles.surfaceHigh,
        elevation: 12,
        // Material이 elevation에 맞춰 알파를 씌우므로 그림자 색은 불투명하게
        shadowColor: GoShadow.overlay.last.color.withValues(alpha: 1),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GoRadius.lg)),
        title: Text(title, style: GoText.heading),
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
                fillColor: roles.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      BorderSide(color: roles.line, width: GoStroke.card),
                ),
              ),
            ),
            if (helper != null) ...[
              const SizedBox(height: 6),
              Text(helper,
                  style: TextStyle(fontSize: 12, color: roles.textSecondary)),
            ],
          ],
        ),
        actions: [
          GoButton('취소',
              kind: GoButtonKind.text,
              size: GoButtonSize.md,
              onTap: () => Navigator.pop(ctx)),
          GoButton('저장',
              kind: GoButtonKind.complete,
              size: GoButtonSize.md,
              onTap: () => Navigator.pop(ctx, controller.text.trim())),
        ],
      ),
    );
  }

  // ── 화면 ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final username = (_me?['username'] as String?) ?? '';
    final roles = GoRoles.of(context);
    return Scaffold(
      backgroundColor: roles.background,
      body: SafeArea(
        bottom: false,
        child: ListView(padding: EdgeInsets.zero, children: [
          // 프로토타입 .af-head — 타이틀 28px 세리프.
          // 뒤로가기는 12px 글자뿐이라 표적이 24pt밖에 안 됐다. 로비와 같은
          // 44pt 버튼으로 교체(2026-09-08). 왼쪽 12는 버튼 자체 좌우
          // 여백(16)을 빼고 제목(24)에 맞춘 값
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 24, 0),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                GoButton('설정으로',
                    kind: GoButtonKind.text,
                    size: GoButtonSize.md,
                    icon: Icons.arrow_back,
                    onTap: () => Navigator.pop(context)),
                const Spacer(),
              ]),
              const SizedBox(height: 2),
              const Padding(
                padding: EdgeInsets.only(left: 12),
                child: Text('프로필 편집', style: GoText.title),
              ),
            ]),
          ),
          const SizedBox(height: 22),
          _photoBlock(),
          const SizedBox(height: 22),
          GoGroup(rows: [
            _row('이름', _name.isEmpty ? '설정 안 함' : _name, _editName),
            _row('아이디', username.isEmpty ? '설정 안 함' : '@$username',
                _editUsername),
          ]),
          const SizedBox(height: GoSpace.section),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text('이름과 사진은 페이스메이트와 나에게 온 요청 목록에 보여요.',
                style: TextStyle(
                    fontSize: 12, color: roles.textSecondary, height: 1.6)),
          ),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  Widget _photoBlock() {
    final roles = GoRoles.of(context);
    return Center(
      child: Column(children: [
        // 사진은 버튼처럼 눌린다 — 0.97 축소 + 햅틱
        Pressable(
          onTap: _tapPhoto,
          child: Stack(alignment: Alignment.center, children: [
            GoAvatar(
              size: 96,
              roleColor: roles.self,
              photoUrl: _photoUrl,
            ),
            if (_uploading)
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: roles.dark.bg.withValues(alpha: .45),
                ),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: roles.textOnDark),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 10),
        GoButton(_photoUrl == null ? '사진첩에서 고르기' : '사진 바꾸기',
            kind: GoButtonKind.text,
            size: GoButtonSize.md,
            enabled: !_uploading,
            onTap: _tapPhoto),
      ]),
    );
  }

  /// 그룹 안의 행 하나
  GoGroupRow _row(String title, String value, VoidCallback onTap) {
    final roles = GoRoles.of(context);
    return GoGroupRow(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
          horizontal: GoSpace.card, vertical: GoSpace.l),
      child: Row(children: [
        Expanded(
          child: Text(title,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: roles.textPrimary)),
        ),
        Text(value, style: TextStyle(fontSize: 13, color: roles.textSecondary)),
        const SizedBox(width: 6),
        Icon(Icons.chevron_right, size: 18, color: roles.textSecondary),
      ]),
    );
  }
}
