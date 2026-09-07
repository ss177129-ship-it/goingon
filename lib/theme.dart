import 'package:flutter/material.dart';

/// GoingOn 팔레트 — **값의 유일한 출처.** 화면·위젯은 이 클래스를 직접
/// 참조하지 않고 [GoRoles](역할 토큰)를 통해서만 색을 얻는다.
///
/// 규칙 (2026-09-08 컬러 토큰 시스템):
/// - 기본 팔레트 4색([paper]·[lime]·[coral]·[ink])은 바꾸지 않는다
/// - **paper 위에 lime·coral·white 글자 금지.** 글자용 코랄은 [coralText],
///   글자용 라임 계열은 [olive]·[pine]
/// - **coral 배경 위 white 글자는 굵은 16pt 이상만.** 본문 크기 white 금지
/// - **lime 원색은 ink 또는 pine 배경 위에서만.** paper 위에서는 [olive]
/// - 칩·배지의 면은 [coralTint]·[limeTint]·[pineTint], 글자는 그 앵커색
/// - 위젯 코드에 `Color(0x…)`를 쓰지 않는다. 새 값이 필요하면 여기에
class GoColors {
  // ── 기본 팔레트 (변경 금지) ──
  static const paper = Color(0xFFF0EAE0);
  static const lime = Color(0xFFC5E040);
  static const coral = Color(0xFFF05840);
  static const ink = Color(0xFF1A1A16);

  // ── 보조 컬러 ──
  /// 버튼·그래픽용 코랄
  static const coralComponent = Color(0xFFE04A34);

  /// 글자용 코랄(링크)
  static const coralText = Color(0xFFBD3722);

  /// 코랄의 다크 앵커 — 아웃라인·상태 칩 글자·상대
  static const rust = Color(0xFF8A3B1F);

  /// 딥 그린 — 완료 액션 면, 온라인 상태 글자
  static const pine = Color(0xFF1E5C4A);

  /// 라임의 다크 앵커 — 리워드 글자·나
  static const olive = Color(0xFF5C6D1D);

  /// 웜 그레이 — 보조 글자(단위·캡션·비활성)
  static const stone = Color(0xFF6B675C);

  static const coralTint = Color(0xFFFAD8D0);
  static const limeTint = Color(0xFFE8F0C4);
  static const pineTint = Color(0xFFD8E8E0);

  /// 흰 글자 — coral 면 위 굵은 큰 글자 전용
  static const white = Color(0xFFFFFFFF);

  // ── 면·선 (페이퍼 위의 계층) ──
  /// 카드·시트가 놓이는 면. 순백이 아니라 페이퍼 색상(hue 33°)을 유지한
  /// 채 밝기만 올린 값 — 따뜻한 종이 위의 순백은 차가운 구멍으로 읽힌다
  static const surface = Color(0xFFFDFAF5);

  /// 시트·다이얼로그처럼 위로 떠오르는 면. surface보다 한 단 밝다
  static const surfaceHigh = Color(0xFFFFFDF9);

  /// 뒤가 비쳐야 하는 면(탭바). surface 90%
  static const surfaceVeil = Color(0xE6FDFAF5);

  /// 그림자 색 — 종이의 색상을 따라간 따뜻한 갈색-검정
  static const shadow = Color(0xFF4A3A24);

  /// 면 안쪽의 헤어라인. ink 22%
  static const line = Color(0x381A1A16);

  /// 반드시 읽혀야 하는 구분선. ink 34%
  static const lineStrong = Color(0x571A1A16);

  /// 공명(두 사람의 발이 맞은 순간) — 제품 고유색. ink·canvas 위에서만
  static const resonance = Color(0xFFD4A84B);

  /// 러닝·로비 화면 바탕. 페이퍼보다 한 단 어둡다
  static const canvas = Color(0xFFEBE4D6);

  // ── 눌림 색 (손가락이 닿아 있는 동안만) ──
  static const inkPressed = Color(0xFF35342C);
  static const coralComponentPressed = Color(0xFFC53F2B);
  static const pinePressed = Color(0xFF174A3B);
  static const surfacePressed = Color(0xFFEDE7DE);
  static const pressOverlay = Color(0x141A1A16); // ink 8%
}

/// 면 + 글자(+테두리) 한 세트. 역할 하나가 곧 조합 하나다
class GoRole {
  const GoRole({
    required this.bg,
    required this.fg,
    this.border,
    required this.pressed,
  });

  final Color bg;
  final Color fg;
  final Color? border;

  /// 눌려 있는 동안의 면
  final Color pressed;
}

/// 역할 토큰. 화면·위젯은 **반드시 이 이름으로만** 색을 쓴다 —
/// `GoRoles.of(context).actionPrimary.bg`처럼.
///
/// 팔레트([GoColors])는 값이고 역할은 뜻이다. "코랄"이 아니라 "주 액션",
/// "올리브"가 아니라 "리워드 글자". 값이 바뀌어도 화면 코드는 그대로다.
class GoRoles extends ThemeExtension<GoRoles> {
  const GoRoles({
    required this.background,
    required this.canvas,
    required this.surface,
    required this.surfaceHigh,
    required this.surfaceVeil,
    required this.surfacePressed,
    required this.pressOverlay,
    required this.line,
    required this.lineStrong,
    required this.rule,
    required this.textPrimary,
    required this.textSecondary,
    required this.textOnDark,
    required this.link,
    required this.actionPrimary,
    required this.actionComplete,
    required this.actionSecondary,
    required this.statusRunning,
    required this.statusOnline,
    required this.reward,
    required this.dark,
    required this.self,
    required this.partner,
    required this.selfOnDark,
    required this.partnerOnDark,
    required this.attention,
    required this.resonance,
  });

  // 면·선
  /// 화면 바탕(paper)
  final Color background;

  /// 러닝·로비 바탕
  final Color canvas;
  final Color surface;
  final Color surfaceHigh;
  final Color surfaceVeil;
  final Color surfacePressed;

  /// 면이 없는 것이 눌렸을 때 얹는 잉크 8%
  final Color pressOverlay;
  final Color line;
  final Color lineStrong;

  /// 섹션 사이 1px — 잉크 100%
  final Color rule;

  // 글자
  final Color textPrimary;

  /// 단위·캡션·비활성
  final Color textSecondary;

  /// 잉크 면 위의 글자
  final Color textOnDark;
  final Color link;

  // 액션
  /// 러닝 시작/정지 등 주 액션. **글자는 굵게 16pt 이상**
  final GoRole actionPrimary;

  /// 저장·완료
  final GoRole actionComplete;

  /// 아웃라인 버튼
  final GoRole actionSecondary;

  // 상태 칩
  /// 뛰는 중
  final GoRole statusRunning;

  /// 온라인·GPS·완료
  final GoRole statusOnline;

  /// 코인·적립 전용. **리워드 외 사용 금지**
  final GoRole reward;

  /// 잉크 면(히어로 카드·선택 알약·세그먼트 활성)
  final GoRole dark;

  // 관계색 — 아바타 테두리·점. paper 위에서는 다크 앵커
  final Color self;
  final Color partner;

  /// ink·canvas 위에서만 쓰는 원색(히어로의 점, 공명 캔버스의 링)
  final Color selfOnDark;
  final Color partnerOnDark;

  /// 주의·경고 테두리와 아이콘 (연결 안내, 늦음, 미등록)
  final Color attention;

  /// 공명 골드 — 러닝 화면 전용
  final Color resonance;

  static const light = GoRoles(
    background: GoColors.paper,
    canvas: GoColors.canvas,
    surface: GoColors.surface,
    surfaceHigh: GoColors.surfaceHigh,
    surfaceVeil: GoColors.surfaceVeil,
    surfacePressed: GoColors.surfacePressed,
    pressOverlay: GoColors.pressOverlay,
    line: GoColors.line,
    lineStrong: GoColors.lineStrong,
    rule: GoColors.ink,
    textPrimary: GoColors.ink,
    textSecondary: GoColors.stone,
    textOnDark: GoColors.paper,
    link: GoColors.coralText,
    actionPrimary: GoRole(
      bg: GoColors.coralComponent,
      fg: GoColors.white,
      pressed: GoColors.coralComponentPressed,
    ),
    actionComplete: GoRole(
      bg: GoColors.pine,
      fg: GoColors.lime,
      pressed: GoColors.pinePressed,
    ),
    actionSecondary: GoRole(
      bg: Color(0x00000000),
      fg: GoColors.rust,
      border: GoColors.rust,
      pressed: GoColors.coralTint,
    ),
    statusRunning: GoRole(
      bg: GoColors.coralTint,
      fg: GoColors.rust,
      pressed: GoColors.coralTint,
    ),
    statusOnline: GoRole(
      bg: GoColors.pineTint,
      fg: GoColors.pine,
      pressed: GoColors.pineTint,
    ),
    reward: GoRole(
      bg: GoColors.limeTint,
      fg: GoColors.olive,
      pressed: GoColors.limeTint,
    ),
    dark: GoRole(
      bg: GoColors.ink,
      fg: GoColors.paper,
      pressed: GoColors.inkPressed,
    ),
    self: GoColors.olive,
    partner: GoColors.rust,
    selfOnDark: GoColors.lime,
    partnerOnDark: GoColors.coral,
    attention: GoColors.rust,
    resonance: GoColors.resonance,
  );

  static GoRoles of(BuildContext context) =>
      Theme.of(context).extension<GoRoles>() ?? light;

  @override
  GoRoles copyWith() => this;

  @override
  GoRoles lerp(ThemeExtension<GoRoles>? other, double t) => this;
}

/// 높이 3단계. 그림자는 **두 겹**이다 — 붙어 있는 접촉 그림자 하나와
/// 넓게 퍼지는 주변광 그림자 하나. 한 겹짜리 그림자는 스티커처럼 보인다.
///
/// 색은 [GoColors.shadow](따뜻한 갈색-검정). 알파가 낮아 페이퍼 위에서는
/// 카드 가장자리를 살짝 어둡게 만드는 정도로만 보이고, 그것이 곧 경계다
class GoShadow {
  /// 페이지에 놓인 카드·그룹
  static const card = [
    BoxShadow(color: Color(0x1A4A3A24), blurRadius: 3, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x144A3A24), blurRadius: 12, offset: Offset(0, 5)),
  ];

  /// 눌린 카드 — 그림자가 줄면 종이가 눌려 들어간 것처럼 보인다
  static const pressed = [
    BoxShadow(color: Color(0x0F4A3A24), blurRadius: 1, offset: Offset(0, 0.5)),
  ];

  /// 주 버튼처럼 눌러주길 바라는 것
  static const raised = [
    BoxShadow(color: Color(0x244A3A24), blurRadius: 4, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x1F4A3A24), blurRadius: 18, offset: Offset(0, 8)),
  ];

  /// 시트·다이얼로그·토스트 — 화면에서 확실히 떨어져 나온 것
  static const overlay = [
    BoxShadow(color: Color(0x1F4A3A24), blurRadius: 6, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x244A3A24), blurRadius: 32, offset: Offset(0, 12)),
  ];

  /// 탭바처럼 위로 그림자를 던지는 것
  static const bar = [
    BoxShadow(color: Color(0x144A3A24), blurRadius: 16, offset: Offset(0, -4)),
  ];

  /// 스위치 손잡이 — 트랙 위에 얹힌 작은 원. 잉크 25%, 1px 아래
  static const thumb = [
    BoxShadow(color: Color(0x401A1A16), blurRadius: 3, offset: Offset(0, 1)),
  ];
}

/// 상태 전환 시간. 눌림(즉시 / 90ms 복귀)은 [Pressable]이 갖고, 여기는
/// **값이 바뀐 뒤** 모양이 따라오는 시간이다. 곡선은 전부 easeOut
class GoMotion {
  /// 스위치 — 손잡이가 실제로 이동하므로 조금 길게
  static const toggle = Duration(milliseconds: 150);

  /// 체크·라디오·탭·세그먼트·칩 — 색·테두리만 바뀌는 것
  static const select = Duration(milliseconds: 120);

  static const curve = Curves.easeOut;
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
/// 색은 역할 그대로다 — 기본이 textPrimary, [secondary]만 textSecondary.
///
/// - **12px 미만은 없다.** 필요하면 [label]을 쓴다.
/// - **세리프 이탤릭은 숫자·라틴 문자·"GO?"·워드마크 "goingon"에만.** 한글은
///   전부 NotoSansKR. Instrument Serif에는 한글이 없어서 한글은 NotoSansKR로
///   넘어가는데, 그 위에 이탤릭이 걸리면 억지로 기울어진다. 제목·버튼 라벨·
///   본문은 산세리프. 숫자가 필요하면 [GoTheme.serif]를 직접 쓴다.
/// - 색을 바꿔야 하면 `.copyWith(color: ...)`, 단 [GoRoles]의 글자 역할만.
class GoText {
  /// 화면 제목 (2026-09-07 산세리프로)
  static const title = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: GoColors.ink,
  );

  /// 카드 제목·이름 (2026-09-07 산세리프로). 큰 숫자는 [GoTheme.serif]
  static const heading = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: GoColors.ink,
  );

  /// 본문
  static const body = TextStyle(
    fontSize: 15,
    height: 1.5,
    color: GoColors.ink,
  );

  /// 보조 설명(textSecondary). 흰 카드 안이든 페이퍼 위든 같은 스타일
  static const secondary = TextStyle(
    fontSize: 13,
    height: 1.45,
    color: GoColors.stone,
  );

  /// 섹션 라벨·스탯 라벨. 하나뿐이다 — 9/10/11px 변형을 만들지 말 것
  static const label = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: .6,
    color: GoColors.ink,
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
      scaffoldBackgroundColor: GoRoles.light.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: GoColors.coralComponent,
        surface: GoColors.paper,
      ),
      extensions: const [GoRoles.light],
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
          backgroundColor: GoRoles.light.actionPrimary.bg,
          foregroundColor: GoRoles.light.actionPrimary.fg,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: buttonShape,
          side: BorderSide(
              color: GoRoles.light.actionSecondary.border!, width: 1.5),
          textStyle: GoText.button,
          foregroundColor: GoRoles.light.actionSecondary.fg,
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

  /// 세리프 이탤릭 — **숫자·라틴 문자·"GO?"·워드마크 전용.** 한글 문자열에
  /// 쓰지 말 것(2026-09-07 규칙). 한글 제목은 [GoText.title]/[GoText.heading].
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
