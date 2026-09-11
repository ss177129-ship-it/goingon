import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/friend_service.dart';
import '../services/invite.dart';
import '../services/invite_service.dart';
import '../services/pacemate_status.dart';
import '../services/run_service.dart';
import '../services/thread_service.dart';
import '../theme.dart';
import '../widgets/go_avatar.dart';
import '../widgets/go_button.dart';
import '../widgets/go_dialog.dart';
import '../widgets/go_icon_button.dart';
import '../widgets/go_toast.dart';
import 'lobby_screen.dart';

/// 한 사람과의 대화 — 이 앱에서 관계가 사는 유일한 줄기.
///
/// ## 제안이 여기 있다
///
/// 전에는 GO?가 홈에 있고, 답은 '제안' 탭에 있고, 준비는 로비에 있었다.
/// 한 가지 일이 세 화면에 흩어져 있으면 사람은 그 사이를 기억으로 이어야 한다.
/// 여기서는 **제안이 대화의 한 줄**이다 — 부르는 것도, 답하는 것도, 결과도
/// 같은 화면에서 위아래로 이어진다.
///
/// ## 제안은 말풍선이 아니라 사건이다
///
/// 그래서 폭을 다 쓰고 테두리를 두른다. 텍스트 말풍선과 같은 무게로 그리면
/// 스크롤 속에서 흘러가 버리는데, 이건 **답을 해야 끝나는 것**이다.
///
/// ## 지금은 세션에서 읽는다
///
/// 3단계에서 제안이 `threads/{tid}/messages`의 `invite` 메시지가 되면
/// 이 화면의 [InviteService] 구독은 사라지고 카드가 메시지 목록 안으로
/// 들어간다. 보이는 모양은 그대로고 출처만 바뀐다.
class ThreadScreen extends StatefulWidget {
  const ThreadScreen({
    super.key,
    required this.partnerUid,
    required this.partnerName,
  });

  final String partnerUid;
  final String partnerName;

  @override
  State<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<ThreadScreen> {
  final _auth = AuthService();
  final _threads = ThreadService();
  final _invites = InviteService();
  final _runs = RunService();
  final _friends = FriendService();

  final _input = TextEditingController();
  final _inputFocus = FocusNode();

  StreamSubscription? _msgSub;
  StreamSubscription? _inviteSub;
  StreamSubscription? _friendsSub;

  List<QueryDocumentSnapshot<Map<String, dynamic>>>? _messages;
  List<Invite> _liveInvites = const [];
  Map<String, dynamic>? _mate;

  bool _broken = false;
  bool _sending = false;

  /// GO?를 누른 뒤 세션이 스트림으로 돌아오기까지의 한 박자.
  /// 없으면 두 번 눌러 세션이 둘 생긴다
  bool _proposing = false;

  /// 마지막으로 읽음 처리한 메시지 id.
  ///
  /// 한 번만 걸고 마는 빗장이면 **화면을 보고 있는 동안 온 말이 안 읽음으로
  /// 남는다** — 상대가 답하는 걸 눈앞에서 보면서 탭 배지에는 3이 뜨고,
  /// 화면을 나갔다 다시 들어와야 지워진다. 그래서 "새 말이 왔고 그게 내 말이
  /// 아니면" 다시 건다. 쓰기는 들어오는 묶음당 한 번이다
  String? _markedUpTo;

  /// 화면에 들어와 처음 받은 스냅샷인가.
  ///
  /// **들어왔을 때는 맨 아래가 내 말이어도 한 번은 지운다.** 안 읽음은
  /// 그 전에 쌓인 것이라 맨 아랫줄과 상관이 없다 — 실제로 달리기를 마치면
  /// 결과 줄이 맨 아래에 서는데, 그것 때문에 수락 때 올라간 배지 1이
  /// 영영 안 지워졌다. 러닝마다 하나씩 쌓였다
  bool _firstSnapshot = true;

  Timer? _tick;

  late final String _threadId =
      ThreadService.idFor(_auth.uid, widget.partnerUid);

  @override
  void initState() {
    super.initState();
    _listen();
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _listen() {
    _msgSub?.cancel();
    _msgSub = _threads.messages(_threadId).listen((snap) {
      if (!mounted) return;
      setState(() {
        _messages = snap.docs;
        _broken = false;
      });
      // **말이 하나라도 있을 때만** 읽음 처리를 한다.
      //
      // 아직 아무도 말한 적 없으면 스레드 문서가 없는데, 없는 문서의
      // `update`는 `not-found`가 아니라 **권한 거부**로 돌아온다 — 규칙의
      // `diff(resource.data)`가 null을 참조해 쓰기 전제조건까지 가지도
      // 못하기 때문이다. 그걸 매번 삼키기 시작하면 진짜 거부까지 감춰진다
      _maybeMarkRead(snap.docs);
    }, onError: (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (mounted) setState(() => _broken = true);
    });

    _inviteSub?.cancel();
    _inviteSub = _invites.stream(_auth.uid).listen((list) {
      if (mounted) setState(() => _liveInvites = list);
    }, onError: (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
    });

    _friendsSub?.cancel();
    _friendsSub = _friends.friendsStream(_auth.uid).listen((list) {
      if (!mounted) return;
      for (final m in list) {
        if (m['uid'] == widget.partnerUid) {
          setState(() => _mate = m);
          return;
        }
      }
    }, onError: (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
    });
  }

  /// 안 읽음을 0으로 되돌린다 — 내가 아직 안 본 **상대의** 말이 새로 왔을 때만.
  ///
  /// 내가 보낸 말에는 반응하지 않는다(내 것은 애초에 내 칸을 올리지 않는다).
  /// 같은 메시지에 두 번 걸지 않으므로 스크롤이나 재구독으로는 쓰기가 안 생긴다
  void _maybeMarkRead(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    if (docs.isEmpty) return;
    final newest = docs.first; // 최신이 먼저 오는 정렬이다
    final first = _firstSnapshot;
    _firstSnapshot = false;

    if (!first) {
      if (newest.id == _markedUpTo) return;
      if (newest.data()['senderId'] == _auth.uid) {
        // 머무는 동안 **내가** 보낸 말은 내 칸을 올리지 않는다.
        // 여기까지 읽었다는 표시만 옮긴다
        _markedUpTo = newest.id;
        return;
      }
    }

    _markedUpTo = newest.id;
    _threads.markRead(_threadId, _auth.uid).catchError((e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
    });
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _inviteSub?.cancel();
    _friendsSub?.cancel();
    _tick?.cancel();
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roles = GoRoles.of(context);
    final now = DateTime.now();
    final invite = currentInviteFor(_liveInvites, widget.partnerUid, now);

    return Scaffold(
      backgroundColor: roles.background,
      // 키보드가 올라오면 입력창이 그 위에 앉아야 한다
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          _header(roles, now, invite),
          // 제안 카드는 **목록 안**에 있다. 입력창 위에 따로 얹으면
          // 작은 화면에서 키보드가 올라올 때 Column이 넘친다 —
          // 헤더 60 + 카드 150 + 입력창 64가 남은 높이를 먹고 대화가 0이 된다.
          // 목록 안에 두면 스크롤이 알아서 흡수하고, 제안이 대화의 한 줄이라는
          // 설계와도 맞는다
          Expanded(child: _body(roles, now, invite)),
          _composer(roles),
        ]),
      ),
    );
  }

  // ── 헤더 — 이 사람이 누구이고 지금 무엇을 할 수 있는가 ──────────────

  Widget _header(GoRoles roles, DateTime now, Invite? invite) {
    final status = PacemateStatus.of(_mate, now);
    // 오가는 제안이 있으면 GO?를 숨긴다 — 카드가 이미 그 이야기를 하고 있고,
    // 여기에 버튼이 또 있으면 세션을 둘 만들게 된다
    final canPropose = invite == null || !invite.isOpen(now);

    return Container(
      padding: const EdgeInsets.fromLTRB(6, 4, 20, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: roles.line)),
      ),
      child: Row(children: [
        GoIconButton(
          icon: Icons.arrow_back_ios_new,
          size: 20,
          tooltip: '뒤로',
          onTap: () => Navigator.pop(context),
        ),
        const SizedBox(width: 2),
        SizedBox(
          width: 40,
          height: 40,
          child: Stack(clipBehavior: Clip.none, children: [
            GoAvatar(size: 40, photoUrl: _mate?['photoUrl'] as String?),
            if (status.tone != PacemateTone.quiet)
              Positioned(
                right: -1,
                bottom: -1,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: status.tone == PacemateTone.active
                        ? roles.success.fg
                        : roles.textDisabled,
                    border: Border.all(color: roles.background, width: 2),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(width: GoSpace.m),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.partnerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: roles.textPrimary)),
                // 상태 줄은 **주 단위**다. 이 앱은 "지금 달릴 수 있는가"를
                // 구조적으로 읽을 수 없다 — 없는 것을 있다고 말하지 않는다
                if (status.label.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(status.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: status.tone == PacemateTone.active
                            ? roles.success.fg
                            : roles.textSecondary,
                      )),
                ],
              ]),
        ),
        if (canPropose) ...[
          const SizedBox(width: GoSpace.s),
          GoButton('GO?',
              kind: GoButtonKind.primary,
              size: GoButtonSize.md,
              serifLabel: true,
              loading: _proposing,
              onTap: _proposing ? null : _propose),
        ],
      ]),
    );
  }

  // ── 대화 ────────────────────────────────────────────────────────

  Widget _body(GoRoles roles, DateTime now, Invite? invite) {
    if (_broken) {
      return _centered(
        roles,
        Icons.wifi_off,
        '대화를 불러오지 못했어요',
        action: GoButton('다시 시도',
            kind: GoButtonKind.text,
            size: GoButtonSize.md,
            onTap: () {
              setState(() => _broken = false);
              _listen();
            }),
      );
    }
    final docs = _messages;
    if (docs == null) return const SizedBox.shrink();

    // 답할 수 있는 제안은 **언제나 맨 아래**에 선다.
    //
    // 처음에는 자기 메시지 자리에 인라인으로 그렸는데, 그 사이 말을 스무 줄
    // 주고받으면 카드가 화면 밖으로 밀려 올라간다. 헤더의 GO?는 제안이
    // 오가는 동안 숨겨져 있으므로, **답할 수도 다시 부를 수도 없는 상태**가
    // 된다 — 그리고 그 증상이 50개 창을 넘겼는지에 따라 뒤집혔다.
    //
    // 지금은 제안한 시각을 타임라인이 한 줄로 말하고([_message]의 invite
    // 분기), 답하는 카드는 항상 손 닿는 곳에 있다
    final card = (invite != null && invite.isOpen(now))
        ? _inviteCard(roles, invite, now)
        : null;

    if (docs.isEmpty) {
      if (card == null) {
        return _centered(roles, Icons.chat_bubble_outline, '아직 나눈 말이 없어요',
            sub: '멀리 있어도 같이 달릴 수 있어요');
      }
      // 말은 없고 제안만 있는 사이 — 카드가 화면 아래쪽에 앉는다
      return ListView(
        reverse: true,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        children: [card],
      );
    }

    // 최신이 먼저 오므로 reverse로 그린다 — 새 말이 입력창 바로 위에 선다.
    // reverse 목록에서 인덱스 0은 **맨 아래**이므로, 제안 카드는 0번이다
    final head = card == null ? 0 : 1;
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      itemCount: docs.length + head,
      itemBuilder: (context, index) {
        if (card != null && index == 0) return card;
        final i = index - head;
        final doc = docs[i];
        final d = doc.data();
        // docs는 최신이 먼저다. 인덱스가 하나 큰 쪽이 **더 오래된** 말이고,
        // reverse 목록에서는 그것이 화면상 바로 위에 그려진다
        final prev = i + 1 < docs.length ? docs[i + 1].data() : null;
        final at = _timeOf(d);
        final prevAt = prev == null ? null : _timeOf(prev);
        final needsDate = at != null &&
            (prevAt == null || !_sameDay(at, prevAt));

        return Column(children: [
          if (needsDate) _dateDivider(roles, at),
          _message(roles, doc.id, d, now, invite),
        ]);
      },
    );
  }

  Widget _centered(GoRoles roles, IconData icon, String title,
      {String? sub, Widget? action}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(GoSpace.xl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 28, color: roles.textDisabled),
          const SizedBox(height: 12),
          Text(title,
              textAlign: TextAlign.center,
              style: GoText.heading.copyWith(color: roles.textSecondary)),
          if (sub != null) ...[
            const SizedBox(height: 6),
            Text(sub, textAlign: TextAlign.center, style: GoText.secondary),
          ],
          if (action != null) ...[const SizedBox(height: 8), action],
        ]),
      ),
    );
  }

  static DateTime? _timeOf(Map<String, dynamic> d) {
    final ts = d['at'];
    return ts is Timestamp ? ts.toDate() : null;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _dateDivider(GoRoles roles, DateTime at) {
    final now = DateTime.now();
    final label = _sameDay(at, now)
        ? '오늘'
        : _sameDay(at, now.subtract(const Duration(days: 1)))
            ? '어제'
            : '${at.month}월 ${at.day}일';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(children: [
        Expanded(child: Container(height: 1, color: roles.line)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(label,
              style: GoText.label.copyWith(color: roles.textDisabled)),
        ),
        Expanded(child: Container(height: 1, color: roles.line)),
      ]),
    );
  }

  /// 대화의 한 줄. **제안도 결과도 여기 산다.**
  ///
  /// 이게 3단계의 전부다 — 전에는 같은 세션을 홈 카드·제안 탭·로비가 각각
  /// 그렸고, 12시간이 지나면 흔적이 사라졌다. 지금은 상태가 바뀔 때마다
  /// 줄이 하나 더 붙을 뿐이고 위에 쌓인 것은 그대로 남는다
  Widget _message(GoRoles roles, String id, Map<String, dynamic> d,
      DateTime now, Invite? invite) {
    final type = (d['type'] as String?) ?? 'text';
    switch (type) {
      case 'invite':
        // 제안한 **시각**을 말하는 줄이다. 답하는 카드는 맨 아래에 있다
        return _quietLine(roles, Icons.directions_run, '같이 달리기를 제안했어요');

      case 'inviteResult':
        return _quietLine(
            roles, Icons.chat_bubble_outline, (d['text'] as String?) ?? '답했어요');

      case 'runResult':
        return _runResultCard(roles, d);

      case 'system':
        return _quietLine(
            roles, Icons.info_outline, (d['text'] as String?) ?? '');

      default:
        return _bubble(roles, id, d);
    }
  }

  /// 함께 달린 기록 — 이 카드가 쌓이면 그 줄기 자체가 두 사람의 기록이 된다.
  /// '우리' 탭이 한 사람만 보던 것을 관계마다 갖게 되는 자리다
  Widget _runResultCard(GoRoles roles, Map<String, dynamic> d) {
    final meta = d['meta'];
    final results = meta is Map ? meta['results'] : null;
    final mine = results is Map ? results[_auth.uid] : null;
    // 서버가 쓰는 맵이라 타입을 믿지 않는다 — `as Map`으로 목록이 통째로
    // 죽으면 지난 대화 전체가 안 보인다
    final seconds = (mine is Map && mine['seconds'] is num)
        ? (mine['seconds'] as num).toInt()
        : null;
    final km = (mine is Map && mine['km'] is num)
        ? (mine['km'] as num).toDouble()
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(GoSpace.l, 14, GoSpace.l, 14),
      decoration: BoxDecoration(
        color: roles.surface,
        border: Border.all(color: roles.line),
        borderRadius: BorderRadius.circular(GoRadius.md),
        boxShadow: GoShadow.card,
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('함께 달렸어요',
                style: GoText.label.copyWith(color: roles.textSecondary)),
            const SizedBox(height: 8),
            if (seconds == null && km == null)
              const Text('기록이 남지 않았어요', style: GoText.secondary)
            else
              Row(crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    if (seconds != null)
                      Text(_clock(seconds), style: GoTheme.serif(28)),
                    if (seconds != null && km != null)
                      const SizedBox(width: 14),
                    if (km != null)
                      Text.rich(TextSpan(
                        text: km.toStringAsFixed(1),
                        style: GoTheme.serif(22, color: roles.textSecondary),
                        children: [
                          TextSpan(
                              text: 'km',
                              style: GoTheme.serif(14,
                                  color: roles.textSecondary)),
                        ],
                      )),
                  ]),
          ]),
    );
  }

  static String _clock(int seconds) {
    final m = seconds ~/ 60, s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _bubble(GoRoles roles, String id, Map<String, dynamic> d) {
    final mine = d['senderId'] == _auth.uid;
    final text = (d['text'] as String?) ?? '';
    if (text.isEmpty) return const SizedBox.shrink();

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      // 상대의 말만 길게 눌러 신고한다. 내 말을 신고할 일은 없고,
      // 길게 누르기가 아무 데서나 반응하면 무슨 기능인지 흐려진다
      child: GestureDetector(
        onLongPress: mine ? null : () => _showMessageActions(id, d),
        child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: const BoxConstraints(maxWidth: 264),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: mine ? roles.dark.bg : roles.surface,
          border: mine ? null : Border.all(color: roles.line),
          // 꼬리 쪽만 각지게 — 누가 한 말인지 형태로도 말한다
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(GoRadius.md),
            topRight: const Radius.circular(GoRadius.md),
            bottomLeft: Radius.circular(mine ? GoRadius.md : 4),
            bottomRight: Radius.circular(mine ? 4 : GoRadius.md),
          ),
          boxShadow: mine ? null : GoShadow.card,
        ),
        child: Text(text,
            style: GoText.body
                .copyWith(color: mine ? roles.dark.fg : roles.textPrimary)),
        ),
      ),
    );
  }

  // ── 제안 카드 ────────────────────────────────────────────────────

  Widget _inviteCard(GoRoles roles, Invite invite, DateTime now) {
    final card = invite.cardFor(now);
    final name = widget.partnerName;

    switch (card) {
      case InviteCard.needsAnswer:
        return _inviteFrame(
          roles,
          border: roles.actionPrimary.bg,
          title: '$name님이 부르고 있어요',
          sub: _left(invite, now),
          subColor: roles.warning.fg,
          actions: Row(children: [
            Expanded(
              child: GoButton('안 될 것 같아',
                  kind: GoButtonKind.secondary,
                  onTap: () => _decline(invite.sessionId)),
            ),
            const SizedBox(width: GoSpace.m),
            Expanded(
              child: GoButton('수락',
                  kind: GoButtonKind.complete,
                  onTap: () => _accept(invite.sessionId)),
            ),
          ]),
        );

      case InviteCard.waitingAnswer:
        return _inviteFrame(
          roles,
          border: roles.line,
          title: '답을 기다리는 중',
          titleColor: roles.textSecondary,
          sub: _left(invite, now),
          subColor: roles.warning.fg,
          trailing: GoButton('취소',
              kind: GoButtonKind.secondary,
              size: GoButtonSize.md,
              onTap: () => _guard(
                  () => _runs.cancelSession(invite.sessionId),
                  '취소하지 못했어요. 다시 시도해 주세요.')),
        );

      case InviteCard.joinable:
        return _inviteFrame(
          roles,
          border: roles.success.fg,
          fill: roles.success.bg,
          title: '함께 달리기로 했어요',
          titleColor: roles.success.fg,
          sub: '준비하러 가요',
          subColor: roles.success.fg,
          trailing: GoButton('입장',
              kind: GoButtonKind.complete,
              size: GoButtonSize.md,
              onTap: () => _enterLobby(invite.sessionId)),
        );

      // 끝난 것에는 버튼을 달지 않는다. 결과는 행동이 아니라 기록이라
      // 조용한 한 줄로 내려앉고, 다음 제안이 그 위에 새로 선다
      case InviteCard.declined:
        final msg = invite.declineMessage?.trim();
        return _quietLine(roles, Icons.chat_bubble_outline,
            msg != null && msg.isNotEmpty ? '“$msg”' : '$name님이 지금은 어렵대요');
      case InviteCard.expired:
        return _quietLine(roles, Icons.schedule, '답이 오지 않았어요');
      case InviteCard.cancelled:
        return _quietLine(roles, Icons.highlight_off, '제안을 거뒀어요');
      case InviteCard.none:
        return const SizedBox.shrink();
    }
  }

  Widget _inviteFrame(
    GoRoles roles, {
    required Color border,
    Color? fill,
    required String title,
    Color? titleColor,
    String? sub,
    Color? subColor,
    Widget? actions,
    Widget? trailing,
  }) {
    return Container(
      // 좌우 여백은 목록의 padding이 이미 준다. 여기서 또 주면 카드만
      // 말풍선보다 40px 좁아져 같은 열에 있는 것들이 안 맞는다
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(GoSpace.l),
      decoration: BoxDecoration(
        color: fill ?? roles.surfaceHigh,
        border: Border.all(color: border, width: GoStroke.accent),
        borderRadius: BorderRadius.circular(GoRadius.md),
        boxShadow: GoShadow.elevated,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Text('GO?',
              style: GoTheme.serif(20,
                  color: titleColor ?? roles.actionPrimary.bg)),
          const SizedBox(width: GoSpace.s),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      maxLines: 2,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: titleColor ?? roles.textPrimary)),
                  if (sub != null && sub.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(sub,
                        maxLines: 1,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: subColor ?? roles.textSecondary)),
                  ],
                ]),
          ),
          if (trailing != null) ...[const SizedBox(width: GoSpace.s), trailing],
        ]),
        if (actions != null) ...[const SizedBox(height: GoSpace.m), actions],
      ]),
    );
  }

  Widget _quietLine(GoRoles roles, IconData icon, String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(
          horizontal: GoSpace.l, vertical: GoSpace.m),
      decoration: BoxDecoration(
        color: roles.canvas,
        borderRadius: BorderRadius.circular(GoRadius.md),
      ),
      child: Row(children: [
        Icon(icon, size: 16, color: roles.textSecondary),
        const SizedBox(width: GoSpace.s),
        Expanded(
          child: Text(text,
              maxLines: 2,
              style: TextStyle(fontSize: 13, color: roles.textSecondary)),
        ),
      ]),
    );
  }

  String _left(Invite i, DateTime now) {
    final r = i.remaining(now);
    if (r == null) return '';
    final m = r.inMinutes;
    return m >= 1 ? '$m분 남음' : '곧 만료돼요';
  }

  // ── 입력창 ──────────────────────────────────────────────────────

  Widget _composer(GoRoles roles) {
    return Container(
      // viewPadding이 아니라 padding이다 — 키보드가 올라오면 padding.bottom은
      // 0이 되므로 홈 인디케이터 자리가 키보드 위에 한 번 더 붙지 않는다
      padding: EdgeInsets.fromLTRB(
          20, 10, 20, 10 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: roles.background,
        border: Border(top: BorderSide(color: roles.line)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: GoSpace.l),
            decoration: BoxDecoration(
              color: roles.surface,
              border: Border.all(
                  color: roles.actionSecondary.border ?? roles.line,
                  width: GoStroke.card),
              borderRadius: BorderRadius.circular(GoRadius.md),
            ),
            child: TextField(
              controller: _input,
              focusNode: _inputFocus,
              maxLines: 4,
              minLines: 1,
              // 규칙에도 같은 상한이 있다. 여기서 먼저 막아야 사용자가
              // 긴 글을 다 쓰고 나서 거부당하지 않는다
              maxLength: ThreadService.maxTextLength,
              buildCounter: (_,
                      {required currentLength,
                      required isFocused,
                      required maxLength}) =>
                  null,
              textInputAction: TextInputAction.newline,
              style: GoText.body,
              cursorColor: roles.textPrimary,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                hintText: '메시지',
                hintStyle: GoText.body.copyWith(color: roles.textDisabled),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ),
        const SizedBox(width: GoSpace.s),
        _sendButton(roles),
      ]),
    );
  }

  Widget _sendButton(GoRoles roles) {
    final ready = _input.text.trim().isNotEmpty && !_sending;
    return Semantics(
      button: true,
      label: '보내기',
      child: GestureDetector(
        onTap: ready ? _send : null,
        child: AnimatedContainer(
          duration: GoMotion.select,
          curve: GoMotion.curve,
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: ready ? roles.actionComplete.bg : roles.canvas,
            borderRadius: BorderRadius.circular(GoRadius.md),
          ),
          child: Icon(Icons.arrow_upward_rounded,
              size: 20,
              color: ready ? roles.actionComplete.fg : roles.textDisabled),
        ),
      ),
    );
  }

  // ── 동작 ────────────────────────────────────────────────────────

  Future<void> _send() async {
    final body = _input.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _threads.sendText(
        myUid: _auth.uid,
        partnerUid: widget.partnerUid,
        text: body,
      );
      _input.clear();
    } on ArgumentError {
      // 길이 초과는 네트워크 문제가 아니다. 같은 문구로 뭉뚱그리면
      // 사용자가 고칠 수 있는 것을 못 고친다
      if (mounted) {
        GoToast.error(
            context, '메시지가 너무 길어요. ${ThreadService.maxTextLength}자까지 보낼 수 있어요.');
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (!mounted) return;
      // 조용히 삼키면 보낸 줄 알고 기다리게 된다. 맞팔이 끊겼거나
      // 차단당했으면 규칙이 권한 거부로 돌려보낸다
      GoToast.error(context, '보내지 못했어요. 연결이 끊겼을 수 있어요.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// GO? — 세션을 만들고 화면은 그대로 둔다. 카드가 스트림으로 돌아와
  /// 입력창 위에 선다
  Future<void> _propose() async {
    if (_proposing) return;
    setState(() => _proposing = true);
    try {
      await _runs.createSession(_auth.uid, widget.partnerUid);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (mounted) {
        GoToast.error(context, '보내지 못했어요. 다시 시도해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _proposing = false);
    }
  }

  Future<void> _accept(String sessionId) async {
    try {
      // 수락은 **문서에 써야 성립한다.** 규칙이 invited인 세션에는 준비도
      // 출발도 걸어 주지 않으므로, 쓰기가 실패하면 로비로 보내면 안 된다
      await _runs.acceptSession(sessionId);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (!mounted) return;
      GoToast.error(context, '수락하지 못했어요. 다시 시도해 주세요.');
      return;
    }
    if (mounted) _enterLobby(sessionId);
  }

  void _enterLobby(String sessionId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LobbyScreen(
            sessionId: sessionId, partnerName: widget.partnerName),
      ),
    );
  }

  /// 침묵 대신 한 줄.
  ///
  /// **이 선택지는 home_screen에도 똑같이 박혀 있다.** 3단계에서 제안이
  /// 메시지가 되면 한곳으로 모은다 — 지금 옮기면 두 화면이 동시에 흔들린다
  static const _declineOptions = [
    '지금은 어려워요',
    '30분 뒤 어때요?',
    '오늘은 쉬고 싶어요',
  ];

  void _decline(String sessionId) {
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
              ..._declineOptions.map((o) => Padding(
                    padding: const EdgeInsets.only(bottom: GoSpace.s),
                    child: GoButton(o,
                        kind: GoButtonKind.secondary,
                        onTap: () {
                          Navigator.pop(ctx);
                          _guard(() => _runs.declineSession(sessionId, o),
                              '전하지 못했어요. 다시 시도해 주세요.');
                        }),
                  )),
            ]),
      ),
    );
  }

  // ── 신고와 차단 ─────────────────────────────────────────────────
  //
  // 사용자끼리 글을 주고받는 기능이 있으면 앱스토어가 신고·차단·필터를
  // 요구한다(App Store Review Guideline 1.2 UGC). 맞팔 게이트가 가장 큰
  // 방어이고(모르는 사람이 말을 걸 수 없다) 차단은 이미 있었다.
  // **신고가 비어 있던 자리**다 — 심사에 걸리는 것도 여기다.

  void _showMessageActions(String messageId, Map<String, dynamic> d) {
    final roles = GoRoles.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: roles.surfaceHigh,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(
            GoSpace.sheet, GoSpace.xl, GoSpace.sheet, GoSpace.sheetBottom),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('"${(d['text'] as String?) ?? ''}"',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoText.secondary),
              const SizedBox(height: 16),
              GoButton('신고하기',
                  kind: GoButtonKind.secondary,
                  destructive: true,
                  onTap: () {
                    Navigator.pop(ctx);
                    _report(messageId);
                  }),
              const SizedBox(height: GoSpace.s),
              GoButton('${widget.partnerName}님 차단하기',
                  kind: GoButtonKind.secondary,
                  destructive: true,
                  onTap: () {
                    Navigator.pop(ctx);
                    _block();
                  }),
            ]),
      ),
    );
  }

  /// 신고는 **한 번에 접수된다** — 사유를 고르게 하지 않는다.
  ///
  /// 불쾌한 말을 받은 사람에게 분류까지 시키면 신고를 포기한다. 무엇이
  /// 문제였는지는 대화를 읽는 사람이 판단한다(reporterUid·threadId·messageId가
  /// 같이 간다). 읽기는 아무에게도 열려 있지 않다 — 신고당한 사람이 자기
  /// 신고를 볼 수 있으면 보복이 시작된다
  Future<void> _report(String messageId) async {
    final ok = await GoDialog.confirm(
      context,
      title: '이 메시지를 신고할까요?',
      body: '대화 내용이 함께 전달돼요. 신고는 상대에게 알려지지 않아요.',
      confirmLabel: '신고',
      destructive: true,
    );
    if (ok != true || !mounted) return;
    try {
      await _threads.report(
        myUid: _auth.uid,
        targetUid: widget.partnerUid,
        threadId: _threadId,
        messageId: messageId,
      );
      if (mounted) GoToast.show(context, '신고가 접수됐어요.');
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (mounted) GoToast.error(context, '신고하지 못했어요. 다시 시도해 주세요.');
    }
  }

  /// 차단하면 `follows` 간선이 끊기므로, 규칙이 **그 순간부터** 새 메시지를
  /// 막는다. 지난 대화는 남는다 — 지우는 것보다 정직하고, 신고 접수함이
  /// 읽어야 할 근거이기도 하다
  Future<void> _block() async {
    final ok = await GoDialog.confirm(
      context,
      title: '${widget.partnerName}님을 차단할까요?',
      body: '서로의 목록에서 사라지고 더는 말을 주고받을 수 없어요. '
          '지난 대화는 남아요.',
      confirmLabel: '차단',
      destructive: true,
    );
    if (ok != true || !mounted) return;
    try {
      await _friends.blockUser(_auth.uid, widget.partnerUid);
      if (!mounted) return;
      // 토스트가 먼저다 — pop 뒤의 context는 이미 사라진 화면의 것이라
      // 확인 문구가 조용히 증발할 수 있다
      GoToast.show(context, '${widget.partnerName}님을 차단했어요.');
      Navigator.pop(context);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (mounted) GoToast.error(context, '차단하지 못했어요. 다시 시도해 주세요.');
    }
  }

  Future<void> _guard(Future<void> Function() action, String fail) async {
    try {
      await action();
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (!mounted) return;
      GoToast.error(context, fail);
    }
  }
}
