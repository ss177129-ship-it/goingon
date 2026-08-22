# 고잉온 레포 감사 보고서
2026-08-21 | 대상: github.com/ss177129-ship-it/goingon (master, 얕은 클론) | 판정: 유지 / 회수·개조 / 폐기 / 신규

## 요약

**Flutter 앱, lib 48파일 / 약 10,300줄 + Cloud Functions(TS) + 테스트 20종.** 상태는 예상보다 훨씬 좋다. 특히 사운드 시스템과 공명 엔진은 새 설계와 같은 철학("침묵이 기본값", 상태 수 절제, 공유 스무딩 상수)으로 이미 지어져 있어, 이 결합은 이식 수술이 아니라 **증축**이다. 기존 앱은 '라이브 1:1 공명'(새 설계의 v1.1 범위)을 먼저 만든 것이고, 새 설계는 그 앞에 고스트·에피소드·릴레이를 세우는 순서 재배열이다.

**최대 발견:** `docs/sound_ux_v1.md`가 케이던스 리듬 레이어를 '트랙 B(부록)'로 이미 계획해 두었다 — 케이던스 부재를 인지하고 페이스 기반으로 우선 출항한 것. **새 설계의 M0(케이던스 엔진)은 곧 이 트랙 B의 승격이다.** 과거 결정과 새 설계가 정확히 이어진다.

## 판정 1 — 유지 (그대로 쓴다)

| 자산 | 근거 |
|---|---|
| `ios/` 셸 전체 (번들ID·사이닝·엔타이틀먼트·`tools/ship-testflight.sh`) | 테스트플라이트 배포 파이프라인 가동 중 — 재구축 시 수일 손실. **가장 비싼 무형자산: 심사 통과 이력** |
| Firebase 스택: `auth_service`(애플·구글 로그인), `push_service` + `functions/src/push.ts`, `firestore.rules` | 인증·푸시·DB 규칙 전부 작동 검증됨. 기술설계서의 "얇은 서버" 요구와 합치 (Supabase 제안 철회 — 아래 수정사항) |
| `theme.dart` + 번들 폰트(NotoSansKR·InstrumentSerif) + 브랜드 에셋 | "타이포가 정체성이라 폰트를 번들함" — 철학까지 유지 |
| 공용 위젯: `bottom_nav` `pressable` `go_dialog` `go_toast` `initial_avatar` `brand_mark` | 새 와이어프레임과 충돌 없음 |
| 러닝 데이터 계층: `run_service` `run_accumulator` `run_recovery` `week_key` `location_service` `active_run_guard` `app_version_gate` | 세션 저장·복구·주간 집계 — 새 설계의 RunRecorder 요구 충족. GPS는 새 설계대로 '선택 부품'화만 |
| `friend_service` + `friend_search_sheet` | 페이스메이트(팔로우)의 토대 |
| `test/` 20종 | 회귀 안전망 — 개조 작업의 보험 |

## 판정 2 — 회수·개조 (핵심 자산, 새 설계에 맞게 수술)

| 자산 | 현재 | 수술 내용 |
|---|---|---|
| **`resonance.dart` (435줄)** | SyncState 4단계(drifting→approaching→aligned→resonant), 페이스 기반 closeness, 공유 스무딩 1초 | 입력을 페이스→**케이던스**로 교체(= 문서의 트랙 B 승격). 라이브뿐 아니라 **고스트 타임라인도 입력으로** 받게 확장. 판정 임계는 설계도 §1-3 값으로 튜닝 |
| **사운드 시스템** (`sound_engine` `soloud_sound_engine` `resonance_sound` `audio_session_controller` + `assets/audio/` 7종) | SoLoud 저지연 엔진, 공명 패드+배음, 진입 차임, 신호음 체계 | D안의 뼈대로 승격: 스템 루프 재생 + 재생속도(BPM) 동기 추가. **수신음 3종(sigHere·sigCheer·sigSlow)은 '사운드 응원 이모티콘'의 원형 그대로** — BM 1호 상품의 씨앗이 이미 있음 |
| `run_briefing` + `briefing_script` | 러닝 브리핑 대본 시스템 | 화자(페이서)·에피소드 내레이션의 기반으로 확장 |
| `us_screen` | '우리' 탭 — 1:1 친구와 쌓은 여정 + 거리 마일스톤 | 새 여정 화면(와이어프레임 15)의 골격으로 개조. 마일스톤 로직 재사용 |
| `resonance_canvas` | 공명 시각화 위젯 | 새 러닝 중 화면(두 원 문법)에 맞게 리스킨 |
| `shared_stream` | 실시간 동기화 스트림 | v1.1(라이브 공명)까지 냉동 보관 — 삭제 금지 |
| `demo_resonance` | 데모 공명 | 온보딩 데모런(와이어프레임 02)의 기반 |

## 판정 3 — 폐기 (새 설계와 충돌 — 부품만 회수 후 재작성)

| 자산 | 이유 |
|---|---|
| `lobby_screen` | 로비=약속 대기 UX는 동시성 전제의 유물. 새 설계에서 '오늘의 상대 선택'+존재 레이어로 대체 |
| `run_screen` (709줄) | 새 세션 상태머신(intro→…→잔향→자유런)과 에피소드 구조로 재작성. 위젯 부품만 회수 |
| `home_screen` | 새 홈 2종(입문자/경험자 분기)으로 교체 |
| `finish_screen` | '완주 후 5분' 설계(음성 채집→트랙 주인공 결과)로 교체 |

## 판정 4 — 신규 (기존에 없음, 기술설계서 §3 그대로)

CadenceEngine(가속도계 스텝 검출 — 트랙 B의 본선 승격) · 에피소드/채보(ChartPlayer) · 템포 동기 스템 음악 · GhostEngine · 첫 러닝 릴레이 · 음성 한 마디 채집 · 잔향 판정 · 게이트형 DM(v1.1)

## 기술설계서 수정 결정 (§8 미결정 1·4번 해소)

1. **스택: Swift 네이티브 전환 취소 → Flutter 유지.** 근거: ① SoLoud 저지연 오디오가 이미 검증됨(네이티브 전환의 최대 사유였던 오디오 성능 문제가 부재) ② 배포 파이프라인·심사 이력 ③ 10K 라인+테스트 자산 ④ 1인팀에게 재작성은 최악의 자본 배분. 케이던스는 `sensors_plus`(가속도계) 우선, 정밀도 부족 시 CMPedometer 플랫폼 채널.
2. **백엔드: Supabase 제안 철회 → Firebase 유지.** Firestore+Functions+FCM이 이미 가동 중. 새 스키마(runs·ghosts·relay 등)는 Firestore 컬렉션으로 이식.

## 결합 실행 순서 (M0 재정의)

1. **M0-a**: `sensors_plus` 케이던스 스파이크 — 실주행 오차 ±3spm 검증 (신규)
2. **M0-b**: SoLoud 스템 루프 + 재생속도 BPM 동기 스파이크 (기존 엔진 확장)
3. **M1**: ResonanceEngine 입력 교체(케이던스) + 고스트 입력 → 시차 공명 성립
4. 이후 기술설계서 M2~M4 그대로 (에피소드·릴레이·베타)

한 줄 결론: **버릴 것은 화면 4장뿐이고, 심장 반쪽(사운드·공명)은 이미 뛰고 있었다. 나머지 반쪽(케이던스·고스트)을 이식하면 된다.**
