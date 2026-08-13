import 'package:flutter/material.dart';

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
  /// pubspec.yaml의 fonts: 선언과 이름이 정확히 일치해야 함.
  /// 예전에는 google_fonts로 런타임에 내려받았는데, 네트워크가 없으면
  /// 시스템 기본 폰트로 폴백돼 첫인상이 무너지고 러닝 중(지하·산길)에도
  /// 같은 일이 생겨서 번들로 바꿈
  static const _serifFamily = 'InstrumentSerif';
  static const _sansFamily = 'NotoSansKR';

  /// 폰트에 없는 글리프를 어디로 넘길지. 순서가 곧 우선순위임.
  ///
  /// **Instrument Serif에는 한글 글리프가 없다.** 그래서 세리프 타이틀에
  /// 한글이 섞이면(내 이름, 아바타 이니셜, "함께 달리고 싶은 사람이
  /// 있나요?") 반드시 NotoSansKR로 넘어가야 하고, 이 연결이 없으면 한글이
  /// 전부 ?(두부)로 깨진다. CLAUDE.md에 적힌 이모지 깨짐도 같은 원인이라,
  /// 이모지 폰트도 사슬 끝에 명시해 둠
  static const _serifFallback = [_sansFamily, 'Apple Color Emoji'];
  static const _sansFallback = ['Apple Color Emoji'];

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: _sansFamily,
      fontFamilyFallback: _sansFallback,
      scaffoldBackgroundColor: GoColors.paper,
      colorScheme: ColorScheme.fromSeed(
        seedColor: GoColors.lime,
        surface: GoColors.paper,
      ),
    );
    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        // 브랜드 세리프 — 숫자·타이틀용
        displayMedium: serif(base.textTheme.displayMedium?.fontSize ?? 45),
      ),
    );
  }

  /// 세리프 이탤릭 타이틀 (프로토타입의 Instrument Serif italic)
  static TextStyle serif(double size, {Color color = GoColors.ink}) =>
      TextStyle(
        fontFamily: _serifFamily,
        fontFamilyFallback: _serifFallback,
        fontSize: size,
        fontStyle: FontStyle.italic,
        color: color,
      );
}
