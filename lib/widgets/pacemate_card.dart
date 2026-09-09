import 'package:flutter/material.dart';

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

  /// 테스트에서 시간을 고정하기 위한 구멍
  final DateTime? now;

  static const _avatar = 52.0;
  static const _dot = 14.0;

  /// 상태 점은 있을 때와 없을 때가 곧 뜻이라, 테스트가 정확히 집을 수
  /// 있어야 한다 — Stack 안 형제라 자식 관계로는 찾아지지 않는다
  static const dotKey = ValueKey('pacemate-status-dot');

  @override
  Widget build(BuildContext context) {
    final roles = GoRoles.of(context);
    final status = PacemateStatus.of(user, now ?? DateTime.now());
    return GoCard(
      margin: const EdgeInsets.fromLTRB(22, 0, 22, 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      onTap: onOpen,
      child: Row(children: [
        _avatarWithStatus(context, status),
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
                if (status.label.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(status.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          color: status.tone == PacemateTone.active
                              ? roles.success.fg
                              : roles.textSecondary)),
                ],
              ]),
        ),
        const SizedBox(width: GoSpace.s),
        GoButton('GO?',
            kind: GoButtonKind.primary,
            size: GoButtonSize.md,
            serifLabel: true,
            loading: goLoading,
            enabled: goEnabled,
            onTap: onGo),
      ]),
    );
  }

  /// 사진 + 오른쪽 아래로 걸쳐 나온 상태 점.
  ///
  /// [Stack]이 아바타보다 조금 크다 — 점이 원 밖으로 나가야 "얹혀 있다"로
  /// 읽히는데, 딱 맞는 상자 안에 가두면 잘려서 그냥 원의 일부가 된다
  Widget _avatarWithStatus(BuildContext context, PacemateStatus status) {
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
        if (status.tone != PacemateTone.quiet)
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
