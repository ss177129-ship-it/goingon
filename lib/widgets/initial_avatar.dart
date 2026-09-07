import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// 원 + 이름 첫 글자 — 프로필/친구 목록/'우리' 탭에서 반복되는 아바타.
/// letter가 비어 있고 emptyIcon이 주어지면 아이콘으로 대체함 (내 프로필 카드용).
///
/// **굵은 색 테두리는 없다**(2026-09-08). 역할색([borderColor] — 나/상대)은
/// 테두리가 아니라 **옅은 면(18%)**으로 깔린다. 사진이 있으면 면도 안 보이고
/// 사진만 남는다. 색 링은 화면마다 굵은 선이 늘어서 지저분했다.
///
/// [photoUrl]이 있으면 사진으로 채움. 사진은 언제든 실패할 수 있으므로
/// (지워진 파일, 비행기 모드, 낡은 주소) 로딩·실패 양쪽 모두 첫 글자로 되돌아감 —
/// 아바타 자리가 비거나 깨진 아이콘이 뜨는 화면은 만들지 않음.
class InitialAvatar extends StatelessWidget {
  final String letter;
  final double size;
  final double fontSize;

  /// 역할색(나=positive, 상대=partner, 중립=line). 이름은 옛것이지만 이제
  /// 테두리가 아니라 옅은 면과 빈 아이콘의 색으로 쓰인다
  final Color borderColor;
  /// null이면 [GoRoles.surface]
  final Color? fill;
  final double borderWidth;
  final IconData? emptyIcon;
  final String? photoUrl;

  const InitialAvatar({
    super.key,
    required this.letter,
    required this.size,
    required this.fontSize,
    required this.borderColor,
    this.fill,
    this.borderWidth = 0,
    this.emptyIcon,
    this.photoUrl,
  });

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    final roles = GoRoles.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill ?? borderColor.withValues(alpha: .18),
        border: borderWidth > 0
            ? Border.all(color: borderColor, width: borderWidth)
            : null,
      ),
      // 테두리 두께만큼 안쪽으로 들어온 영역이 자식의 자리라, 원으로 자르면
      // 사진이 테두리를 덮지 않고 정확히 안쪽만 채움
      child: ClipOval(
        child: url == null || url.isEmpty
            ? _fallback(roles)
            : CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                width: size,
                height: size,
                placeholder: (_, __) => _fallback(roles),
                errorWidget: (_, __, ___) => _fallback(roles),
              ),
      ),
    );
  }

  Widget _fallback(GoRoles roles) {
    final showEmptyIcon = letter.isEmpty && emptyIcon != null;
    return Center(
      child: showEmptyIcon
          ? Icon(emptyIcon, size: size * .43, color: borderColor)
          // 이니셜은 한글이 대부분이라 산세리프 (세리프 이탤릭은 숫자·라틴 전용)
          : Text(letter,
              style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                  color: roles.textPrimary)),
    );
  }
}
