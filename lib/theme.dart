import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// GoingOn 브랜드 컬러 — 프로토타입 v2와 동일
class GoColors {
  static const paper = Color(0xFFF0EAE0);
  static const canvas = Color(0xFFEBE4D6);
  static const lime = Color(0xFFC5E040);
  static const limeDark = Color(0xFF6A9810);
  static const coral = Color(0xFFF05840);
  static const coralDark = Color(0xFFB03020);
  static const ink = Color(0xFF1A1A16);
  static const amber = Color(0xFFD97706);
  static const resonance = Color(0xFFD4A84B);
  static const mid = Color(0xFF78746E);
  static const dim = Color(0xFFB0ACA6);
  static const line = Color(0x171A1A16); // ink 9% opacity
}

class GoTheme {
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: GoColors.paper,
      colorScheme: ColorScheme.fromSeed(
        seedColor: GoColors.lime,
        surface: GoColors.paper,
      ),
    );
    return base.copyWith(
      textTheme: GoogleFonts.notoSansKrTextTheme(base.textTheme).copyWith(
        // 브랜드 세리프(Instrument Serif 대응) — 숫자·타이틀용
        displayMedium: GoogleFonts.instrumentSerif(
          fontStyle: FontStyle.italic,
          color: GoColors.ink,
        ),
      ),
    );
  }

  /// 세리프 이탤릭 타이틀 (프로토타입의 Instrument Serif italic)
  static TextStyle serif(double size, {Color color = GoColors.ink}) =>
      GoogleFonts.instrumentSerif(
        fontSize: size,
        fontStyle: FontStyle.italic,
        color: color,
      );
}
