import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/friend_service.dart';
import '../services/hidden_invites.dart';
import '../services/invite.dart';
import '../services/invite_service.dart';
import '../services/run_service.dart';
import '../theme.dart';
import '../widgets/go_avatar.dart';
import '../widgets/go_button.dart';
import '../widgets/go_card.dart';
import '../widgets/go_dialog.dart';
import '../widgets/go_toast.dart';
import 'lobby_screen.dart';

/// '제안' 탭 — 지금 오가는 것.
///
/// **왜 탭인가**(2026-09-09). 받은 제안은 시트로만 떴고, 그 시트는 앱이
/// 포그라운드에 있고 홈이 열려 있고 다른 시트가 없을 때만 나타났다. 한 번
/// 닫으면 아무 흔적도 남지 않아서, 상대는 답을 영영 못 받은 채 기다렸다.
/// 제안이 **머무는 자리**가 있어야 그 구멍이 막힌다.
///
/// 홈은 사람, 여기는 지금 오가는 것, '우리'는 쌓인 것 — 세 탭이 시간축을
/// 나눠 갖는다.
class InvitesScreen extends StatefulWidget {
  const InvitesScreen({super.key});

  @override
  State<InvitesScreen> createState() => _InvitesScreenState();
}

class _InvitesScreenState extends State<InvitesScreen> {
  final _auth = AuthService();
  final _invites = InviteService();
  final _runs = RunService();
  final _friends = FriendService();

  StreamSubscription? _sub;
  StreamSubscription? _friendsSub;
  List<Invite>? _list;

  /// 스트림이 끊겼다 — 목록은 그대로 두고 안내만 얹는다
  bool _broken = false;
  Map<String, Map<String, dynamic>> _profiles = const {};

  /// 1분마다 다시 그린다 — 남은 시간이 줄어야 하고, 30분이 지나면 문서가
  /// 아직 invited여도 만료로 넘어가야 한다(서버 정리는 15분마다 돈다)
  Timer? _tick;

  final _hidden = HiddenInvites.instance;

  @override
  void initState() {
    super.initState();
    _hidden.addListener(_onHiddenChanged);
    _listen();
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _listen() {
    _sub?.cancel();
    _sub = _invites.stream(_auth.uid).listen((l) {
      if (mounted) {
        setState(() {
          _list = l;
          _broken = false;
        });
      }
    }, onError: (e, stack) {
      // **마지막으로 성공한 목록을 버리지 않는다.** 여기서 빈 목록으로
      // 지웠더니, 홈 카드에는 제안이 떠 있는데 이 탭은 "오가는 제안이
      // 없어요"였다 — 같은 스트림을 보면서 화면끼리 다른 말을 했다.
      // 못 불러온 것과 없는 것은 다르다
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (mounted) setState(() => _broken = true);
    });
    // 이름·사진은 페이스메이트 목록에서 온다. 세션에는 uid만 있고, 제안을
    // 주고받을 수 있는 사람은 규칙상 언제나 페이스메이트다
    _friendsSub?.cancel();
    _friendsSub = _friends.friendsStream(_auth.uid).listen((list) {
      if (!mounted) return;
      setState(() => _profiles = {
            for (final f in list) f['uid'] as String: f,
          });
    }, onError: (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
    });
  }

  void _onHiddenChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _hidden.removeListener(_onHiddenChanged);
    _sub?.cancel();
    _friendsSub?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  String _nameOf(String uid) {
    final n = _profiles[uid]?['name'];
    final s = n is String ? n.trim() : '';
    return s.isEmpty ? '페이스메이트' : s;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final all = _list;
    final open = all?.where((i) => i.isOpen(now)).toList() ?? const [];
    // 내가 치운 것은 목록에서 뺀다. 문서는 그대로 있고 상대 화면에도 남는다
    final done = all
            ?.where((i) => i.isOutcome(now) && !_hidden.contains(i.sessionId))
            .toList() ??
        const [];

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(22, 18, 22, 10),
          child: Text('제안', style: GoText.title),
        ),
        if (_broken) _notice(),
        if (all == null)
          const SizedBox(height: 40)
        else if (open.isEmpty && done.isEmpty)
          _empty()
        else ...[
          if (open.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 6, 22, 10),
              child: Text('오가는 중', style: GoText.label),
            ),
            ...open.map((i) => _row(i, now)),
          ],
          if (done.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(22, GoSpace.section, 12, 4),
              child: Row(children: [
                const Text('지난 제안', style: GoText.label),
                const Spacer(),
                GoButton('모두 지우기',
                    kind: GoButtonKind.text,
                    size: GoButtonSize.md,
                    onTap: () => _clearAll(done)),
              ]),
            ),
            ...done.map((i) => _dismissibleRow(i, now)),
          ],
        ],
        const SizedBox(height: GoSpace.xl),
      ],
    );
  }

  /// 조용히 실패하지 않는다 — 여기 걸리면 대개 인덱스 미배포다
  Widget _notice() {
    final roles = GoRoles.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(22, 0, 22, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: roles.surface,
        borderRadius: BorderRadius.circular(GoRadius.md),
        boxShadow: GoShadow.card,
      ),
      child: Row(children: [
        Icon(Icons.wifi_off, size: 18, color: roles.warning.fg),
        const SizedBox(width: GoSpace.m),
        Expanded(
          child: Text('제안을 불러오지 못했어요.',
              style: TextStyle(fontSize: 12, color: roles.textPrimary)),
        ),
        GoButton('다시 시도',
            kind: GoButtonKind.text,
            size: GoButtonSize.md,
            onTap: () {
              setState(() => _broken = false);
              _listen();
            }),
      ]),
    );
  }

  /// 지난 제안 한 줄 — 옆으로 밀면 내 목록에서 사라진다.
  ///
  /// **오가는 중인 제안에는 이걸 씌우지 않는다.** 답해야 할 것을 손짓
  /// 한 번으로 치울 수 있으면, 상대는 답을 못 받은 채 기다리게 된다
  Widget _dismissibleRow(Invite i, DateTime now) {
    final roles = GoRoles.of(context);
    return Dismissible(
      key: ValueKey(i.sessionId),
      // 어느 쪽으로 밀어도 된다 — 방향을 외우게 하지 않는다
      background: _swipeBackground(roles, Alignment.centerLeft),
      secondaryBackground: _swipeBackground(roles, Alignment.centerRight),
      onDismissed: (_) => _hidden.hide([i.sessionId]),
      child: _row(i, now),
    );
  }

  Widget _swipeBackground(GoRoles roles, Alignment align) => Container(
        margin: const EdgeInsets.fromLTRB(22, 0, 22, 10),
        padding: const EdgeInsets.symmetric(horizontal: GoSpace.hero),
        alignment: align,
        decoration: BoxDecoration(
          color: roles.canvas,
          borderRadius: BorderRadius.circular(GoRadius.md),
        ),
        child: Icon(Icons.close, size: 20, color: roles.textSecondary),
      );

  Future<void> _clearAll(List<Invite> done) async {
    final confirmed = await GoDialog.confirm(
      context,
      title: '지난 제안 ${done.length}건을 지울까요?',
      body: '내 목록에서만 사라져요. 상대에게 남은 기록은 그대로예요.',
      confirmLabel: '지우기',
    );
    if (confirmed != true) return;
    await _hidden.hide(done.map((i) => i.sessionId));
  }

  Widget _empty() {
    final roles = GoRoles.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 60, 22, 0),
      child: Column(children: [
        Icon(Icons.mail_outline, size: 28, color: roles.textDisabled),
        const SizedBox(height: 12),
        Text('오가는 제안이 없어요',
            style: GoText.heading.copyWith(color: roles.textSecondary)),
      ]),
    );
  }

  Widget _row(Invite i, DateTime now) {
    final roles = GoRoles.of(context);
    final name = _nameOf(i.partnerUid);
    final card = i.cardFor(now);
    final (String title, String? sub) = switch (card) {
      InviteCard.needsAnswer => ('$name님이 부르고 있어요', _left(i, now)),
      InviteCard.waitingAnswer => ('$name님에게 보냈어요', _left(i, now)),
      InviteCard.joinable => ('$name님과 준비하러 가요', null),
      InviteCard.declined => (
          '$name님이 지금은 어렵대요',
          i.declineMessage?.trim().isNotEmpty == true
              ? '"${i.declineMessage!.trim()}"'
              : null
        ),
      InviteCard.expired => ('$name님에게 답이 오지 않았어요', null),
      InviteCard.cancelled => ('$name님과의 제안이 취소됐어요', null),
      InviteCard.none => ('$name님', null),
    };

    return GoCard(
      margin: const EdgeInsets.fromLTRB(22, 0, 22, 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Row(children: [
        GoAvatar(size: 44, photoUrl: _profiles[i.partnerUid]?['photoUrl'] as String?),
        const SizedBox(width: GoSpace.m),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    maxLines: 2,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: roles.textPrimary)),
                if (sub != null) ...[
                  const SizedBox(height: 2),
                  Text(sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: roles.textSecondary)),
                ],
              ]),
        ),
        const SizedBox(width: GoSpace.s),
        _action(i, card, name),
      ]),
    );
  }

  String? _left(Invite i, DateTime now) {
    final r = i.remaining(now);
    if (r == null) return null;
    final m = r.inMinutes;
    return m >= 1 ? '$m분 남음' : '곧 만료돼요';
  }

  Widget _action(Invite i, InviteCard card, String name) => switch (card) {
        InviteCard.needsAnswer => Row(mainAxisSize: MainAxisSize.min, children: [
            GoButton('나중에',
                kind: GoButtonKind.text,
                size: GoButtonSize.md,
                onTap: () => _decline(i.sessionId)),
            const SizedBox(width: 2),
            GoButton('수락',
                kind: GoButtonKind.primary,
                size: GoButtonSize.md,
                onTap: () => _accept(i.sessionId, name)),
          ]),
        InviteCard.joinable => GoButton('입장',
            kind: GoButtonKind.primary,
            size: GoButtonSize.md,
            onTap: () => _enter(i.sessionId, name)),
        InviteCard.waitingAnswer => GoButton('취소',
            kind: GoButtonKind.text,
            size: GoButtonSize.md,
            onTap: () => _run(() => _runs.cancelSession(i.sessionId),
                '취소하지 못했어요. 다시 시도해 주세요.')),
        // 지난 제안은 시간이 지나면 목록에서 스스로 빠진다 — 닫기 버튼을
        // 두면 손으로 치워야 할 것이 하나 더 늘 뿐이다
        _ => const SizedBox.shrink(),
      };

  Future<void> _run(Future<void> Function() action, String fail) async {
    try {
      await action();
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (!mounted) return;
      GoToast.error(context, fail);
    }
  }

  Future<void> _accept(String sessionId, String name) async {
    try {
      await _runs.acceptSession(sessionId);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (!mounted) return;
      GoToast.error(context, '수락하지 못했어요. 다시 시도해 주세요.');
      return;
    }
    if (mounted) _enter(sessionId, name);
  }

  void _enter(String sessionId, String name) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => LobbyScreen(sessionId: sessionId, partnerName: name),
    ));
  }

  /// 침묵 대신 한 줄 — 홈의 수락 시트와 같은 선택지를 쓴다
  void _decline(String sessionId) {
    const options = ['지금은 어려워요', '30분 뒤 어때요?', '오늘은 쉬고 싶어요'];
    showModalBottomSheet(
      context: context,
      backgroundColor: GoRoles.of(context).surfaceHigh,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(
            GoSpace.sheet, GoSpace.xl, GoSpace.sheet, GoSpace.sheetBottom),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('어떻게 전할까요?', style: GoText.heading),
              const SizedBox(height: 16),
              ...options.map((o) => Padding(
                    padding: const EdgeInsets.only(bottom: GoSpace.s),
                    child: GoButton(o,
                        kind: GoButtonKind.secondary,
                        onTap: () {
                          Navigator.pop(ctx);
                          _run(() => _runs.declineSession(sessionId, o),
                              '전하지 못했어요. 다시 시도해 주세요.');
                        }),
                  )),
            ]),
      ),
    );
  }
}
