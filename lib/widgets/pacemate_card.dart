import 'package:flutter/material.dart';

import '../services/invite.dart';
import '../services/pacemate_status.dart';
import '../theme.dart';
import 'avatar_photo.dart';
import 'go_avatar.dart';
import 'go_button.dart';
import 'go_card.dart';

/// 홈의 주인공 — 페이스메이트 한 명.
///
/// **왜 행이 아니라 카드인가**(2026-09-09). 전에는 [GoGroup]의 평평한 행
/// 하나였고, 화면에서 가장 큰 것은 내 프로필 카드였다. 이 앱의 값어치는
/// 내 숫자가 아니라 **저쪽에 사람이 있다**는 것이라, 관계가 화면의 1층이
/// 아니라 목록의 한 줄이면 위계가 거꾸로 선다.
///
/// 층은 [GoCard]가 이미 아는 것을 쓴다 — 2층(누르면 열리는 카드)이고,
/// 눌리면 그림자가 접혀 종이 쪽으로 내려앉는다. 여기서 그림자를 새로
/// 만들지 않는다.
///
/// **겹침은 장식이 아니라 정보다.** 상태 점은 아바타의 원 밖으로 걸쳐
/// 나와 카드 면 위에 얹히고, 카드 색과 같은 링을 둘러 "위에 있는 것"으로
/// 읽힌다. 점 하나만으로 뜻을 전하지 않으므로([GoRoles] Color Usage Rules)
/// 바로 옆 한 줄이 같은 말을 글자로도 한다.
class PacemateCard extends StatelessWidget {
  const PacemateCard({
    super.key,
    required this.user,
    required this.name,
    required this.onOpen,
    required this.onGo,
    this.goEnabled = true,
    this.goLoading = false,
    this.answerable = true,
    this.invite,
    this.onAccept,
    this.onDecline,
    this.onCancelInvite,
    this.onJoin,
    this.now,
  });

  /// `users/{uid}` 문서 전체 — 상태 한 줄을 여기서 뽑는다
  final Map<String, dynamic> user;
  final String name;

  /// 카드를 누르면 상세 프로필 시트 (progressive disclosure)
  final VoidCallback onOpen;

  /// 주 행동. 카드 안에서 **유일하게** 색을 가진 것
  final VoidCallback onGo;
  final bool goEnabled;
  final bool goLoading;

  /// 이 카드에서 제안에 답할 수 있는가.
  ///
  /// **홈은 false다**(v1.1). 답하기는 대화 화면으로 옮겼고, 홈 카드는
  /// "지금 무슨 일이 오가는지" 한 줄로 알려주고 `GO?`로 시작하는 자리만
  /// 남는다 — 한 관계에 답할 곳이 둘이면 어느 쪽에서 눌렀는지에 따라
  /// 화면이 달라지고, 그 차이를 사람이 기억해야 한다.
  ///
  /// 기본값이 true인 이유는 기존 테스트 때문이다. 이 카드는 답하기까지
  /// 할 줄 알고, 홈이 그 능력을 안 쓰기로 한 것이다
  final bool answerable;

  /// 이 사람과 지금 오가는 제안. null이면 평소 카드(GO?)
  final Invite? invite;

  /// 받은 제안에 답하기
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;

  /// 내가 보낸 제안 물리기
  final VoidCallback? onCancelInvite;

  /// 수락된 제안 — 로비로
  final VoidCallback? onJoin;

  /// 테스트에서 시간을 고정하기 위한 구멍
  final DateTime? now;

  static const _avatar = 52.0;
  static const _dot = 14.0;

  /// 상태 점은 있을 때와 없을 때가 곧 뜻이라, 테스트가 정확히 집을 수
  /// 있어야 한다 — Stack 안 형제라 자식 관계로는 찾아지지 않는다
  static const dotKey = ValueKey('pacemate-status-dot');

  /// 남은 시간을 사람이 읽는 말로. 초 단위까지 세면 카드가 시계가 된다
  static String _left(Duration d) {
    final m = d.inMinutes;
    return m >= 1 ? '$m분 남음' : '곧 만료돼요';
  }

  @override
  Widget build(BuildContext context) {
    final roles = GoRoles.of(context);
    final at = now ?? DateTime.now();
    final card = invite?.cardFor(at) ?? InviteCard.none;
    final status = PacemateStatus.of(user, at);

    // 제안이 오가는 중이면 그것이 이 카드의 이야기다 — 평소의 러닝 상태
    // 한 줄보다 지금 답해야 할 일이 먼저다
    final (String? line, Color tone) = switch (card) {
      InviteCard.waitingAnswer => (
          [
            '답을 기다리는 중',
            if (invite?.remaining(at) case final r?) _left(r),
          ].join(' · '),
          roles.textSecondary
        ),
      InviteCard.needsAnswer => (
          [
            '$name님이 부르고 있어요',
            if (invite?.remaining(at) case final r?) _left(r),
          ].join(' · '),
          roles.warning.fg
        ),
      InviteCard.joinable => ('준비하러 가요', roles.success.fg),
      InviteCard.declined => (
          invite?.declineMessage?.trim().isNotEmpty == true
              ? '"${invite!.declineMessage!.trim()}"'
              : '지금은 어렵대요',
          roles.textSecondary
        ),
      InviteCard.expired => ('답이 오지 않았어요', roles.textSecondary),
      InviteCard.cancelled => ('그만뒀어요', roles.textSecondary),
      InviteCard.none => (
          status.label.isEmpty ? null : status.label,
          status.tone == PacemateTone.active
              ? roles.success.fg
              : roles.textSecondary
        ),
    };

    return GoCard(
      margin: const EdgeInsets.fromLTRB(22, 0, 22, 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      onTap: onOpen,
      child: Row(children: [
        // 점은 **상태 줄이 그것을 말할 때만** 찍는다. 제안이 오가는 동안엔
        // 줄이 제안 이야기를 하므로, 러닝 활동을 뜻하는 점만 남으면 색
        // 하나가 짝 없이 떠 있게 된다(Color Usage Rules — 색만으로 전하지
        // 않는다). 실제로 거절 문구 옆에 초록 점이 붙어 있었다
        _avatarWithStatus(
            context, card == InviteCard.none ? status : null),
        const SizedBox(width: GoSpace.m),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: roles.textPrimary)),
                // 할 말이 없으면 빈 줄로 자리만 차지하지 않는다
                if (line != null) ...[
                  const SizedBox(height: 2),
                  Text(line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: tone)),
                ],
              ]),
        ),
        const SizedBox(width: GoSpace.s),
        _action(card),
      ]),
    );
  }

  /// 카드의 오른쪽 — **상태마다 할 수 있는 일이 하나씩만** 선다.
  /// 답을 기다리는 중에 GO?가 그대로 남아 있으면 같은 사람을 두 번 부르게 된다
  Widget _action(InviteCard card) {
    // 답하기를 대화로 옮긴 화면에서는 상태와 무관하게 GO?만 선다.
    // **콜백만 null로 두면 안 된다** — switch는 `card`로 갈라지므로
    // 나중에/수락/입장/취소 버튼이 그대로 그려지고 눌러도 아무 일이
    // 일어나지 않는 죽은 버튼이 된다
    if (!answerable) return _goButton(card);

    return switch (card) {
      InviteCard.needsAnswer => Row(mainAxisSize: MainAxisSize.min, children: [
          GoButton('나중에',
              kind: GoButtonKind.text,
              size: GoButtonSize.md,
              onTap: onDecline),
          const SizedBox(width: 2),
          GoButton('수락',
              kind: GoButtonKind.primary,
              size: GoButtonSize.md,
              onTap: onAccept),
        ]),
      InviteCard.joinable => GoButton('입장',
          kind: GoButtonKind.primary, size: GoButtonSize.md, onTap: onJoin),
      InviteCard.waitingAnswer => GoButton('취소',
          kind: GoButtonKind.text,
          size: GoButtonSize.md,
          onTap: onCancelInvite),
      // 끝난 제안은 **주 행동을 가로막지 않는다**(2026-09-09). 전에는
      // GO? 자리에 '확인'이 서서, 다시 부르려면 먼저 안내를 치워야 했다.
      // 무슨 일이 있었는지는 옆의 한 줄이 이미 말하고 있다
      InviteCard.declined ||
      InviteCard.expired ||
      InviteCard.cancelled ||
      InviteCard.none =>
        _goButton(card),
    };
  }

  /// **오가는 중에는 눌리지 않는다.** `answerable: false`인 화면에서도
  /// 이 규칙은 그대로다 — 상대가 나를 부르고 있는데 내가 또 GO?를 누르면
  /// 같은 쌍에 세션이 둘 생긴다. `inviteCollisions`가 뒤늦게 접긴 하지만,
  /// 애초에 눌리지 않는 편이 맞다
  Widget _goButton(InviteCard card) {
    final busy = card == InviteCard.waitingAnswer ||
        card == InviteCard.needsAnswer ||
        card == InviteCard.joinable;
    return GoButton('GO?',
        kind: GoButtonKind.primary,
        size: GoButtonSize.md,
        serifLabel: true,
        loading: goLoading,
        enabled: goEnabled && !busy,
        onTap: onGo);
  }

  /// 사진 + 오른쪽 아래로 걸쳐 나온 상태 점.
  ///
  /// [Stack]이 아바타보다 조금 크다 — 점이 원 밖으로 나가야 "얹혀 있다"로
  /// 읽히는데, 딱 맞는 상자 안에 가두면 잘려서 그냥 원의 일부가 된다
  Widget _avatarWithStatus(BuildContext context, PacemateStatus? status) {
    final roles = GoRoles.of(context);
    return SizedBox(
      width: _avatar + 3,
      height: _avatar + 3,
      child: Stack(children: [
        // 사진만 따로 눌린다 — 카드를 누르면 상세, 얼굴을 누르면 얼굴.
        // 목록의 52pt 원에서는 누구인지 알아보기 어려울 때가 있다
        AvatarPhotoTap(
          photoUrl: user['photoUrl'] as String?,
          name: name,
          child: GoAvatar(size: _avatar, photoUrl: user['photoUrl'] as String?),
        ),
        // 최근 기록이 없으면 점을 찍지 않는다. 회색 점은 상태가 아니라
        // 고장으로 읽히고, 목록에 아무 뜻 없는 동그라미만 늘어난다
        if (status != null && status.tone != PacemateTone.quiet)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              key: dotKey,
              width: _dot,
              height: _dot,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: status.tone == PacemateTone.active
                    ? roles.success.fg
                    : roles.textDisabled,
                // 카드 면과 같은 색 링 — 점과 아바타 사이에 틈을 만들어
                // 점이 아바타 '위에' 떠 있는 것으로 보이게 한다
                border: Border.all(color: roles.surfaceHigh, width: 2.5),
              ),
            ),
          ),
      ]),
    );
  }
}
