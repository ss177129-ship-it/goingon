import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/auth_service.dart';
import '../services/friend_service.dart';
import '../theme.dart';

/// 초대 + 코드 입력 — 성장 루프의 심장
class InviteScreen extends StatefulWidget {
  final String myCode;
  final String myName;
  const InviteScreen({super.key, required this.myCode, required this.myName});

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  final _codeController = TextEditingController();
  final _usernameController = TextEditingController();
  bool _busy = false;

  Future<void> _share() async {
    // TODO 출시 전: 앱스토어 등록 후 실제 링크로 교체
    try {
      await Share.share(
        '${widget.myName}님이 함께 달리고 싶어 해요 🏃\n'
        '멀리 있어도 같이 달릴 수 있어요.\n\n'
        '1. GoingOn 설치: https://apps.apple.com/app/goingon\n'
        '2. 초대 코드 입력: ${widget.myCode}',
      );
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('공유하지 못했어요. 다시 시도해 주세요.')),
      );
    }
  }

  Future<void> _enterCode() async {
    final code = _codeController.text;
    if (code.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final name =
          await FriendService().addFriendByCode(AuthService().uid, code);
      if (!mounted) return;
      if (name != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$name님과 연결됐어요! 이제 함께 달릴 수 있어요')),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('코드를 찾을 수 없어요. 다시 확인해 주세요.')),
        );
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('연결에 실패했어요. 인터넷을 확인해 주세요.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _searchUsername() async {
    final username = _usernameController.text;
    if (username.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final name = await FriendService()
          .addFriendByUsername(AuthService().uid, username);
      if (!mounted) return;
      if (name != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$name님과 연결됐어요! 이제 함께 달릴 수 있어요')),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('아이디를 찾을 수 없어요. 다시 확인해 주세요.')),
        );
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('연결에 실패했어요. 인터넷을 확인해 주세요.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: GoColors.paper,
        title: Text('함께 달릴 사람', style: GoTheme.serif(22)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(28),
          children: [
            const Text('멀리 있어도 같이 달릴 수 있어요. 링크 한 번이면 돼요.',
                style: TextStyle(fontSize: 13, color: GoColors.mid)),
            const SizedBox(height: 24),
            // 내 코드 카드
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: GoColors.line),
              ),
              child: Column(children: [
                const Text('내 초대 코드',
                    style: TextStyle(fontSize: 11, color: GoColors.dim)),
                const SizedBox(height: 8),
                Text(widget.myCode,
                    style: GoTheme.serif(36, color: GoColors.limeDark)),
              ]),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: GoColors.ink,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _share,
                icon: const Icon(Icons.ios_share, size: 18),
                label: const Text('초대 링크 보내기',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 36),
            Row(children: [
              Expanded(child: Divider(color: GoColors.line)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text('또는 받은 코드 입력',
                    style: TextStyle(fontSize: 11, color: GoColors.dim)),
              ),
              Expanded(child: Divider(color: GoColors.line)),
            ]),
            const SizedBox(height: 20),
            TextField(
              controller: _codeController,
              textAlign: TextAlign.center,
              textCapitalization: TextCapitalization.characters,
              style: GoTheme.serif(24),
              decoration: InputDecoration(
                hintText: 'GO-XXXXX',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: GoColors.line),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: GoColors.lime,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _busy ? null : _enterCode,
                child: Text('연결하기', style: GoTheme.serif(18, color: GoColors.ink)),
              ),
            ),
            const SizedBox(height: 36),
            Row(children: [
              Expanded(child: Divider(color: GoColors.line)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text('또는 아이디로 찾기',
                    style: TextStyle(fontSize: 11, color: GoColors.dim)),
              ),
              Expanded(child: Divider(color: GoColors.line)),
            ]),
            const SizedBox(height: 20),
            TextField(
              controller: _usernameController,
              textAlign: TextAlign.center,
              style: GoTheme.serif(24),
              decoration: InputDecoration(
                hintText: '상대방 아이디',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: GoColors.line),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: GoColors.line, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _busy ? null : _searchUsername,
                child: Text('찾아서 연결하기',
                    style: GoTheme.serif(18, color: GoColors.ink)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
