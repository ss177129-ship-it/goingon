import 'package:flutter/material.dart';

import '../theme.dart';

/// 원 + 테두리 + 이름 첫 글자 — 프로필/친구 목록/'우리' 탭에서 반복되는 아바타.
/// letter가 비어 있고 emptyIcon이 주어지면 아이콘으로 대체함 (내 프로필 카드용).
class InitialAvatar extends StatelessWidget {
  final String letter;
  final double size;
  final double fontSize;
  final Color borderColor;
  final Color fill;
  final double borderWidth;
  final IconData? emptyIcon;

  const InitialAvatar({
    super.key,
    required this.letter,
    required this.size,
    required this.fontSize,
    required this.borderColor,
    this.fill = Colors.white,
    this.borderWidth = 2,
    this.emptyIcon,
  });

  @override
  Widget build(BuildContext context) {
    final showEmptyIcon = letter.isEmpty && emptyIcon != null;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      child: Center(
        child: showEmptyIcon
            ? Icon(emptyIcon, size: size * .43, color: borderColor)
            : Text(letter, style: GoTheme.serif(fontSize)),
      ),
    );
  }
}
