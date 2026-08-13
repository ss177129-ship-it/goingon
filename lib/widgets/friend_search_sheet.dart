import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/friend_service.dart';
import '../theme.dart';
import 'initial_avatar.dart';

/// 아이디로 친구 찾기 시트 — 홈/'우리' 탭 어디서든 같은 방식으로 열 수 있게 공용화.
///
/// 찾기와 연결이 두 단계로 나뉘어 있음: 먼저 상대가 누구인지 보여주고,
/// "맞아요, 연결할래요"를 누른 뒤에야 실제로 연결됨
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
  final _friends = FriendService();
  bool _busy = false;
  FriendCandidate? _found;
  String? _error;

  Future<void> _search() async {
    final input = _controller.text.trim();
    if (input.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _found = null;
    });
    try {
      final candidate = await _friends.lookupByUsername(input);
      if (!mounted) return;
      setState(() {
        _found = candidate;
        _error = candidate == null ? '그런 아이디를 쓰는 사람이 없어요.' : null;
      });
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (!mounted) return;
      setState(() => _error = '찾지 못했어요. 인터넷을 확인해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() async {
    final candidate = _found;
    if (candidate == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _friends.connect(AuthService().uid, candidate.uid);
      if (!mounted) return;
      switch (result) {
        case FriendAddResult.connected:
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('${candidate.name}님과 연결됐어요! 이제 함께 달릴 수 있어요')));
        case FriendAddResult.alreadyFriend:
          setState(() => _error = '이미 함께 달리는 사이예요.');
        case FriendAddResult.myself:
          setState(() => _error = '내 아이디예요. 상대방의 아이디를 입력해 주세요.');
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (!mounted) return;
      setState(() => _error = '연결에 실패했어요. 인터넷을 확인해 주세요.');
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
            const Text('상대방의 아이디를 입력하면 누구인지 먼저 보여드려요.',
                style: TextStyle(fontSize: 13, color: GoColors.mid)),
            const SizedBox(height: 20),
            TextField(
              controller: _controller,
              autofocus: true,
              textAlign: TextAlign.center,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.none,
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
              onChanged: (_) {
                if (_found != null || _error != null) {
                  setState(() {
                    _found = null;
                    _error = null;
                  });
                }
              },
              onSubmitted: (_) => _search(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style: const TextStyle(
                      fontSize: 12, color: GoColors.coralDark)),
            ],
            if (_found != null) ...[
              const SizedBox(height: 14),
              _foundCard(_found!),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: GoColors.lime,
                  disabledBackgroundColor: GoColors.lime.withOpacity(.4),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _busy ? null : (_found == null ? _search : _connect),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: GoColors.ink))
                    : Text(_found == null ? '찾기' : '맞아요, 연결할래요',
                        style: GoTheme.serif(18, color: GoColors.ink)),
              ),
            ),
          ]),
    );
  }

  /// 연결 전 확인 카드 — 오타 하나로 모르는 사람과 이어지지 않도록
  Widget _foundCard(FriendCandidate c) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: GoColors.line, width: 1.5),
      ),
      child: Row(children: [
        InitialAvatar(
          letter: c.name.isEmpty ? '' : c.name[0],
          size: 44,
          fontSize: 18,
          borderColor: GoColors.line,
          borderWidth: 1.5,
          emptyIcon: Icons.person_outline,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.name,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: GoColors.ink)),
                const SizedBox(height: 2),
                Text('@${c.username}',
                    style: const TextStyle(fontSize: 12, color: GoColors.dim)),
              ]),
        ),
      ]),
    );
  }
}
