import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:share_plus/share_plus.dart';

import '../../services/auth_service.dart';
import '../../theme.dart';
import '../../widgets/go_toast.dart';
import '../../widgets/pressable.dart';
import 'onboarding_scaffold.dart';

/// 온보딩 04 — 초대. **건너뛰어도 되는 장이다.**
///
/// 건너뛰기 문구가 사과가 아니라 사실인 게 중요하다: 혼자여도 첫 러닝부터
/// 함께다(첫 러닝 릴레이·고스트). 여기서 "친구가 없으면 재미없어요" 류의
/// 문장을 쓰면 그건 죄책감 카피고, 이 앱이 금지한 것이다.
///
/// **초대 '링크'는 아직 없다.** 유니버설 링크를 받으려면 도메인과 출시된
/// 앱이 있어야 하고 둘 다 없다. 카카오 공유도 v1.1이다. 그래서 지금 보내는
/// 것은 내 아이디가 담긴 한 문장이고, 받은 사람은 앱에서 그 아이디를 찾는다.
/// 링크가 생기면 이 화면에서 바뀌는 것은 [_shareText] 하나뿐이다.
class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  String? _name;
  String? _username;

  @override
  void initState() {
    super.initState();
    AuthService().myProfile().then((p) {
      if (!mounted || p == null) return;
      setState(() {
        _name = (p['name'] as String?)?.trim();
        _username = (p['username'] as String?)?.trim();
      });
    }).catchError((Object e, StackTrace s) {
      // 아이디를 못 읽어도 화면은 그대로 선다 — 건너뛰기가 늘 열려 있다
      FirebaseCrashlytics.instance.recordError(e, s, fatal: false);
    });
  }

  String get _shareText {
    final me = _name ?? '';
    final id = _username;
    final who = me.isEmpty ? '' : '$me님이 ';
    return id == null
        ? '$who고잉온에서 같이 달리자고 해요. 멀리 있어도 발은 맞출 수 있어요.'
        : '$who고잉온에서 같이 달리자고 해요.\n앱에서 아이디 @$id 를 찾아 주세요.';
  }

  Future<void> _share() async {
    try {
      await Share.share(_shareText);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (!mounted) return;
      GoToast.error(context, '공유 창을 열지 못했어요.');
    }
  }

  Future<void> _copyId() async {
    final id = _username;
    if (id == null) return;
    await Clipboard.setData(ClipboardData(text: '@$id'));
    if (!mounted) return;
    GoToast.show(context, '아이디를 복사했어요.');
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      content: [
        Text('같이 뛰고 싶은 사람,\n한 명쯤 있잖아요', style: GoTheme.serif(24)),
        const SizedBox(height: 8),
        const Text('멀리 있어도 돼요. 아이디 하나면 끝',
            style: TextStyle(fontSize: 13, color: GoColors.mid)),
        OnboardingScaffold.gap,
        OnboardingCard(
          height: 120,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('goingon', style: GoTheme.serif(15, color: GoColors.dim)),
            const SizedBox(height: 8),
            Text(_shareText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, height: 1.5, color: GoColors.ink)),
          ]),
        ),
        OnboardingScaffold.gap,
        Row(children: [
          Expanded(child: _smallAction('공유하기', _share)),
          const SizedBox(width: 10),
          Expanded(
              child: _smallAction(
                  '아이디 복사', _username == null ? null : _copyId)),
        ]),
        const Spacer(),
      ],
      action: OnboardingButton(label: '초대 보내기', onTap: _share),
      footer: Pressable(
        onTap: widget.onDone,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Text('건너뛰기 — 혼자여도 첫 러닝부터 함께예요',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: GoColors.dim)),
        ),
      ),
    );
  }

  Widget _smallAction(String label, VoidCallback? onTap) {
    return Pressable(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? .35 : 1,
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: GoColors.line),
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: GoColors.ink)),
        ),
      ),
    );
  }
}
