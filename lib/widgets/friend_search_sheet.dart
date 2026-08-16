import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/friend_service.dart';
import '../theme.dart';
import 'initial_avatar.dart';
import 'go_toast.dart';

/// 아이디로 친구 찾기 시트 — 홈/'우리' 탭 어디서든 같은 방식으로 열 수 있게 공용화.
///
/// 찾기와 연결이 분리되어 있고, 연결은 **요청 → 상대 수락**으로만 이뤄짐.
/// 찾은 뒤 보이는 버튼은 지금 어떤 사이인지(FriendRelation)에 따라 달라짐
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
  late final _myUid = AuthService().uid;
  bool _busy = false;
  FriendCandidate? _found;
  String? _error;
  String? _notice;

  Future<void> _search() async {
    final input = _controller.text.trim();
    if (input.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
      _found = null;
    });
    try {
      final candidate = await _friends.lookupByUsername(input, _myUid);
      if (!mounted) return;
      setState(() {
        _found = candidate;
        // 나를 차단한 사람도 "없음"으로 나옴 — 있다는 사실 자체를 알리지 않음
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

  /// 관계 상태에 따라 눌렀을 때 할 일이 달라짐
  Future<void> _act() async {
    final c = _found;
    if (c == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      switch (c.relation) {
        case FriendRelation.none:
          await _friends.sendRequest(_myUid, c.uid);
          _finish('${c.name}님에게 요청을 보냈어요. 수락하면 함께 달릴 수 있어요');
        case FriendRelation.requestSent:
          await _friends.cancelRequest(_myUid, c.uid);
          _replace(c, FriendRelation.none, '요청을 취소했어요.');
        case FriendRelation.requestReceived:
          await _friends.acceptRequest(_myUid, c.uid);
          _finish('${c.name}님과 연결됐어요! 이제 함께 달릴 수 있어요');
        case FriendRelation.blockedByMe:
          await _friends.unblockUser(_myUid, c.uid);
          _replace(c, FriendRelation.none, '차단을 해제했어요.');
        case FriendRelation.friend:
        case FriendRelation.self:
          break; // 버튼이 비활성이라 여기 오지 않음
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (!mounted) return;
      setState(() => _error = '처리하지 못했어요. 잠시 후 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _finish(String message) {
    if (!mounted) return;
    Navigator.pop(context);
    GoToast.show(context, message);
  }

  /// 시트를 닫지 않고 상태만 갱신 (취소·차단 해제처럼 이어서 뭔가 할 수 있는 경우)
  void _replace(FriendCandidate c, FriendRelation relation, String notice) {
    if (!mounted) return;
    setState(() {
      _found = FriendCandidate(
          uid: c.uid, name: c.name, username: c.username, relation: relation);
      _notice = notice;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _found;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          28, 28, 28, MediaQuery.of(context).viewInsets.bottom + 40),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('친구 찾기', style: GoTheme.serif(24)),
            const SizedBox(height: 6),
            const Text('아이디로 찾아 요청을 보내면, 상대가 수락했을 때 연결돼요.',
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
                if (_found != null || _error != null || _notice != null) {
                  setState(() {
                    _found = null;
                    _error = null;
                    _notice = null;
                  });
                }
              },
              onSubmitted: (_) => _search(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style:
                      const TextStyle(fontSize: 12, color: GoColors.coralDark)),
            ],
            if (_notice != null) ...[
              const SizedBox(height: 10),
              Text(_notice!,
                  style:
                      const TextStyle(fontSize: 12, color: GoColors.limeDark)),
            ],
            if (c != null) ...[
              const SizedBox(height: 14),
              _foundCard(c),
            ],
            const SizedBox(height: 14),
            SizedBox(width: double.infinity, child: _actionButton(c)),
          ]),
    );
  }

  Widget _actionButton(FriendCandidate? c) {
    final label = c == null ? '찾기' : _actionLabel(c.relation);
    final enabled = !_busy && (c == null || label != null);
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: GoColors.lime,
        disabledBackgroundColor: GoColors.lime.withOpacity(.35),
        padding: const EdgeInsets.symmetric(vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      onPressed: enabled ? (c == null ? _search : _act) : null,
      child: _busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child:
                  CircularProgressIndicator(strokeWidth: 2, color: GoColors.ink))
          : Text(label ?? _stateLabel(c!.relation),
              style: GoTheme.serif(18, color: GoColors.ink)),
    );
  }

  /// 누를 수 있는 상태면 버튼 문구, 아니면 null(비활성)
  String? _actionLabel(FriendRelation r) => switch (r) {
        FriendRelation.none => '함께 달리자고 요청하기',
        FriendRelation.requestSent => '요청 취소하기',
        FriendRelation.requestReceived => '수락하고 연결하기',
        FriendRelation.blockedByMe => '차단 해제하기',
        FriendRelation.friend => null,
        FriendRelation.self => null,
      };

  String _stateLabel(FriendRelation r) => switch (r) {
        FriendRelation.friend => '이미 함께 달리는 사이예요',
        FriendRelation.self => '내 아이디예요',
        _ => '',
      };

  /// 연결 전 확인 카드 — 오타 하나로 모르는 사람에게 요청이 가지 않도록
  Widget _foundCard(FriendCandidate c) {
    final status = _relationNote(c.relation);
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
          photoUrl: c.photoUrl,
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
                if (status != null) ...[
                  const SizedBox(height: 4),
                  Text(status,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: GoColors.mid)),
                ],
              ]),
        ),
      ]),
    );
  }

  String? _relationNote(FriendRelation r) => switch (r) {
        FriendRelation.requestSent => '요청을 보내고 기다리는 중',
        FriendRelation.requestReceived => '나에게 요청을 보냈어요',
        FriendRelation.friend => '이미 연결됨',
        FriendRelation.blockedByMe => '차단한 상대',
        _ => null,
      };
}
