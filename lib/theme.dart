import 'package:flutter/material.dart';

/// GoingOn 색 토큰.
///
/// 규칙 (2026-09-07):
/// - 글자에 쓸 수 있는 색은 [ink]·[mid]·[coralDark]·[limeDark]·[amberDark]뿐.
/// - [dim]·[line]은 선·구분·비활성·플레이스홀더용. **글자에 쓰지 말 것** —
///   흰 배경에서 2.3:1, 페이퍼에서 1.9:1이라 어떤 크기에서도 읽히지 않는다.
/// - [lime]·[coral]·[amber]는 면·점·강조 배경용. 글자로 쓰면 페이퍼 위에서
///   라임 1.2:1, 코랄 2.9:1이라 안 보인다. 글자가 필요하면 *Dark 쪽을 쓴다.
/// - 틴트 배경(라임 10%, 코랄 7% 등)은 쓰지 않는다. "다른 카드"는 테두리
///   색(2px)이나 왼쪽 세로 바(4px)로 말한다. 틴트는 페이퍼 위에서 사라진다.
/// - 값은 판단이므로 바꿀 수 있지만, 바꾼다면 **여기서만** 바꾼다.
class GoColors {
  static const paper = Color(0xFFF0EAE0);
  static const canvas = Color(0xFFEBE4D6);
  static const lime = Color(0xFFC5E040);

  /// 라임 계열 글자·테두리. #6A9810(흰 3.4:1)에서 내렸다 —
  /// 흰 5.8:1, 페이퍼 4.9:1
  static const limeDark = Color(0xFF48700A);

  static const coral = Color(0xFFF05840);

  /// 흰 6.4:1, 페이퍼 5.4:1 — 그대로
  static const coralDark = Color(0xFFB03020);

  static const ink = Color(0xFF1A1A16);
  static const amber = Color(0xFFD97706);

  /// 앰버 계열 글자. [amber]는 흰 3.2:1이라 30px 이상 큰 숫자에만 쓴다
  static const amberDark = Color(0xFF9A5200);

  static const resonance = Color(0xFFD4A84B);

  /// 보조 글자. #78746E(페이퍼 3.9:1)에서 내렸다 — 흰 6.8:1, 페이퍼 5.7:1.
  /// 이제 페이퍼 위에 직접 놓아도 된다
  static const mid = Color(0xFF5E5A54);

  /// 선·비활성·플레이스홀더 전용. 글자 금지
  static const dim = Color(0xFFB0ACA6);

  static const line = Color(0x291A1A16); // ink 16% — 페이퍼 위에서 보이는 최소치

  /// 섹션 사이 1px 구분선. 신문처럼 잉크 100%. 카드 테두리엔 쓰지 않는다
  static const rule = ink;
}

/// 모서리 3단계. 이 밖의 값(14·18·20·22)은 쓰지 않는다
class GoRadius {
  static const sm = 12.0; // 칩·작은 요소
  static const md = 16.0; // 버튼·카드
  static const lg = 24.0; // 시트
}

/// 선 굵기 3단계
class GoStroke {
  static const rule = 1.0;   // 섹션 구분선 (GoColors.rule)
  static const card = 1.5;   // 카드 테두리 (GoColors.line)
  static const accent = 2.0; // 강조 카드 테두리 (coral / lime)
}

/// 간격. 화면 좌우 여백은 [screen], 시트 안은 [sheet]
class GoSpace {
  static const xs = 4.0;
  static const s = 8.0;
  static const m = 12.0;
  static const l = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const screen = 24.0;
  static const sheet = 28.0;
  static const card = 16.0;    // 카드 안쪽 패딩
  static const hero = 20.0;    // 히어로 카드 안쪽 패딩
  static const section = 24.0; // 섹션 사이
  static const gutter = 12.0;  // 한 줄에 카드 여럿일 때 사이
  static const sheetBottom = 40.0; // 시트 하단(홈 인디케이터 위)
}

/// 텍스트 스타일 7개. 화면에서 fontSize·color를 직접 적지 말고 여기서 고른다.
///
/// - **12px 미만은 없다.** 필요하면 [label]을 쓴다.
/// - 세리프(이탤릭)는 [title]·[heading]·"GO?"·숫자에만. Instrument Serif에는
///   한글이 없어서 한글은 NotoSansKR로 넘어가는데, 그 위에 이탤릭이 걸리면
///   억지로 기울어진다. 버튼 라벨·본문은 산세리프.
/// - 색을 바꿔야 하면 `.copyWith(color: ...)`, 단 [GoColors]의 글자 허용 색만.
class GoText {
  /// 화면 제목
  static final title = GoTheme.serif(28);

  /// 카드 제목·이름·큰 숫자
  static final heading = GoTheme.serif(22);

  /// 본문
  static const body = TextStyle(
    fontSize: 15,
    height: 1.5,
    color: GoColors.ink,
  );

  /// 보조 설명. 흰 카드 안이든 페이퍼 위든 같은 스타일
  static const secondary = TextStyle(
    fontSize: 13,
    height: 1.45,
    color: GoColors.mid,
  );

  /// 섹션 라벨·스탯 라벨. 하나뿐이다 — 9/10/11px 변형을 만들지 말 것
  static const label = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: .6,
    color: GoColors.mid,
  );

  /// 버튼 라벨(큰 버튼 52pt)
  static const button = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: GoColors.ink,
  );

  /// 버튼 라벨(카드·행 안의 44pt 버튼)
  static const buttonSmall = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: GoColors.ink,
  );
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
  /// 전부 ?(두부)로 깨진다. 이 사슬은 건드리지 않았다 (CLAUDE.md 참조)
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

    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(GoRadius.md),
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        // 브랜드 세리프 — 숫자·타이틀용 (기존 유지)
        displayMedium: serif(base.textTheme.displayMedium?.fontSize ?? 45),
        headlineMedium: GoText.title,
        titleLarge: GoText.heading,
        bodyLarge: GoText.body,
        bodyMedium: GoText.body,
        bodySmall: GoText.secondary,
        labelLarge: GoText.button,
        labelMedium: GoText.label,
      ),
      // 아이콘 기본색. 화면에서 dim을 넘기던 곳은 그 지정을 지우면 이 값을 받는다
      iconTheme: const IconThemeData(color: GoColors.ink),

      // 버튼 기본값. 화면이 padding·shape를 직접 넘기면 그쪽이 이기지만,
      // minimumSize는 대개 안 넘기므로 **최소 높이만큼은 앱 전체에 걸린다.**
      // 지금 38~42pt로 만들어진 수락/거절/GO? 버튼이 이 한 줄로 44pt 이상이 된다
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: buttonShape,
          textStyle: GoText.button,
          foregroundColor: GoColors.ink,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: buttonShape,
          side: const BorderSide(color: GoColors.line, width: 1.5),
          textStyle: GoText.button,
          foregroundColor: GoColors.ink,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          textStyle: GoText.buttonSmall,
          foregroundColor: GoColors.ink,
        ),
      ),
    );
  }

  /// 세리프 타이틀 (프로토타입의 Instrument Serif italic).
  ///
  /// 기존 호출부(`GoTheme.serif(22)`, `serif(19, color: ...)`)는 그대로 동작한다.
  /// [italic]을 false로 주면 기울임 없이 세리프만 쓴다 — 한글이 많은 제목에서
  /// 억지 이탤릭이 거슬리면 이쪽. 스크린샷으로 확인한 뒤 기본값을 정할 것
  static TextStyle serif(
    double size, {
    Color color = GoColors.ink,
    bool italic = true,
  }) =>
      TextStyle(
        fontFamily: _serifFamily,
        fontFamilyFallback: _serifFallback,
        fontSize: size,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        color: color,
      );
}
