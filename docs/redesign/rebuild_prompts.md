# 고잉온 개편 프롬프트 시퀀스 v1
2026-08-21 | session_ui_prompts.md와 같은 용법: 한 번에 프롬프트 하나씩, 순서대로, 완료 기준 통과 후 다음으로.

## 사용법

- 각 프롬프트를 통째로 복사해 코딩 에이전트에게 준다. **P0부터 순서대로** — 건너뛰면 CLAUDE.md의 "의도된 설계 결정" 충돌로 에이전트가 멈추거나, 더 나쁘게는 옛 설계 위에 새 코드를 쌓는다.
- 설계 근거는 전부 `docs/redesign/`에 있다: 전략(strategy_memo) · UX(ux_decisions_v1.1) · 제품 상세(product_design_v1.1) · 기술(tech_design_v1.0) · 재사용 판정(repo_audit).
- 완료 기준은 CLAUDE.md의 것을 그대로 쓴다: analyze 에러 0 · test 전부 통과 · 시뮬레이터 도달 · 화면 작업이면 스크린샷 보고. 매 프롬프트 끝 = 커밋 하나.

---

## P0 — 거버넌스 개정 (사람의 결정. 에이전트에게 주기 전에 CEO가 승인)

> CLAUDE.md의 "의도된 설계 결정" 섹션을 `docs/redesign/strategy_memo.md`(D-001~006)에 맞게 개정하라. 구체적으로:
> ① "러닝 중 라이브 동기화"는 유지하되 v1.1 범위로 이동함을 명시 (v1.0의 함께는 고스트런·응원이 담당)
> ② 로비 화면과 GO? 요청 TTL 항목에 "폐기 예정 — 오늘의 상대 선택 + 존재 레이어로 대체(docs/redesign/product_design_v1.1.md §2-2, §3)" 주석 추가
> ③ 새 항목 추가: "세션 = 8분 에피소드(시간 기반·완결 내장·상한 아님·자유런 병존)", "케이던스가 심장(BPM=케이던스, 내 발소리 기본 무음)", "고스트런은 시차 동행(승패 언어 금지)", "러닝 중 화면 조작 제로", "연결 과금 금지·러닝 중 삽입 광고 영구 금지"
> ④ 데모 모드(심사관용)는 유지 — 단 내용물을 '데모런(온보딩 페이서)'과 통합할 것을 TODO로
> ⑤ TODO.md에 P1~P8 마일스톤을 등록
> 사운드 작업 단일 기준은 sound_ux_v1.md에서 **product_design_v1.1.md §1(사운드 시스템)으로 승계**됨을 CLAUDE.md에 명시하라 (sound_ux_v1.md의 금지 목록 — 실패음·상시 배경음 금지 — 은 새 설계에서도 유효).

## P1 — M0 스파이크 실측·파라미터 확정 (이미 설치됨)

> `docs/m0_spike.md`를 읽고 M0-a(케이던스)·M0-b(템포 동기) 스파이크를 실측 지원하라. 내(CEO)가 실주행 CSV(cadence_probe.csv, tempo_probe.csv)를 가져오면: ① 랩 구간별 수동 카운트 대비 오차를 계산하고 ② ±3spm 기준 미달이면 `lib/services/cadence/cadence_engine.dart`의 kThresholdK·검출 창을 튜닝해 재실측을 요청하라. ③ 지터 p95>30ms이면 SoLoud 오디오 스레드 스케줄링 대안을 설계하라. 통과 시 확정 파라미터를 주석에 "실측 확정(날짜)"로 남기고 커밋. **이 프롬프트가 통과되기 전에 P2로 가지 말 것.**

## P2 — 공명 엔진 입력 교체: 페이스 → 케이던스

> `docs/redesign/repo_audit.md` 판정 2와 `docs/redesign/product_design_v1.1.md` §1-3을 읽어라. `lib/services/resonance.dart`의 closeness 입력을 페이스에서 케이던스(`lib/services/cadence/cadence_engine.dart`의 CadenceSample.spm)로 교체하라. 판정 초기값: |Δspm|≤3이 8초 지속 시 공명 진입, 이탈 10초 시 해제(실패음 없음 — sound_ux_v1.md 금지 목록 유효), 정수비(1:2, 2:3) 폴리리듬 인정. SyncState 4단계와 kSharedSmoothingTimeConstant는 유지한다. **입력 소스를 추상화하라** — 라이브 상대(shared_stream)와 고스트 타임라인(P4)이 같은 인터페이스로 꽂히게. 기존 resonance_test.dart를 케이던스 픽스처로 갱신하되 테스트를 약화하지 말 것.

## P3 — 세션 상태머신 + 에피소드 채보

> `docs/redesign/tech_design_v1.0.md` §3-3, §3-6을 읽어라. ① SessionPhase 상태머신(intro→build→mission→climax→outro→reverb→freeRun/chain/cooldown)을 새 서비스로 구현하라. reverb(잔향 30초) 판정: CadenceEngine의 GaitState가 결정한다 — running 유지 시 freeRun 자동 전환(멘트 없음), walking 10초 시 cooldown. 화면 조작 요구 금지. ② 채보 JSON 포맷(§3-6)과 ChartPlayer를 구현하고 에피소드 1종 '기차'를 assets에 추가하라(스템은 임시로 기존 pad 에셋 재활용, 정식 스템은 별도 트랙). ③ 전화 수신 시 자동 일시정지→꼭지 재개, 4분 이상 중단 시 부분 완주 처리. run_recovery 경로는 절대 끊지 말 것(CLAUDE.md).

## P4 — 고스트런 3막

> `docs/redesign/product_design_v1.1.md` §3(고스트런)을 읽어라. ① 모든 러닝이 고스트가 되도록 run_service 저장 스키마에 케이던스 타임라인(1초 해상도, delta 압축)과 사연 필드를 추가하라 — 공개 범위 기본 '페이스메이트만', GPS 경로는 기본 비저장. ② GhostEngine: 고스트 파일을 세션 시작 전 다운로드, 경과 시간축으로 재생(내 페이스와 독립), P2의 공명 인터페이스에 두 번째 입력으로 연결 — 시차 공명 성립. ③ 종료 시 상대에게 알림 문서 생성(functions/push.ts 확장 — 발송은 서버만, CLAUDE.md 규칙). ④ 승패·추월 언어를 코드·카피 어디에도 쓰지 말 것: 가까워짐/나란함/멀어짐만.

## P5 — 새 홈 2종 + 온보딩 4장

> 피그마 와이어프레임(https://www.figma.com/design/koizbsGLUZofes4nXNahux 01~07번 화면)과 `docs/redesign/ux_decisions_v1.1.md` §3·§5를 읽어라. ① 온보딩: 여덟 걸음(가입 전 소리 체험) → 데모런(기존 demo_resonance 재활용, '가상의 페이서' 명시) → 레벨 질문 1개 → 초대 제안(건너뛰기 가능, 죄책감 카피 금지). 알림 권한은 첫 완주 직후에 묻는다(CLAUDE.md의 권한 규칙 준수). ② 홈: 레벨에 따라 입문자형(오늘의 8분 전면)/경험자형(자유런 전면) 분기. 카드 3장 구조(오늘의 에피소드/지금 뛰는 중/우리 여정) — us_screen의 여정 로직 재활용. ③ lobby_screen은 이 시점에 삭제하고 진입 경로를 '오늘의 상대 선택'으로 교체(repo_audit 판정 3). 디자인 토큰은 theme.dart의 GoColors 유지 — 나=lime, 상대=coral, 공명=골드 전용 규칙 준수.

## P6 — 완주 후 5분

> `docs/redesign/product_design_v1.1.md` §5를 읽어라. finish_screen을 대체하는 새 플로우: ① 아웃트로(귀에서 착륙 — 도착음은 기존 chime_match 재활용 검토) ② 쿨다운 오디오 디브리핑 + 음성 한 마디 채집(20초 상한, 3회 무응답 시 빈도 자동 하향) ③ 결과 화면 컴포넌트 순서 고정: 오늘의 트랙 ▶(주인공) → 함께 요약 → 여정 → 기록(접힘). 공유 카드는 기존 RepaintBoundary 캡처 경로 재활용(CLAUDE.md 전략 항목). ④ 응원 이월(브리지): 도착한 응원은 푸시로 예고만 하고 재생은 다음 세션 intro에서 — cheers 문서에 queued/bridged 상태 추가.

## P7 — 첫 러닝 릴레이 + 응원 배선

> `docs/redesign/product_design_v1.1.md` §4-3(릴레이)과 §6(소셜 배선)을 읽어라. ① 신규 유저 첫 세션에 최근 첫 러닝 풀에서 |Δspm|≤10 매칭(2분 미만 제외, 익명) — Cloud Function으로. 완주 시 "당신의 첫 8분이 다음 사람의 동반자가 됩니다" + 이후 알림. ② 응원: 수신음 3종(sigHere/sigCheer/sigSlow)을 응원 시그널로 배선 — 달리는 상대의 리듬에 박자 맞춰 삽입. ③ 알림 다이제스트 규칙(동일인 일 3회 묶음, 죄책감 문법 금지).

## P8 — 계측 + 베타 준비

> `docs/redesign/tech_design_v1.0.md` §7 지표 트리를 읽어라. events 컬렉션에 북극성 계측을 심어라: 세션 시작/완주/부분완주, 공명 진입/누적 초, 잔향 분기(freeRun/chain/cooldown), 음성 한 마디 응답 여부, 릴레이 매칭/재방문, 응원 발송/브리지 재생. 대시보드는 만들지 말 것(Firestore 콘솔 쿼리로 충분) — 앱 쪽 계측만. 마지막으로 TODO.md의 심사 준비 항목(PrivacyInfo.xcprivacy 최초 작성 포함)을 점검하고 베타 배포 체크리스트를 갱신하라. TestFlight 업로드는 CEO 승인 후(CLAUDE.md — 밖으로 나가는 것).

---

## 전 프롬프트 공통 금지 (에이전트에게 매번 상기)

- GPS 필터 값(RunFilterConfig) 변경 금지 — 실측 검증값 (CLAUDE.md)
- 순위·리더보드·승패 언어·실패음·상시 배경음 금지
- 러닝 중 화면 조작을 요구하는 UI 금지
- firestore.rules 완화로 권한 에러 "해결" 금지
- 테스트 약화·삭제로 통과 금지
- design/prototype_v2.html 수정 금지 (참고: 새 화면의 디자인 기준은 와이어프레임 + GoColors 토큰. 프로토타입과 충돌 시 docs/redesign이 우선 — P0에서 CLAUDE.md에 명시)
