import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import 'pressable.dart';

/// 프로필 사진을 눌러 크게 보는 것 — 홈 카드와 상세 카드의 아바타.
///
/// **크게'만' 본다.** 전체 화면 뷰어도, 확대·회전 제스처도 아니다. 목록의
/// 52pt 원에서는 누구인지 알아보기 어려울 때가 있고, 필요한 것은 얼굴을
/// 한 번 확인하는 것뿐이다. 화면을 통째로 덮으면 되돌아오는 길이 생기고
/// (닫기 버튼·스와이프) 사진 한 장을 보는 일이 화면 전환이 된다.
///
/// 그래서 크기를 화면 폭의 62%, 최대 260pt로 묶는다. 큰 기기에서 사진만
/// 계속 커지면 '카드'가 아니라 '뷰어'가 된다.
///
/// **사진이 없으면 아무 일도 일어나지 않는다.** 기본 실루엣은 확대해도
/// 볼 것이 없고, 눌리는데 아무 반응이 없는 것보다 애초에 안 눌리는 편이
/// 정직하다 — [AvatarPhotoTap]이 photoUrl이 빌 때 [Pressable]을 아예
/// 씌우지 않는다.
class AvatarPhotoTap extends StatelessWidget {
  const AvatarPhotoTap({
    super.key,
    required this.photoUrl,
    required this.child,
    this.name,
  });

  final String? photoUrl;
  final Widget child;

  /// 확대 카드 아래에 놓는 이름. 사진만 떠 있으면 누구인지 다시 묻게 된다
  final String? name;

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    if (url == null || url.isEmpty) return child;
    return Pressable(
      // 아바타는 이미 원이라 더 줄이면 눌린 게 아니라 튄 것처럼 보인다
      scale: 0.94,
      onTap: () => showAvatarPhoto(context, url, name: name),
      child: child,
    );
  }
}

/// 화면 폭에 비례하되 이 이상으로는 커지지 않는다
const double _kMaxPhoto = 260;

Future<void> showAvatarPhoto(BuildContext context, String url,
    {String? name}) {
  // 어둡게 덮는 막에는 따로 역할 토큰이 없다. 팔레트를 직접 참조하지 않기
  // 위해 잉크 글자색(=ink)에서 꺼내 쓴다
  final scrim = GoRoles.of(context).textPrimary.withValues(alpha: .62);
  return showDialog<void>(
    context: context,
    // 사진 한 장을 보는 일에 닫기 버튼까지 두지 않는다 — 아무 데나 누르면
    // 닫힌다. 그래서 barrier 자체가 닫기 표적이다
    barrierDismissible: true,
    barrierColor: scrim,
    builder: (ctx) {
      final roles = GoRoles.of(ctx);
      final size =
          (MediaQuery.of(ctx).size.width * .62).clamp(180.0, _kMaxPhoto);
      return Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(GoSpace.xl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ClipOval(
            child: SizedBox(
              width: size,
              height: size,
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                // 이미 목록에서 받아 둔 사진이라 대개 즉시 뜬다. 그래도
                // 실패할 수 있으므로(지워진 파일·낡은 주소) 빈 원을 남기지
                // 않고 옅은 면으로 자리를 지킨다
                placeholder: (_, __) => ColoredBox(color: roles.line),
                errorWidget: (_, __, ___) => ColoredBox(color: roles.line),
              ),
            ),
          ),
          if (name != null && name.isNotEmpty) ...[
            const SizedBox(height: GoSpace.l),
            Text(name,
                style: GoText.heading.copyWith(color: roles.textOnDark)),
          ],
        ]),
      );
    },
  );
}
