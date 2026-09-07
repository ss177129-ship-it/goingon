# Handoff: 고잉온 UI 컴포넌트 — 제안 항목 구현

## Overview
`GoingOn Components.dc.html`은 고잉온(Flutter, iOS) 앱의 UI 컴포넌트 시트입니다. 대부분은 이미 코드에 있는 패턴을 정리한 것이고, 이 핸드오프의 목표는 시트에서 **`제안`** 표시가 붙은 항목을 `lib/widgets/`에 공용 위젯으로 추가하는 것입니다.

## About the Design Files
이 폴더의 HTML은 **디자인 참고용 프로토타입**입니다. 프로덕션 코드가 아니며 그대로 복사하지 않습니다. 할 일은 이 디자인을 **기존 Flutter 코드베이스의 방식으로 재구현**하는 것 — `lib/theme.dart`의 토큰(`GoColors` · `GoRadius` · `GoStroke` · `GoSpace` · `GoText` · `GoTheme.serif`)과 기존 위젯(`Pressable`, `InitialAvatar`)을 사용합니다. 브라우저에서 보려면 `GoingOn Components.dc.html`을 열면 됩니다(같은 폴더의 `support.js` 필요).

## Fidelity
**High-fidelity.** 색·크기·글자·간격은 최종값입니다. 단, 값은 전부 `theme.dart` 토큰으로 표현되어야 하며 숫자를 화면 코드에 직접 적지 않습니다. 새 토큰이 필요하면 `theme.dart`에서만 추가합니다.

## 저장소 제약 (2026-09-08 갱신 — 이 시트의 색 이름은 옛것이다)
아래 항목의 `limeDark` · `coralDark` · `mid` · `dim` · `amber`는 **더 이상 존재하지 않는 팔레트 이름**이다. 구현은 `lib/theme.dart`의 역할 토큰(`GoRoles.of(context)`)으로 했고, 색의 쓰임은 theme.dart의 Color Usage Rules를 따른다. 이 문서의 색 지시와 theme.dart가 다르면 **theme.dart가 이긴다.**
- 색은 `GoRoles` 역할 토큰으로만. 팔레트·hex 직접 사용 금지.
- 칩·배지·상태는 옅은 틴트가 아니라 **원색 면**(코랄·초록·라임) + 대비되는 글자. 보조색은 전부 선명하다(채도 .75+).
- 모서리는 `GoRadius.sm 12` · `md 16` · `lg 24`만. 선 굵기는 `GoStroke.rule 1` · `card 1.5` · `accent 2`만.
- 12px 미만 글자 없음. 세리프(`GoTheme.serif`)는 숫자·라틴·"GO?"에만, 한글은 산세리프.
- 이모지 금지 — Material Icons와 텍스트만.
- 눌림 반응은 `Pressable`(0.97, 즉시 눌림 / 90ms 복귀) 하나로 통일.
- 선택·오류·성공은 색 하나로 전하지 않는다 — 아이콘·형태·텍스트를 함께.
- 완료 기준: `flutter analyze` 에러 0 → `flutter test` 전부 통과 → 시뮬레이터에서 해당 화면까지 진입해 스크린샷으로 확인.

## Screens / Views
화면이 아니라 **컴포넌트**입니다. 각 항목: 파일 → 스펙 → 사용 위치 순.

### 1. `GoSwitch` — `lib/widgets/go_switch.dart`
현재 `settings_screen.dart`의 Material `Switch(activeThumbColor: GoColors.limeDark)`를 대체.
- 크기 51×31, 트랙 radius 16(전체 둥근 형태).
- 켬: 트랙 `GoColors.limeDark`, 손잡이 27 white, left 22 · 끔: 트랙 `GoColors.dim`, 손잡이 left 2.
- 손잡이 그림자 `0 1 3 rgba(26,26,22,.25)`.
- 전환 150ms(`AnimatedAlign` 또는 `AnimatedPositioned` + `AnimatedContainer` color).
- 비활성(`onChanged == null`): 전체 opacity .4, 탭 무시.
- 행 안에서는 행 전체가 탭 영역(`_row`의 `onTap`이 이미 그렇게 되어 있음). 탭 시 `HapticFeedback.selectionClick`.
- API: `GoSwitch({required bool value, ValueChanged<bool>? onChanged})`.

### 2. `GoCheckbox` — `lib/widgets/go_checkbox.dart`
- 원 22 (`BoxShape.circle`). 미선택: white 면 + `GoColors.line` 1.5. 선택: `GoColors.lime` 면 + 같은 색 테두리 + `Icons.check` 16 `GoColors.ink` (weight 700에 가깝게 — Material Icons는 단일 굵기라 `Icons.check` 그대로).
- 라벨 `GoText.body`(15/1.5 ink). "(선택)" 같은 보조 표기는 12 `GoColors.mid`.
- 탭 영역은 행 전체, 최소 높이 44. 전환 120ms.
- API: `GoCheckbox({required bool value, required ValueChanged<bool> onChanged, required Widget label})`.
- 사용 예정: 위치정보 수집·이용 동의(법 요건 — 별도 동의), 이용약관 동의.

### 3. `GoRadio` — `lib/widgets/go_radio.dart`
- 원 22 white. 미선택 `GoColors.line` 1.5. 선택 `GoColors.ink` 2 + 중앙 점 10 `GoColors.ink`.
- 라벨 15 ink, 항목 간격 14, 탭 영역 행 전체(44).
- API: `GoRadioGroup<T>({required List<(T, String)> options, required T? value, required ValueChanged<T> onChanged})`.
- 사용 예정: 홈의 "어떻게 전할까요?" 답장 선택지(지금은 OutlinedButton 3개) — 교체 여부는 판단 후 결정, 우선 위젯만 추가.

### 4. `GoTabs` (밑줄 탭) — `lib/widgets/go_tabs.dart`
- 라벨 `14/600` 산세리프, 항목 간격 20, 패딩 상하 10.
- 활성: `GoColors.ink` 글자 + 아래 2px `GoColors.ink` 밑줄. 비활성: `GoColors.mid`, 밑줄 없음.
- 컨테이너 바닥선 1px `GoColors.line`(밑줄이 바닥선을 덮음 — 밑줄을 -1 오프셋).
- 전환 120ms color. 시트 예시 라벨: 함께한 순간 / 마일스톤 / 기록.
- API: `GoTabs({required List<String> labels, required int index, required ValueChanged<int> onChanged})`.

### 5. `GoSegment` — `lib/widgets/go_segment.dart`
- 컨테이너: white 면, `GoColors.line` 1.5, radius `GoRadius.sm 12`, 안쪽 패딩 3, 항목 간격 2. 높이 40.
- 항목: flex 균등, `13/600`, 상하 패딩 9, radius 9(= 12 − 3, 기하값이라 토큰 아님).
- 활성: `GoColors.ink` 면 + `GoColors.paper` 글자. 비활성: 투명 + `GoColors.mid`.
- 전환 120ms. 예시: 이번 주 / 이번 달 / 전체.
- API: `GoSegment({required List<String> labels, required int index, required ValueChanged<int> onChanged})`.

### 6. `GoSelectChip` — `lib/widgets/go_chip.dart`
- 높이 32, 패딩 9/14, radius `GoRadius.sm 12`, 글자 `13/600`.
- 미선택: white + `GoColors.line` 1.5 + `GoColors.ink` 글자. 선택: `GoColors.ink` 면 + 같은 색 테두리 + `GoColors.paper` 글자.
- 같은 파일에 기존 패턴도 위젯으로: `GoStoryChip`(white, `limeDark` 2px, 12/600 limeDark, 패딩 3/8 — 현재 `us_screen._momentRow`의 9px를 12px로 올림) · `GoStatusTag`(white, *Dark 2px, 12/600 letter-spacing 1.2, 패딩 5/12 — 현재 `home_screen._showGoRequest`의 11px).
- API: `GoSelectChip({required String label, required bool selected, VoidCallback? onTap})`.

### 7. `GoCountBadge` · 라이브 점 · 라이브 태그 — `lib/widgets/go_badge.dart`
- 카운트 배지: 최소 18×18, 패딩 가로 5, radius 9, `GoColors.coralDark` 면, `GoColors.paper` 글자 12/600, 바깥에 2px `GoColors.paper` 링. 아이콘의 우상단(top −2, right −6)에 겹침. 0이면 그리지 않음.
- 사용 위치: `GoBottomNav` '우리' 탭 — 나에게 온 친구 요청 수(`FriendService.incomingRequestsStream`).
- 라이브 점: 아바타 우하단, 14 `GoColors.lime` + 2px paper 링. 상대가 지금 달리는 중일 때(세션 `live` 맵 기준).
- 라이브 태그: white, `limeDark` 2px, radius 12, 점 8 lime + "달리는 중" 12/600 limeDark, 패딩 5/10/5/8.

### 8. `GoSkeletonRow` — `lib/widgets/go_skeleton.dart`
- 최초 로딩(`_lastSessions == null` 같은 경우)에만. 마지막 데이터가 있으면 그것을 유지한다(이 앱의 원칙 — 깜빡임 금지).
- 행: 상단 1px `GoColors.line`, 패딩 상하 12. 원 44 + 막대(30% × 12, 55% × 10, radius 6/5) + 오른쪽 64×44 radius 12. 색 `ink 8%`(`GoColors.ink.withValues(alpha: .08)`), 두 번째 막대 6%.
- 애니메이션 없음.

### 9. (선택) 라이브 스탯 배치 — `run_screen.dart`
숫자 크기는 기존 코드 그대로(거리 serif 68 limeDark · 페이스 serif 40 ink · 상태 serif 44 `GoColors.resonance`). 시트의 배치(거리 위, 아래 줄에 페이스 좌 / 공명 상태 우, 라벨 `GoText.label`)는 **제안**이므로 별도 판단 후 적용.

## 정규화 (2026-09-08 적용됨 — 글자 12px 이상은 완료, radius는 미적용)
시트는 theme.dart 규칙에 맞춰 코드의 예외값을 정리했습니다:
- radius 14 → 12(칩·작은 버튼·`friend_search_sheet` 입력) / 18 → 16(다이얼로그·확인 카드·빈 카드) / 22 → 24(프로필 카드·히어로 카드).
- 9~11px 글자 → 12px(스토리 라벨, 요청 태그, 순간 행의 월·기분 줄, 탭바 라벨, 친구 행 보조 줄).
- 홈 헤더 검색 아이콘 `dim` → 기본 `ink`(dim은 글자·아이콘 금지 규칙).

## Interactions & Behavior
- 모든 탭 가능한 요소는 `Pressable`(scale 0.97, 눌림 0ms, 복귀 90ms easeOut, `HapticFeedback.selectionClick`).
- 스위치 150ms, 체크·라디오·탭·세그먼트·칩 120ms. 곡선 easeOut.
- 비활성은 opacity .4(스위치) 또는 lime 35%(버튼). 로딩은 버튼 면 유지 + 20 spinner(stroke 2, ink).

## State Management
기존 패턴(StatefulWidget + setState + Stream 구독) 유지. 위젯은 전부 **상태 없는(controlled)** 형태 — `value`/`index`와 `onChanged`만 받고 상태는 호출한 화면이 가집니다.

## Design Tokens (theme.dart와 동일)
- 색: paper `#F0EAE0` · canvas `#EBE4D6` · lime `#C5E040` · limeDark `#48700A` · coral `#F05840` · coralDark `#B03020` · amber `#D97706` · amberDark `#9A5200` · resonance `#D4A84B` · ink `#1A1A16` · mid `#5E5A54` · dim `#B0ACA6` · line ink 16%.
- 모서리 12 · 16 · 24. 선 1 · 1.5 · 2. 간격 4 · 8 · 12 · 16 · 24 · 32, 화면 좌우 24, 시트 안 28.
- 글자: title serif 28 · heading serif 22 · body 15/1.5 · secondary 13/1.45 mid · label 12/600 ls .6 · button 16/600 · buttonSmall 14/600.
- 폰트: Instrument Serif(이탤릭, 한글은 NotoSansKR 폴백) + NotoSansKR — 번들, `GoTheme.serif()`만 사용.

## Assets
새 에셋 없음. 아이콘은 Material Icons(`Icons.check`, `Icons.group`/`people_alt_outlined` 등). 시트의 웹 아이콘(Material Symbols)은 Flutter의 Material Icons로 1:1 대응.

## Files
- `GoingOn Components.dc.html` — 컴포넌트 시트(브라우저에서 열기, `support.js` 필요). 섹션 06 · 09 · 10 · 11 · 12에 `제안` 항목.
- `support.js` — 시트 런타임.

## Claude Code에 붙일 프롬프트 (예시)
```
design_handoff_goingon_components/README.md를 읽고, "제안" 항목 1~8을 lib/widgets/에 공용 위젯으로 추가해줘.
- 값은 theme.dart 토큰만 사용, 새 상수는 theme.dart에만
- 눌림은 Pressable로, 위젯은 controlled(value + onChanged)
- 각 위젯에 test/ 위젯 테스트 1개 이상 (pressable_test.dart 스타일)
- GoSwitch로 settings_screen의 Switch 두 곳을 교체하고, GoBottomNav '우리' 탭에 GoCountBadge를 연결
- 끝나면 flutter analyze → flutter test → 시뮬레이터에서 설정 화면 스크린샷으로 확인하고 결과 보고
정규화(두 번째 패스)는 아직 하지 말고 목록만 정리해서 보고해줘.
```
