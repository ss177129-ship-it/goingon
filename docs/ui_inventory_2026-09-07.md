# UI 부품 인벤토리 — 2026-09-07

대상: `lib/screens/*` 전부 + `lib/widgets/*`. 코드 변경 없음. 커밋 `13a76a2` 기준.
목적: `GoButton`·카드·시트 공통 부품을 만들기 전에 지금 흩어져 있는 값을 한 표에 모은 것.

스크린샷 8장: `~/Desktop/goingon_screens_20260907/` (레포에 넣지 않음 — 8MB).

| # | 화면 | 상태 |
|---|---|---|
| 01 | 홈 | ✓ |
| 02 | 우리 | ✓ 기록 없음 상태 |
| 03 | 설정 | ✓ |
| 04 | 프로필 편집 | ✓ |
| 05 | 차단 목록 시트 | ✓ |
| 06 | 로비(데모) | ✓ |
| 07·08 | 러닝(데모) 가까워져요 / 나란히 | ✓ |
| — | 완료 | ✗ 멈춤 버튼 0.55초 홀드 필요(`run_screen.dart:373`) — 접근성 클릭은 탭만 됨 |
| — | 로그인·닉네임·업데이트 필요 | ✗ 로그아웃 후 재로그인이 Apple 인증이라 사람 손 필요 |
| — | GO? 시트·요청 수락 시트·검색 결과 | ✗ 실제 요청이 발송되는 부작용 |

표기: 색 L=lime, I=ink, W=white, P=paper. 글자 `serif(n)`=`GoTheme.serif`, 나머지는 인라인 `TextStyle`. `?`=라벨이 변수라 정적으로 못 읽음. "테마"=`GoTheme.light()`의 버튼 테마 기본값.

---

## (a) 버튼 — 47개

| 파일:줄 | 라벨 | 종류 | 배경 | 라운드 | 글자 | 패딩 |
|---|---|---|---|---|---|---|
| home:198 | GO? 시트 확인 | Filled | L | 16 | ink | v17 |
| home:216 | 나중에 | Text | — | — | mid 13 | 테마 |
| home:252 | 요청 시트 | Outlined | — | 14 | ? | v15 |
| home:315 | 검색(돋보기) | **IconButton** | — | — | 아이콘 dim | 기본 |
| home:347 | 혼자서 먼저 체험해보기 → | Text | — | — | 13 | 테마 |
| home:417 | 거절 | Outlined | — | 12 | 13 | v11 |
| home:435 | 수락하고 연결 | Filled | L | 12 | 13 | v11 |
| home:495 | 다시 시도 | Text | — | — | ? | 테마 |
| home:589 | 친구 행(롱프레스) | **GestureDetector** | — | — | 18 | h22 v`m` |
| home:620 | GO? | Filled | L | 14 | serif(18) ink | h16 v10 |
| home:680 | `_demoLink` | Outlined | — | 14 | 14 | v14 h16 |
| lobby:295 | ← 홈으로 | **GestureDetector** | — | — | mid 11 | 없음 |
| lobby:364 | 단계 카드(탭) | Pressable | W | md | — | `hero` |
| lobby:432 | 카드 안 TextButton | Text | — | — | ? | 테마 |
| lobby:489 | 준비완료 → | Pressable | I | 18 | serif(20) paper | v18 |
| lobby:544 | 카카오톡으로 알리기 | Outlined | — | 12 | 12 w600 ink | v12 |
| lobby:559 | 다음에 다시 | Outlined | — | 12 | 12 w600 mid | v12 |
| us:144 | 다시 시도 | Outlined | — | 16 | serif(18) | v15 |
| us:199 | 페이스메이트 찾기 | Filled | I | 16 | serif(18) paper | v16 |
| us:254 | GO? 보내러 홈으로 | Filled | L | 16 | serif(18) | v15 |
| us:485 | GO? 보내러 홈으로 | Filled | L | 14 | serif(17) | v13 |
| settings:225 | 차단 해제 | Text | — | — | 12 | 테마 |
| settings:413 | 설정 행 | **InkWell** | — | — | 14 | h24 v15 |
| profile:90 | 시트 액션 행 | **InkWell** | — | — | 14 | h28 v16 |
| profile:251 | 취소(다이얼로그) | Text | — | — | mid | 테마 |
| profile:255 | 저장(다이얼로그) | Filled | I | 테마 | serif(15) lime | 테마 |
| profile:279 | ← 설정으로 | **GestureDetector** | — | — | mid 12 | v4 |
| profile:314 | 아바타(사진 변경) | **GestureDetector** | — | — | — | — |
| profile:345 | 사진첩에서 고르기 | Text | — | — | 13 | 테마 |
| profile:359 | 편집 행 | **InkWell** | — | — | 14 w600 | h24 v15 |
| finish:290 | 홈으로 | Pressable | I | 18 | ? | v18 |
| finish:309 | 오늘의 순간 공유하기 | Pressable | — | — | 12 | v10 h16 |
| run:505 | 기분 선택 pill ×N | Pressable | — | 20 | 13 | symmetric |
| run:526 | 건너뛰기 | Text | — | — | mid 13 | 테마 |
| run:701 | 멈춤(홀드) | **GestureDetector** | W 원 | circle | — | — |
| login:112 | G 계속하기 | Outlined | W | 16 | 16 | 테마 |
| nickname:115 | 시작하기 | Filled | I | 16 | ? | v17 |
| update:95 | 업데이트하러 가기 | Pressable | I | 18 | serif(19) lime | v17 |
| update:111 | 업데이트했어요 · 다시 확인 | Pressable | — | — | mid 13 | v12 |
| fss:225 | 찾기 / 요청 | Filled | L | 14 | ? | v15 |
| go_dialog:28 | 취소 | Text | — | — | ? | 테마 |
| go_dialog:33 | 확인 | Filled | I / coralDark(destructive) | 테마 | serif(15) paper | 테마 |
| go_dialog:63 | 확인(notice) | Filled | I | 테마 | serif(15) paper | 테마 |
| bottom_nav:31 | 탭 ×3 | **GestureDetector** | — | — | 10 w600 | — |

**흩어진 값**: 라운드 12·14·16·18·20(5종) · 세로 패딩 10~18(9종) · 글자 serif 15/17/18/19/20 + sans 12/13/14/16. 같은 문구 "GO? 보내러 홈으로"가 우리 탭 안에서 두 벌(us:254 vs :485)로 값이 다름.

---

## (b) 카드 — 31개

| 파일:줄 | 무엇 | 배경 | 테두리 | 라운드 | 패딩 | 눌림 |
|---|---|---|---|---|---|---|
| home:175 | 요청 라벨 pill | W | coralDark accent | sm | h12 v5 | — |
| home:381 | 요청 카드 | W | coralDark accent | md | 16,14,16,14 | — |
| home:478 | 연결 안내 | W | amberDark accent | md | all 14 | — |
| home:529 | 프로필 카드 | W | line card | **22** | 18,18,18,14 | — |
| home:592 | 친구 행 | — | top line rule | — | h22 v`m` | GestureDetector |
| home:754 | 빈 상태 | **W 50%** | line card | **18** | v24 h20 | — |
| lobby:368 | 단계 카드 | W | limeDark/line(ready 분기) | md | `hero` | Pressable |
| lobby:411 | 다음 → 칩 | W | line card | sm | h10 v4 | — |
| lobby:493 | 준비완료 | I | — | **18** | v18 | Pressable |
| lobby:507 | 대기 카드 | W | line card | md | v18 | — |
| lobby:532 | 지연 안내 | W | amberDark accent | md | `card` | — |
| lobby:586 | 러너 원 | W | line / ready색 accent | circle | — | — |
| lobby:600 | 상태 pill | W | line / amberDark / ready색 | sm | h10 v3 | — |
| lobby:630 | 카운트다운 점 | W | ready색 accent | circle | — | — |
| us:125/180/235 | 빈 상태 원 ×3 | W | **mid·coralDark·limeDark 40% 알파** 2px | circle | — | — |
| us:364 | 합산 거리 카드 | ink 계열 | — | **22** | `hero` | — |
| us:416 | 스트릭 | W | amberDark accent | md | h18 v16 | — |
| us:444 | 요일 셀 ×7 | amber 실색 / W | limeDark accent(오늘) / line card | sm | — | — |
| us:585 | `_metric` ×N | W | line card | 16 | v13 h6 | — |
| us:608 | 여정 행 | W | limeDark accent / line | md | h14 v12 | — |
| us:651 | 순간 행 | — | top line rule | — | v`m` | — |
| us:671 | 사연 태그 | W | limeDark accent | sm | h8 v3 | — |
| finish:216 | 함께 블록 | W | line card | md | `card` | — |
| finish:298 | 홈으로 | I | — | **18** | v18 | Pressable |
| finish:345 | 개인 카드 ×2 | W | line card | sm | all 12 | — |
| run:510 | 기분 pill | — | line card | **20** | symmetric | Pressable |
| run:656 | 함께 달린 것 | W | line card | **18** | h28 | — |
| run:719 | 멈춤 원 | W | line card | circle | — | GestureDetector(홀드) |
| settings:193 | 차단 행 카드 | W | line card | 16 | h16 v12 | — |
| fss:163 | 검색창 | W | line card | **14** | h16 | — |
| fss:265 | 검색 결과 카드 | W | line card | **18** | `card` | — |
| update:100 | CTA | I | — | **18** | v17 | Pressable |

**GoRadius 밖 값이 남은 곳**: 22(홈 프로필·우리 합산) · 18(홈 빈 상태·로비 준비완료·완료 홈으로·러닝 카드·검색 결과·업데이트 CTA) · 20(기분 pill) · 14(검색창) · 16 리터럴(`_metric`·차단 행 — 값은 md와 같지만 토큰 아님). 틴트 작업(`1940602`) 때 손댄 decoration만 토큰화했고 나머지는 리터럴.
**규칙 사각지대**: `us:125/180/235` 40% 알파 테두리(틴트 규칙은 배경만 걷어냄), `home:754` 흰 50% 배경.

---

## (c) 시트 · 다이얼로그 · 토스트

| 종류 | 수 | 호출부 |
|---|---|---|
| `showModalBottomSheet` | 7 | home:164 GO? 수신 · home:235 요청 응답 · home:638 친구 액션(끊기/차단) · settings:140 차단 목록 · profile:69 사진 액션 · run:488 기분 선택 · fss:16 친구 검색 |
| `showDialog` 직접 | 1 | profile:218 이름/아이디 입력 |
| `GoDialog.confirm` | 7 | home:703·719 끊기/차단 · profile:133 사진 삭제 · root:75 러닝 복구 · run:472 종료 · settings:252 로그아웃 · settings:273 탈퇴 |
| `GoDialog.notice` | 2 | lobby:200 · run:235 |
| `GoToast.show` | 8 | home:464·741 · profile:122·149 · settings:71·80·242 · fss:125 |
| `GoToast.error` | 24 | root 1 · login 2 · nickname 3 · lobby 3 · profile 9 · home 3 · settings 4 · run 1 · finish 1 |

시트 7개 중 패딩이 `(sheet, xl, sheet, sheetBottom)`로 통일된 건 4개(home ×2·settings·run). home:171은 `(28,28,28,40)`, profile:69·fss:16은 별도 확인 필요. 시트 상단 라운드는 home:169만 `vertical(top: 24)` 확인됨.

---

## (d) 아바타 · 아이콘

**InitialAvatar 크기 7단계**: 96(프로필 편집) · 88(GO? 수신 시트) · 60(홈 내 카드) · 44(친구 행·검색 결과) · 40(요청 카드·차단 행) · 30(우리 페어) · 24(설정 프로필 행). 테두리 링은 전부 `accent`(2px). `emptyIcon`은 `size × .43`.

**Icon 크기 6단계**: 30(우리 빈 상태 ×2) · 28(우리 오프라인) · 24(탭바·스트릭 불꽃·홈 검색=기본) · 20(설정·프로필 행 아이콘·설정 chevron·여정 행) · 18(프로필 chevron·wifi_off) · 14(로비 터치 힌트). chevron만 18/20 두 벌.

---

## (e) Pressable을 안 거치는 눌림 요소 — 48개 중 40개

| 위젯 | 수 | 곳 | 비고 |
|---|---|---|---|
| **GestureDetector** | 7 | 홈 친구 행(롱프레스) · 로비 ← 홈으로 · 프로필 ← 설정으로 · 프로필 아바타 · 러닝 멈춤(홀드) · 탭바 ×3 | 눌림 피드백(축소·햅틱) 없음. 탭바가 여기 있는 게 가장 눈에 띔 |
| **InkWell** | 3 | 설정 행 · 프로필 편집 행 · 사진 시트 액션 행 | Material 잉크 리플 |
| **IconButton** | 1 | 홈 검색 | Material 기본 |
| **Filled / Outlined / Text** | 29 | (a) 표 | Material 리플 — Pressable(0.97 축소 + selectionClick)과 촉감이 다름 |

Pressable을 쓰는 건 8곳(로비 2 · 완료 2 · 러닝 pill · 업데이트 2). 같은 화면(로비) 안에서도 준비완료는 Pressable, 카카오톡 알리기는 Outlined. `GoButton`을 만들 때 위 40개가 후보.

---

## 확인 방법

- 코드: `grep`으로 `FilledButton|OutlinedButton|TextButton|Pressable|GestureDetector|InkWell|IconButton`, `BoxDecoration(`, `InitialAvatar(`, `Icon(`, `showModalBottomSheet|showDialog|GoDialog.|GoToast.` 전수 조사. 라벨이 변수인 것은 `?`.
- 화면: 시뮬레이터 접근성 클릭(TODO §5.1)으로 홈→우리→설정→프로필 편집→차단 목록→데모 로비→데모 러닝 순서로 진입해 촬영.
