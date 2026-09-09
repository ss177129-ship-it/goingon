import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// 원형 아바타 — 프로필/친구 목록/'우리' 탭/GO? 시트에서 반복되는 조각.
///
/// **기본 프로필은 실루엣이다**(2026-09-08). 전에는 이름 첫 글자를 원 안에
/// 띄웠는데(`InitialAvatar`), 글자가 원 한가운데 덩그러니 놓여 있는 모양이
/// 사진과 나란히 섰을 때 어색했고, 이름이 비면 또 다른 아이콘으로 갈라졌다.
/// 이제 사진이 없으면 누구든 같은 실루엣이다 — 이름 유무로 갈라지지 않는다.
///
/// 실루엣은 에셋이 아니라 [CustomPainter]로 그린다. 크기(24~96)마다 선명하고,
/// 색을 [GoRoles] 역할색에서 그대로 받는다(에셋이면 테마마다 파일이 필요).
///
/// **굵은 색 테두리는 없다**(2026-09-08). 역할색([roleColor] — 나/상대)은
/// 테두리가 아니라 **옅은 면(18%)**과 실루엣의 색으로 깔린다. 사진이 있으면
/// 면도 안 보이고 사진만 남는다.
///
/// **[roleColor]를 넘기지 않으면 브랜드 라임 기본 프로필**(2026-09-09) —
/// 워드마크의 라임 원색 면 위에 올리브 실루엣. 명부·목록·내 프로필이
/// 여기 해당한다. 관계색은 나와 상대를 **나란히 놓고 갈라야 하는** 화면
/// (로비·러닝·'우리')에서만 뜻이 있고, 목록에서는 색이 뜻을 잃는다.
///
/// [photoUrl]이 있으면 사진으로 채움. 사진은 언제든 실패할 수 있으므로
/// (지워진 파일, 비행기 모드, 낡은 주소) 로딩·실패 양쪽 모두 실루엣으로
/// 되돌아감 — 아바타 자리가 비거나 깨진 아이콘이 뜨는 화면은 만들지 않음.
class GoAvatar extends StatelessWidget {
  final double size;

  /// 역할색(나=self, 상대=partner). 옅은 면과 실루엣의 색.
  /// null이면 [GoRoles.avatarDefault] — 라임 면 + 올리브 실루엣
  final Color? roleColor;

  /// null이면 [roleColor]의 18% 면 (roleColor도 null이면 라임 원색 면)
  final Color? fill;
  final double borderWidth;
  final String? photoUrl;

  const GoAvatar({
    super.key,
    required this.size,
    this.roleColor,
    this.fill,
    this.borderWidth = 0,
    this.photoUrl,
  });

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    final role = roleColor;
    final base = GoRoles.of(context).avatarDefault;
    // 관계색이 오면 그 색의 옅은 면 + 55% 실루엣, 아니면 라임 원색 면 + 올리브
    final surface = fill ?? (role?.withValues(alpha: .18) ?? base.bg);
    final figure = role?.withValues(alpha: .55) ?? base.fg;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: surface,
        border: borderWidth > 0
            ? Border.all(color: role ?? base.fg, width: borderWidth)
            : null,
      ),
      // 테두리 두께만큼 안쪽으로 들어온 영역이 자식의 자리라, 원으로 자르면
      // 사진이 테두리를 덮지 않고 정확히 안쪽만 채움
      child: ClipOval(
        child: url == null || url.isEmpty
            ? _silhouette(figure)
            : CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                width: size,
                height: size,
                placeholder: (_, __) => _silhouette(figure),
                errorWidget: (_, __, ___) => _silhouette(figure),
              ),
      ),
    );
  }

  Widget _silhouette(Color figure) => CustomPaint(
        size: Size.square(size),
        painter: AvatarSilhouettePainter(color: figure),
      );
}

/// 머리(원) + 어깨(아래로 잘리는 타원) — 원 밖으로 흘러넘치는 어깨는
/// [GoAvatar]의 ClipOval이 잘라 준다. 색은 [GoAvatar]가 이미 정해서 넘기므로
/// (관계색 55% 또는 기본 프로필의 올리브) 여기서 알파를 다시 얹지 않는다.
class AvatarSilhouettePainter extends CustomPainter {
  final Color color;

  const AvatarSilhouettePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // 머리 — 중심에서 살짝 위. 반지름은 지름의 17%
    final headR = s * .17;
    final headC = Offset(s / 2, s * .40);
    canvas.drawCircle(headC, headR, paint);

    // 어깨 — 머리 아래에서 시작해 원 바깥까지 이어지는 타원의 윗부분.
    // 원의 아래쪽 곡선과 어깨 곡선이 비슷하게 휘어야 한 덩어리로 보인다
    final shoulders = Rect.fromCenter(
      center: Offset(s / 2, s * 1.0),
      width: s * .78,
      height: s * .76,
    );
    canvas.drawOval(shoulders, paint);
  }

  @override
  bool shouldRepaint(AvatarSilhouettePainter old) => old.color != color;
}
