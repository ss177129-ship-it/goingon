import 'package:flutter/material.dart';

/// GoingOn 팔레트 — **값의 유일한 출처.** 화면·위젯은 이 클래스를 직접
/// 참조하지 않고 [GoRoles](역할 토큰)를 통해서만 색을 얻는다.
///
/// ## 세 묶음 (2026-09-09, 보조색 전면 재편)
///
/// 1. **브랜드** — [paper]·[lime]·[coral]·[ink]. 아이콘의 네 색. 바꾸지 않는다.
///    정체성과 주 액션에만 쓴다.
/// 2. **중성(neutral)** — 페이퍼의 색상(hue 33°)을 유지한 웜 그레이 램프.
///    배경·면·선·보조 글자·비활성·보조 버튼은 **전부 여기서** 나온다.
///    보조 행동에 색을 쓰지 않는다.
/// 3. **시맨틱** — success·warning·error·info. 뜻이 고정된 네 색.
///    상태에만 쓰고, 브랜드와 겹치지 않는다. 각각 글자용([successText] 등,
///    밝은 바탕 위 4.5:1)·면용(옅은 [successSoft], 진한 [successSolid]) 세 단계.
///
/// 전에는 보조색이 코랄 변주 5개 + 초록 1개였고 한 색이 여러 뜻을 겸했다
/// (코랄 = 주 버튼·링크·상대·경고, 초록 = 완료·온라인·나). 이제 화면에
/// 색이 있으면 "여기 눌러"(브랜드) 아니면 "상태가 이렇다"(시맨틱) 둘 중 하나다.
///
/// 규칙:
/// - 밝은 바탕(paper·surface·canvas) 위의 색 글자는 4.5:1 이상.
///   원색 [lime]·[coral]은 글자로 쓰지 않는다 — 나/상대 글자는 [selfText]·
///   [partnerText]
/// - 코랄 면 위 흰 글자는 굵은 16pt 이상만(3.9:1). 시맨틱 solid 면 위
///   흰 글자는 본문 크기도 된다(5:1+)
/// - **코랄은 빨강 계열이라 error와 이웃한다.** error는 코랄보다 차갑고
///   어두운 값이고, 상태는 색만으로 전하지 않는다(아이콘·문구 동반)
/// - 위젯 코드에 `Color(0x…)`를 쓰지 않는다. 새 값이 필요하면 여기에.
///   값은 `test/theme_roles_test.dart`가 대비를 검사한다
class GoColors {
  // ── 브랜드 (변경 금지) ──
  static const paper = Color(0xFFF0EAE0);
  static const lime = Color(0xFFC5E040);
  static const coral = Color(0xFFF05840);
  static const ink = Color(0xFF1A1A16);

  // ── 브랜드 파생 (컴포넌트용) ──
  /// 주 버튼용 코랄 — 흰 굵은 글자 3.9:1
  static const coralComponent = Color(0xFFE04A34);
  static const coralComponentPressed = Color(0xFFC53F2B);

  /// 원색 코랄 면이 눌렸을 때 (뛰는 중 칩)
  static const coralPressed = Color(0xFFE04A34);
  static const limePressed = Color(0xFFAFC935);
  static const inkPressed = Color(0xFF35342C);

  /// 상대(partner) 글자·아이콘 — 코랄에서 파생, 캔버스 위 4.5:1(페이퍼 4.8:1).
  /// 밝은 바탕 셋 중 가장 어두운 [canvas]가 기준이다 — 페이퍼만 맞추면 카드 위에서 모자란다.
  /// [errorText]와 이웃한 색이므로 상태 표시에는 쓰지 않는다
  static const partnerText = Color(0xFFC03019);

  /// 나(self) 글자·아이콘 — 라임에서 파생한 올리브, 페이퍼 위 5.3:1.
  /// [successText](초록, hue 140°)와 다른 색상(hue 75°)
  static const selfText = Color(0xFF4E6800);

  /// 흰 글자 — 코랄·시맨틱 solid 면 위
  static const white = Color(0xFFFFFFFF);

  // ── 중성 램프 (웜 그레이, hue 33~39°) ──
  /// 카드·시트가 놓이는 면. 순백이 아니라 페이퍼 색상을 유지한 채 밝기만
  /// 올린 값 — 따뜻한 종이 위의 순백은 차가운 구멍으로 읽힌다
  static const surface = Color(0xFFFDFAF5);

  /// 시트·다이얼로그처럼 위로 떠오르는 면. surface보다 한 단 밝다
  static const surfaceHigh = Color(0xFFFFFDF9);

  /// 뒤가 비쳐야 하는 면(탭바). surface 90%
  static const surfaceVeil = Color(0xE6FDFAF5);

  /// 러닝·로비 화면 바탕. 페이퍼보다 한 단 어둡다
  static const canvas = Color(0xFFEBE4D6);
  static const surfacePressed = Color(0xFFEDE7DE);

  static const neutral100 = Color(0xFFF6F1E8);
  static const neutral200 = Color(0xFFE8E1D4);
  static const neutral300 = Color(0xFFD4CBBC);

  /// 아웃라인 버튼·입력창 테두리. 페이퍼 위 2:1 — 선으로는 충분하다
  static const neutral400 = Color(0xFFB0A697);

  /// 비활성 글자·플레이스홀더 (페이퍼 위 3.4:1 — 본문으로 쓰지 않는다)
  static const neutral500 = Color(0xFF857C6F);

  /// 보조 글자 — 페이퍼 위 5.7:1
  static const neutral600 = Color(0xFF5E5A54);
  static const neutral700 = Color(0xFF45413A);
  static const neutral800 = Color(0xFF2E2B26);

  /// 그림자 색 — 종이의 색상을 따라간 따뜻한 갈색-검정
  static const shadow = Color(0xFF4A3A24);

  /// 면 안쪽의 헤어라인. ink 22% (사진 위에서도 보이도록 알파)
  static const line = Color(0x381A1A16);

  /// 반드시 읽혀야 하는 구분선. ink 34%
  static const lineStrong = Color(0x571A1A16);

  /// 면이 없는 것이 눌렸을 때 얹는 잉크 8%
  static const pressOverlay = Color(0x141A1A16);

  /// 선택된 자리에 드리우는 잉크 그림자(탭바 알약). 12% / 눌림 18%
  static const inkVeil = Color(0x1F1A1A16);
  static const inkVeilPressed = Color(0x2E1A1A16);

  // ── 시맨틱 ──
  /// 완료·온라인·GPS 잡힘·성공 토스트
  static const successText = Color(0xFF1A6B34); // 페이퍼 위 5.5:1
  static const successSolid = Color(0xFF1E7A3C); // 흰 글자 5.4:1
  static const successSolidPressed = Color(0xFF186532);
  static const successSoft = Color(0xFFDCEFE0);
  static const successSoftPressed = Color(0xFFCDE6D3);

  /// 연결 불안정·늦음·미등록 — 아직 실패는 아니지만 알아야 하는 것
  static const warningText = Color(0xFF9A4D00); // 페이퍼 위 5.1:1
  static const warningSolid = Color(0xFFB45309); // 흰 글자 5.0:1
  static const warningSolidPressed = Color(0xFF9A4708);
  static const warningSoft = Color(0xFFFBE7C6);
  static const warningSoftPressed = Color(0xFFF3DAB0);

  /// 실패 토스트·삭제·차단·탈퇴·유효성 오류
  static const errorText = Color(0xFFB42323); // 페이퍼 위 5.5:1
  static const errorSolid = Color(0xFFC42B2B); // 흰 글자 5.6:1
  static const errorSolidPressed = Color(0xFFA82424);
  static const errorSoft = Color(0xFFF8DAD6);
  static const errorSoftPressed = Color(0xFFF0C9C3);

  /// 안내·중립 알림. 지금 앱에는 거의 없다 — 자리만 둔다
  static const infoText = Color(0xFF1F55C4); // 페이퍼 위 5.6:1
  static const infoSolid = Color(0xFF2563EB); // 흰 글자 5.2:1
  static const infoSolidPressed = Color(0xFF1E52C7);
  static const infoSoft = Color(0xFFDAE4F8);
  static const infoSoftPressed = Color(0xFFC8D6F2);

  // ── 제품 고유 ──
  /// 공명(두 사람의 발이 맞은 순간). ink·canvas 위에서만
  static const resonance = Color(0xFFD4A84B);
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
/// "초록"이 아니라 "성공". 값이 바뀌어도 화면 코드는 그대로다.
///
/// ## Color Usage Rules (2026-09-09)
///
/// 색은 장식이 아니라 **정보 위계·행동의 중요도·상태**를 전하는 수단이다.
/// 화면에 색이 있으면 그건 "여기 눌러" 아니면 "상태가 이렇다" 둘 중 하나다.
///
/// 1. **Primary**([actionPrimary], 브랜드 코랄) — 가장 중요하거나 가장 먼저
///    해야 하는 행동. 화면당 하나. 현재 선택된 탭바 항목은 주 색이 아니라
///    [selection](잉크 그림자 알약)이다 — 탭바는 모든 화면에 붙어 있어
///    여기에 주 색을 쓰면 화면의 CTA와 매번 경쟁한다
/// 2. **Confirm**([actionComplete], 잉크 면) — 저장·완료·확정. "성공"이 아니라
///    "확정"이므로 시맨틱 초록이 아니라 잉크다
/// 3. **Secondary / Tertiary**([actionSecondary]·text 버튼) — 보조 행동,
///    취소·닫기. **색을 쓰지 않는다**(중성). 덜 중요한 역할이지 덜 보이는
///    색이 아니다 — 대비는 primary와 같다. 파괴적 행동(지우기·차단·탈퇴)만
///    [error]
/// 4. **Status**([success]·[warning]·[error]·[info]) — 상태에만. 글자·아이콘·
///    테두리는 `.fg`, 옅은 면은 `.bg`. 진한 면이 필요한 칩은 [statusOnline]
/// 5. **Relation**([self]·[partner]) — 나와 상대. 브랜드 라임·코랄에서 파생한
///    읽히는 색이고 시맨틱과 **뜻이 다르다**(나 ≠ 성공, 상대 ≠ 오류)
/// 6. **Visibility First** — 모든 색 선택의 첫 기준은 가시성. 밝은 바탕 위
///    글자는 4.5:1, 12px 아래로 내려가지 않는다
/// 7. **Do Not Rely on Color Alone** — 선택·오류·성공·중요도를 색 하나로
///    전하지 않는다. 아이콘·인디케이터·형태·텍스트·모션을 함께 쓴다.
///    코랄(브랜드)과 error가 이웃한 색이라 특히 그렇다
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
    required this.textDisabled,
    required this.textOnDark,
    required this.link,
    required this.actionPrimary,
    required this.actionComplete,
    required this.actionSecondary,
    required this.statusRunning,
    required this.statusOnline,
    required this.reward,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.dark,
    required this.selection,
    required this.self,
    required this.partner,
    required this.selfOnDark,
    required this.partnerOnDark,
    required this.resonance,
  });

  // ── 면·선 (중성) ──
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

  // ── 글자 (중성) ──
  final Color textPrimary;

  /// 단위·캡션
  final Color textSecondary;

  /// 비활성·플레이스홀더. 본문으로 쓰지 않는다
  final Color textDisabled;

  /// 잉크 면 위의 글자
  final Color textOnDark;

  /// 글자 링크 — 중성. 링크임은 색이 아니라 화살표·밑줄로
  final Color link;

  // ── 액션 ──
  /// 러닝 시작/GO 등 주 액션 (브랜드 코랄). **글자는 굵게 16pt 이상**
  final GoRole actionPrimary;

  /// 저장·완료·확정 — 잉크 면
  final GoRole actionComplete;

  /// 아웃라인·텍스트 버튼 — 중성
  final GoRole actionSecondary;

  // ── 상태 칩 (진한 면) ──
  /// 뛰는 중 — 브랜드 코랄 면 (제품 고유 상태)
  final GoRole statusRunning;

  /// 온라인·GPS·완료 — success solid + 흰 글자
  final GoRole statusOnline;

  /// 코인·적립 전용. **리워드 외 사용 금지** — 라임 면 + 잉크 글자
  final GoRole reward;

  // ── 시맨틱 (옅은 면 + 글자) ──
  /// 준비 완료·이룬 것·성공 토스트. 글자·아이콘은 `.fg`
  final GoRole success;

  /// 연결 안내·늦음·미등록. 글자·아이콘은 `.fg`
  final GoRole warning;

  /// 실패 토스트·삭제·차단·탈퇴·유효성 오류. 글자·아이콘은 `.fg`
  final GoRole error;

  /// 안내·중립 알림
  final GoRole info;

  // ── 잉크 면 ──
  /// 히어로 카드·세그먼트 활성
  final GoRole dark;

  /// 선택된 자리의 표시 — 잉크를 옅게 드리운 그림자 면 + 잉크 글자
  final GoRole selection;

  // ── 관계색 ──
  /// 나 — 라임 파생 올리브. 글자·아이콘·옅은 면(18%)
  final Color self;

  /// 상대 — 코랄 파생. 글자·아이콘·옅은 면(18%)
  final Color partner;

  /// ink·canvas 위에서만 쓰는 원색(히어로의 점, 공명 캔버스의 링)
  final Color selfOnDark;
  final Color partnerOnDark;

  /// 공명 골드 — 러닝 화면 전용
  final Color resonance;

  // ── 옛 이름 (2026-09-09 이전). 새 코드는 시맨틱 역할을 쓴다 ──
  /// [success].fg
  @Deprecated('roles.success.fg')
  Color get positive => success.fg;

  /// [warning].fg — 파괴적 행동(지우기·차단)이면 [error].fg
  @Deprecated('roles.warning.fg 또는 roles.error.fg')
  Color get attention => warning.fg;

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
    textSecondary: GoColors.neutral600,
    textDisabled: GoColors.neutral500,
    textOnDark: GoColors.paper,
    link: GoColors.neutral700,
    actionPrimary: GoRole(
      bg: GoColors.coralComponent,
      fg: GoColors.white,
      pressed: GoColors.coralComponentPressed,
    ),
    actionComplete: GoRole(
      bg: GoColors.ink,
      fg: GoColors.paper,
      pressed: GoColors.inkPressed,
    ),
    actionSecondary: GoRole(
      bg: Color(0x00000000),
      fg: GoColors.ink,
      border: GoColors.neutral400,
      pressed: GoColors.pressOverlay,
    ),
    statusRunning: GoRole(
      bg: GoColors.coral,
      fg: GoColors.ink,
      pressed: GoColors.coralPressed,
    ),
    statusOnline: GoRole(
      bg: GoColors.successSolid,
      fg: GoColors.white,
      pressed: GoColors.successSolidPressed,
    ),
    reward: GoRole(
      bg: GoColors.lime,
      fg: GoColors.ink,
      pressed: GoColors.limePressed,
    ),
    success: GoRole(
      bg: GoColors.successSoft,
      fg: GoColors.successText,
      border: GoColors.successText,
      pressed: GoColors.successSoftPressed,
    ),
    warning: GoRole(
      bg: GoColors.warningSoft,
      fg: GoColors.warningText,
      border: GoColors.warningText,
      pressed: GoColors.warningSoftPressed,
    ),
    error: GoRole(
      bg: GoColors.errorSoft,
      fg: GoColors.errorText,
      border: GoColors.errorText,
      pressed: GoColors.errorSoftPressed,
    ),
    info: GoRole(
      bg: GoColors.infoSoft,
      fg: GoColors.infoText,
      border: GoColors.infoText,
      pressed: GoColors.infoSoftPressed,
    ),
    dark: GoRole(
      bg: GoColors.ink,
      fg: GoColors.paper,
      pressed: GoColors.inkPressed,
    ),
    selection: GoRole(
      bg: GoColors.inkVeil,
      fg: GoColors.ink,
      pressed: GoColors.inkVeilPressed,
    ),
    self: GoColors.selfText,
    partner: GoColors.partnerText,
    selfOnDark: GoColors.lime,
    partnerOnDark: GoColors.coral,
    resonance: GoColors.resonance,
  );

  static GoRoles of(BuildContext context) =>
      Theme.of(context).extension<GoRoles>() ?? light;

  @override
  GoRoles copyWith() => this;

  @override
  GoRoles lerp(ThemeExtension<GoRoles>? other, double t) => this;
}

/// 깊이의 사다리 (2026-09-08). 화면은 한 장의 종이가 아니라 **층**이다 —
/// 아래에서 위로:
///
/// | 층 | 면 | 그림자 | 무엇 |
/// |---|---|---|---|
/// | 0 바탕 | [GoRoles.background]/[GoRoles.canvas] | 없음 | 종이 |
/// | 1 읽는 카드 | [GoRoles.surface] | [card] | 프로필·스탯·그룹 목록 — 정보 |
/// | 2 누르는 카드 | [GoRoles.surfaceHigh] | [elevated] | onTap이 있는 [GoCard] — 열린다 |
/// | 3 주 CTA | 역할색 면 | [raised] | primary·complete 버튼 — 눌러주길 바라는 것 |
/// | 4 떠 있는 것 | [GoRoles.surfaceVeil] | [bar] | 탭바 |
/// | 5 덮는 것 | [GoRoles.surfaceHigh] | [overlay] | 시트·다이얼로그·토스트 |
///
/// 층은 **역할이 정한다.** 같은 카드라도 정보를 담으면 1층, 누르면 열리는
/// 것이면 2층이다. 화면마다 "이건 좀 더 띄우자"고 고르지 않는다 — 고르기
/// 시작하면 모든 카드가 조금씩 떠서 다시 평면이 된다.
///
/// 그림자는 **두 겹**이다 — 붙어 있는 접촉 그림자 하나와 넓게 퍼지는
/// 주변광 그림자 하나. 한 겹짜리 그림자는 스티커처럼 보인다.
///
/// 색은 [GoColors.shadow](따뜻한 갈색-검정). 알파가 낮아 페이퍼 위에서는
/// 카드 가장자리를 살짝 어둡게 만드는 정도로만 보이고, 그것이 곧 경계다
class GoShadow {
  /// 1층 — 페이지에 놓인 카드·그룹(정보)
  static const card = [
    BoxShadow(color: Color(0x1A4A3A24), blurRadius: 3, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x144A3A24), blurRadius: 12, offset: Offset(0, 5)),
  ];

  /// 2층 — 누르면 열리는 카드. [card]보다 주변광이 더 멀리 퍼진다.
  /// 눌리면 [pressed]로 접혀 1층 아래까지 내려앉는다
  static const elevated = [
    BoxShadow(color: Color(0x1F4A3A24), blurRadius: 4, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x1A4A3A24), blurRadius: 20, offset: Offset(0, 8)),
  ];

  /// 눌린 카드 — 그림자가 줄면 종이가 눌려 들어간 것처럼 보인다
  static const pressed = [
    BoxShadow(color: Color(0x0F4A3A24), blurRadius: 1, offset: Offset(0, 0.5)),
  ];

  /// 3층 — 주 버튼처럼 눌러주길 바라는 것
  static const raised = [
    BoxShadow(color: Color(0x244A3A24), blurRadius: 4, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x1F4A3A24), blurRadius: 18, offset: Offset(0, 8)),
  ];

  /// 5층 — 시트·다이얼로그·토스트. 화면에서 확실히 떨어져 나온 것
  static const overlay = [
    BoxShadow(color: Color(0x1F4A3A24), blurRadius: 6, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x244A3A24), blurRadius: 32, offset: Offset(0, 12)),
  ];

  /// 4층 — 탭바처럼 위로 그림자를 던지는 것
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

  /// 값이 바뀌었을 때(스탯·상태 문구·뼈대→목록). 새 값이 아래에서 떠오르며
  /// 옛 값과 교차한다 — 손이 아니라 데이터가 바꾼 것이라 select보다 길다
  static const update = Duration(milliseconds: 200);

  /// 탭 인디케이터가 **자리를 옮기는 것**. 색이 바뀌는 게 아니라 물체 하나가
  /// 옆으로 미끄러지는 것이라 select(120ms)보다 길다 — 짧으면 이동이 아니라
  /// 순간이동으로 읽힌다
  static const slide = Duration(milliseconds: 300);

  /// 미끄러지는 것 전용 곡선. 처음에 빠르게 떨어져 나와 오래 잦아든다 —
  /// 무게가 있는 물체가 밀려가 멈추는 모양이다. 되튀지는 않는다(overshoot는
  /// 장난스럽게 읽힌다)
  static const slideCurve = Cubic(.2, 0, 0, 1);

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
  static const rule = 1.0; // 섹션 구분선 (GoColors.rule)
  static const card = 1.5; // 카드 테두리 (GoColors.line)
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
  static const card = 16.0; // 카드 안쪽 패딩
  static const hero = 20.0; // 히어로 카드 안쪽 패딩
  static const section = 24.0; // 섹션 사이
  static const gutter = 12.0; // 한 줄에 카드 여럿일 때 사이
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
    color: GoColors.neutral600,
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
      // 아이콘 기본색(textPrimary). 화면에서 색을 안 넘기면 이 값을 받는다
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
