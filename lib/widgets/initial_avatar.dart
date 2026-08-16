import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// 원 + 테두리 + 이름 첫 글자 — 프로필/친구 목록/'우리' 탭에서 반복되는 아바타.
/// letter가 비어 있고 emptyIcon이 주어지면 아이콘으로 대체함 (내 프로필 카드용).
///
/// [photoUrl]이 있으면 사진으로 채움. 사진은 언제든 실패할 수 있으므로
/// (지워진 파일, 비행기 모드, 낡은 주소) 로딩·실패 양쪽 모두 첫 글자로 되돌아감 —
/// 아바타 자리가 비거나 깨진 아이콘이 뜨는 화면은 만들지 않음.
class InitialAvatar extends StatelessWidget {
  final String letter;
  final double size;
  final double fontSize;
  final Color borderColor;
  final Color fill;
  final double borderWidth;
  final IconData? emptyIcon;
  final String? photoUrl;

  const InitialAvatar({
    super.key,
    required this.letter,
    required this.size,
    required this.fontSize,
    required this.borderColor,
    this.fill = Colors.white,
    this.borderWidth = 2,
    this.emptyIcon,
    this.photoUrl,
  });

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      // 테두리 두께만큼 안쪽으로 들어온 영역이 자식의 자리라, 원으로 자르면
      // 사진이 테두리를 덮지 않고 정확히 안쪽만 채움
      child: ClipOval(
        child: url == null || url.isEmpty
            ? _fallback()
            : CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                width: size,
                height: size,
                placeholder: (_, __) => _fallback(),
                errorWidget: (_, __, ___) => _fallback(),
              ),
      ),
    );
  }

  Widget _fallback() {
    final showEmptyIcon = letter.isEmpty && emptyIcon != null;
    return Center(
      child: showEmptyIcon
          ? Icon(emptyIcon, size: size * .43, color: borderColor)
          : Text(letter, style: GoTheme.serif(fontSize)),
    );
  }
}
