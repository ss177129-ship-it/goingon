import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/friend_service.dart';
import '../theme.dart';

/// 아이디로 친구 찾기 시트 — 홈/'우리' 탭 어디서든 같은 방식으로 열 수 있게 공용화
Future<void> showFriendSearchSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: GoColors.paper,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => const _FriendSearchSheet(),
  );
}

class _FriendSearchSheet extends StatefulWidget {
  const _FriendSearchSheet();

  @override
  State<_FriendSearchSheet> createState() => _FriendSearchSheetState();
}

class _FriendSearchSheetState extends State<_FriendSearchSheet> {
  final _controller = TextEditingController();
  bool _busy = false;

  Future<void> _search() async {
    final username = _controller.text;
    if (username.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final name = await FriendService()
          .addFriendByUsername(AuthService().uid, username);
      if (!mounted) return;
      if (name != null) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$name님과 연결됐어요! 이제 함께 달릴 수 있어요')),
        );
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
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          28, 28, 28, MediaQuery.of(context).viewInsets.bottom + 40),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('친구 찾기', style: GoTheme.serif(24)),
            const SizedBox(height: 6),
            const Text('상대방의 아이디를 입력하면 바로 연결돼요.',
                style: TextStyle(fontSize: 13, color: GoColors.mid)),
            const SizedBox(height: 20),
            TextField(
              controller: _controller,
              autofocus: true,
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
              onSubmitted: (_) => _search(),
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
                onPressed: _busy ? null : _search,
                child: Text('찾아서 연결하기',
                    style: GoTheme.serif(18, color: GoColors.ink)),
              ),
            ),
          ]),
    );
  }
}
