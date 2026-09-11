import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/friend_service.dart';
import '../services/invite.dart';
import '../services/invite_service.dart';
import '../services/pacemate_status.dart';
import '../services/thread_service.dart';
import '../theme.dart';
import '../widgets/go_avatar.dart';
import '../widgets/go_button.dart';
import '../widgets/go_card.dart';
import '../widgets/go_group.dart';
import '../widgets/go_toast.dart';
import 'thread_screen.dart';

/// '대화' 탭 — 옛 '제안' 탭의 자리.
///
/// ## 왜 제안 탭이 대화가 되는가
///
/// 제안은 **대화의 한 종류**였지 별도의 사물이 아니었다. 그런데 한 사람과의
/// 일이 네 곳에 흩어져 있었다 — 홈(사람과 GO?), 제안(지금 오가는 것),
/// 우리(쌓인 것), 로비(기다리는 곳). 사람은 시간축이 아니라 **사람**으로
/// 기억하므로, 한 관계는 한 줄기여야 한다.
///
/// 탭을 늘리지 않고 이름이 안 맞게 된 탭을 바꿔 끼운다. 그래서 여기가
/// "나에게 온 모든 것"이 되고, 배지 하나가 그것을 전부 센다 — 전에는 친구
/// 요청이 홈에 있으면서 배지가 없었고(놓치면 상대는 무한정 기다렸다),
/// 러닝 제안만 배지를 갖고 있었다.
///
/// ## 목록의 출처는 `threads`가 아니라 `following`이다
///
/// 스레드로 목록을 만들면 **아직 말을 나눈 적 없는 페이스메이트가 목록에서
/// 사라진다.** 그러면 정작 대화를 시작할 자리가 없다. 페이스메이트가 줄을
/// 갖고, 스레드는 그 줄에 얹힌다([ThreadService.mergeThreads]).
///
/// ## 아직 제안은 세션에서 온다
///
/// 3단계에서 제안이 스레드 안의 말풍선이 되면 이 화면의 [InviteService]
/// 구독은 사라진다. 지금은 세션을 읽어 줄 위에 얹는다 — 데이터 출처만
/// 다르고 보이는 모양은 그때와 같다.
class ThreadsScreen extends StatefulWidget {
  const ThreadsScreen({super.key});

  @override
  State<ThreadsScreen> createState() => _ThreadsScreenState();
}

class _ThreadsScreenState extends State<ThreadsScreen> {
  final _auth = AuthService();
  final _friends = FriendService();
  final _invites = InviteService();
  final _threads = ThreadService();

  StreamSubscription? _friendsSub;
  StreamSubscription? _threadsSub;
  StreamSubscription? _requestsSub;
  StreamSubscription? _invitesSub;

  List<Map<String, dynamic>>? _mates;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _threadDocs = const [];
  List<FriendRequest> _requests = const [];
  List<Invite> _liveInvites = const [];

  /// 스트림이 끊겼다 — 마지막으로 성공한 목록은 그대로 두고 안내만 얹는다.
  /// 여기서 빈 목록으로 지우면 "못 불러온 것"이 "없는 것"처럼 보인다
  bool _broken = false;

  /// 1분마다 다시 그린다 — 남은 시간이 줄어야 하고, 30분이 지나면 문서가
  /// 아직 invited여도 만료로 보여야 한다(서버 정리는 15분마다 돈다)
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _listen();
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _listen() {
    final uid = _auth.uid;

    _friendsSub?.cancel();
    _friendsSub = _friends.friendsStream(uid).listen((list) {
      // 복구되면 배너도 같이 내린다. 성공 쪽에서 안 내리면 잠깐 끊겼던
      // 화면에 "불러오지 못했어요"가 영영 붙어 있는다 — 이 화면은
      // IndexedStack 안이라 State가 앱이 끝날 때까지 안 사라진다
      if (mounted) setState(() { _mates = list; _broken = false; });
    }, onError: (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (mounted) setState(() => _broken = true);
    });

    _threadsSub?.cancel();
    _threadsSub = _threads.threads(uid).listen((snap) {
      if (mounted) setState(() { _threadDocs = snap.docs; _broken = false; });
    }, onError: (e, stack) {
      // 여기가 끊겨도 페이스메이트 줄은 그대로 서 있어야 한다 —
      // 마지막 줄만 비는 것이 목록이 통째로 사라지는 것보다 낫다
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (mounted) setState(() => _broken = true);
    });

    _requestsSub?.cancel();
    _requestsSub = _friends.incomingRequestsStream(uid).listen((list) {
      if (mounted) setState(() { _requests = list; _broken = false; });
    }, onError: (e, stack) {
      // 여기가 조용히 실패하면 **요청이 0건인 것처럼 보인다.** 놓치면
      // 상대는 무한정 기다리므로, 이것만은 화면에 말해야 한다
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (mounted) setState(() => _broken = true);
    });

    _invitesSub?.cancel();
    _invitesSub = _invites.stream(uid).listen((list) {
      if (mounted) setState(() => _liveInvites = list);
    }, onError: (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
    });
  }

  @override
  void dispose() {
    _friendsSub?.cancel();
    _threadsSub?.cancel();
    _requestsSub?.cancel();
    _invitesSub?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  static String _displayName(String? raw) {
    final s = raw?.trim() ?? '';
    return s.isEmpty ? '페이스메이트' : s;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final mates = _mates;

    final rows = mates == null
        ? const <ThreadSummary>[]
        : ThreadService.mergeThreads(
            myUid: _auth.uid,
            pacemates: [
              for (final m in mates)
                (
                  uid: m['uid'] as String,
                  name: _displayName(m['name'] as String?),
                ),
            ],
            threadDocs: _threadDocs,
          );

    // 답할 것이 있는 줄이 맨 위로. mergeThreads는 말이 오간 순서만 알고
    // 제안은 모르므로, 정렬은 여기서 한 번 더 한다 — 오늘 저녁 달릴지
    // 정하는 일이 어제 나눈 인사보다 급하다.
    //
    // 동점에 0을 돌려주면 안 된다. Dart의 sort는 안정 정렬이 아니라서
    // mergeThreads가 정해둔 순서가 다시 그릴 때마다 흔들린다
    final order = {for (var i = 0; i < rows.length; i++) rows[i].partnerUid: i};
    final sorted = [...rows]..sort((a, b) {
        final ao = _openInvite(a.partnerUid, now) != null ? 0 : 1;
        final bo = _openInvite(b.partnerUid, now) != null ? 0 : 1;
        if (ao != bo) return ao - bo;
        return order[a.partnerUid]!.compareTo(order[b.partnerUid]!);
      });

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(22, 18, 22, 10),
          child: Text('대화', style: GoText.title),
        ),
        if (_broken) _notice(),
        if (_requests.isNotEmpty) ..._requestSection(),
        if (mates == null)
          const SizedBox(height: 40)
        else if (sorted.isEmpty)
          _empty()
        else ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 14, 22, 10),
            child: Text('페이스메이트', style: GoText.label),
          ),
          GoGroup(
            margin: const EdgeInsets.symmetric(horizontal: 22),
            rows: [for (final r in sorted) _row(r, now)],
          ),
        ],
        const SizedBox(height: GoSpace.xl),
      ],
    );
  }

  Invite? _openInvite(String partnerUid, DateTime now) {
    final i = currentInviteFor(_liveInvites, partnerUid, now);
    return (i != null && i.isOpen(now)) ? i : null;
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
          child: Text('대화를 불러오지 못했어요.',
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

  Widget _empty() {
    final roles = GoRoles.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 60, 22, 0),
      child: Column(children: [
        Icon(Icons.chat_bubble_outline, size: 28, color: roles.textDisabled),
        const SizedBox(height: 12),
        Text('아직 페이스메이트가 없어요',
            style: GoText.heading.copyWith(color: roles.textSecondary)),
        const SizedBox(height: 6),
        const Text('홈에서 사람을 찾으면 여기에 대화가 생겨요',
            textAlign: TextAlign.center, style: GoText.secondary),
      ]),
    );
  }

  // ── 나에게 온 친구 요청 ──────────────────────────────────────────
  //
  // 홈에서 여기로 옮겨 왔다. "나에게 온 것"이 두 컬렉션·두 화면에 갈라져
  // 있으면서 배지는 하나뿐이었고, 그 하나가 친구 요청을 안 세고 있었다

  List<Widget> _requestSection() {
    return [
      const Padding(
        padding: EdgeInsets.fromLTRB(22, 14, 22, 8),
        child: Text('나에게 온 요청', style: GoText.label),
      ),
      ..._requests.map(_requestRow),
    ];
  }

  Widget _requestRow(FriendRequest r) {
    final name = _displayName(r.name);
    final roles = GoRoles.of(context);
    return GoCard(
      margin: const EdgeInsets.fromLTRB(22, 0, 22, 8),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(children: [
        Row(children: [
          GoAvatar(size: 40, photoUrl: r.photoUrl),
          const SizedBox(width: GoSpace.m),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$name님이 함께 달리고 싶어해요',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: roles.textPrimary)),
                  if (r.username.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text('@${r.username}',
                        style: TextStyle(
                            fontSize: 12, color: roles.textSecondary)),
                  ],
                ]),
          ),
        ]),
        const SizedBox(height: GoSpace.m),
        Row(children: [
          Expanded(
            child: GoButton('거절',
                kind: GoButtonKind.secondary,
                size: GoButtonSize.md,
                onTap: () => _respondToRequest(r, accept: false)),
          ),
          const SizedBox(width: GoSpace.s),
          Expanded(
            flex: 2,
            // 수락은 "연결을 완성한다"이므로 complete(잉크). 주 색은 GO? 하나뿐
            child: GoButton('수락하고 연결',
                kind: GoButtonKind.complete,
                size: GoButtonSize.md,
                onTap: () => _respondToRequest(r, accept: true)),
          ),
        ]),
      ]),
    );
  }

  Future<void> _respondToRequest(FriendRequest r, {required bool accept}) async {
    try {
      if (accept) {
        await _friends.acceptRequest(_auth.uid, r.fromUid);
      } else {
        // 거절은 조용히 — 상대에게 알리지 않음
        await _friends.declineRequest(_auth.uid, r.fromUid);
      }
      if (!mounted || !accept) return;
      GoToast.show(context, '${_displayName(r.name)}님과 연결됐어요!');
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      if (!mounted) return;
      GoToast.error(context, '처리하지 못했어요. 다시 시도해 주세요.');
    }
  }

  // ── 스레드 한 줄 ─────────────────────────────────────────────────

  GoGroupRow _row(ThreadSummary s, DateTime now) {
    final roles = GoRoles.of(context);
    final mate = _mateOf(s.partnerUid);
    final invite = currentInviteFor(_liveInvites, s.partnerUid, now);
    final (String sub, Color subColor, bool strong) =
        _subtitle(s, invite, now, roles);

    return GoGroupRow(
      padding: const EdgeInsets.symmetric(
          horizontal: GoSpace.card, vertical: GoSpace.m),
      onTap: () => _open(s),
      child: Row(children: [
        _avatar(mate, now),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(s.partnerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight:
                            s.unread > 0 ? FontWeight.w700 : FontWeight.w600,
                        color: roles.textPrimary)),
                const SizedBox(height: 3),
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: strong ? FontWeight.w500 : FontWeight.w400,
                      color: subColor,
                    )),
              ]),
        ),
        const SizedBox(width: GoSpace.s),
        _trailing(s, roles),
      ]),
    );
  }

  Map<String, dynamic>? _mateOf(String uid) {
    for (final m in _mates ?? const <Map<String, dynamic>>[]) {
      if (m['uid'] == uid) return m;
    }
    return null;
  }

  /// 아바타 위의 점은 **presence가 아니다.** 이 앱은 "지금 달릴 수 있는가"를
  /// 구조적으로 읽을 수 없다([PacemateStatus] 참고) — 해상도는 주 단위다.
  /// 그래서 조용한 사람에게는 점을 아예 찍지 않는다
  Widget _avatar(Map<String, dynamic>? mate, DateTime now) {
    final roles = GoRoles.of(context);
    final status = PacemateStatus.of(mate, now);
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(clipBehavior: Clip.none, children: [
        GoAvatar(size: 48, photoUrl: mate?['photoUrl'] as String?),
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
                border: Border.all(color: roles.surface, width: 2),
              ),
            ),
          ),
      ]),
    );
  }

  /// 줄 하나가 말할 것은 하나다. 순서가 곧 급한 순서다:
  /// 답해야 할 제안 → 마지막 말 → 지난 결과 → 아직 아무것도
  (String, Color, bool) _subtitle(
      ThreadSummary s, Invite? invite, DateTime now, GoRoles roles) {
    if (invite != null) {
      final card = invite.cardFor(now);
      switch (card) {
        case InviteCard.needsAnswer:
          return ('부르고 있어요${_left(invite, now)}', roles.warning.fg, true);
        case InviteCard.waitingAnswer:
          return ('답을 기다리는 중${_left(invite, now)}', roles.warning.fg, true);
        case InviteCard.joinable:
          return ('준비하러 가요', roles.success.fg, true);
        default:
          break;
      }
    }

    final preview = s.lastPreview?.trim();
    if (preview != null && preview.isNotEmpty) {
      final mine = s.lastSenderId == _auth.uid;
      return (
        mine ? '나: $preview' : preview,
        s.unread > 0 ? roles.textPrimary : roles.textSecondary,
        s.unread > 0,
      );
    }

    if (invite != null) {
      switch (invite.cardFor(now)) {
        case InviteCard.declined:
          final msg = invite.declineMessage?.trim();
          return (
            msg != null && msg.isNotEmpty ? '“$msg”' : '지금은 어렵대요',
            roles.textSecondary,
            false
          );
        case InviteCard.expired:
          return ('답이 오지 않았어요', roles.textSecondary, false);
        case InviteCard.cancelled:
          return ('제안을 거뒀어요', roles.textSecondary, false);
        default:
          break;
      }
    }

    return ('아직 나눈 말이 없어요', roles.textDisabled, false);
  }

  String _left(Invite i, DateTime now) {
    final r = i.remaining(now);
    if (r == null) return '';
    final m = r.inMinutes;
    return m >= 1 ? ' · $m분 남음' : ' · 곧 만료돼요';
  }

  Widget _trailing(ThreadSummary s, GoRoles roles) {
    final when = s.lastAt;
    if (when == null && s.unread == 0) return const SizedBox.shrink();
    return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (when != null)
            Text(_ago(when),
                style: TextStyle(fontSize: 12, color: roles.textDisabled)),
          if (s.unread > 0) ...[
            const SizedBox(height: 5),
            Container(
              constraints: const BoxConstraints(minWidth: 20),
              height: 20,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: roles.actionPrimary.bg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(s.unread > 99 ? '99+' : '${s.unread}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: roles.actionPrimary.fg)),
            ),
          ],
        ]);
  }

  /// 기기 시계가 서버보다 앞서면 음수가 나온다 — "−3분 전"을 보여주느니
  /// '방금'이라고 말한다
  static String _ago(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.isNegative || d.inMinutes < 1) return '방금';
    if (d.inHours < 1) return '${d.inMinutes}분';
    if (d.inHours < 24) return '${d.inHours}시간';
    if (d.inDays == 1) return '어제';
    if (d.inDays < 7) return '${d.inDays}일';
    return '${at.month}/${at.day}';
  }

  void _open(ThreadSummary s) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ThreadScreen(
          partnerUid: s.partnerUid,
          partnerName: s.partnerName,
        ),
      ),
    );
  }
}
