# TODO — 작업 과제 (우선순위 순)

## 0. ⚠️ 푸시 알림 — 코드는 끝, 유저 수동 작업 3가지 남음

Cloud Functions와 앱 코드는 작성·검증 완료. 아래 셋은 콘솔/Xcode 작업이라 AI가 대신 못 함.

- [ ] **Blaze(종량제) 플랜 업그레이드** — https://console.firebase.google.com/project/goingon-c12f3/usage/details
      Functions 배포의 전제 조건(카드 등록). 무료 한도가 실사용의 수백 배라 실제 요금은 사실상 0원이지만, 업그레이드 직후 **예산 알림(예: 월 5천원)을 반드시 설정**할 것
- [ ] **APNs 인증키(.p8) 발급 → Firebase 업로드**
      Apple Developer → Certificates, Identifiers & Profiles → Keys → `+` → Apple Push Notifications service(APNs) 체크 → 생성 → .p8 다운로드(**한 번만 받을 수 있음**)
      → Firebase 콘솔 → 프로젝트 설정 → Cloud Messaging → Apple 앱 구성 → APNs 인증 키 업로드 (Key ID, Team ID 함께 입력)
- [ ] **Xcode에서 Push Notifications capability 추가**
      Runner 타겟 → Signing & Capabilities → `+ Capability` → Push Notifications.
      (직접 파일을 고치면 코드 서명이 깨질 수 있어 반드시 Xcode UI로 할 것. 변경된 `Runner.entitlements`·`project.pbxproj`를 커밋에 포함)

셋을 마친 뒤: `firebase deploy --only functions --project goingon-c12f3`

**검증은 실기기 필요** — 시뮬레이터는 APNs 토큰을 못 받아 푸시가 오지 않음(앱은 정상 동작하고 토큰 등록만 조용히 건너뜀).


작업 지시는 "TODO.md N번 해줘" 형식으로. 모든 과제는 CLAUDE.md의 **완료 기준**을 통과해야 완료이며, 완료 시 아래 "완료된 과제"로 이동.

## 1. 러닝 복구 플로우 검증 (2026-08-13 구현됨 — 검증 필요)

러닝 중 앱 강제 종료 시 기록 복구 기능이 방금 추가됨 (`run_recovery.dart`, run_screen 5초 저장, root_screen 복구 제안). 시뮬레이터에서 검증할 것:

**전제: 데모가 아닌 러닝은 상대의 준비완료가 필요하므로 혼자 재현 불가.** 시뮬레이터 2대(iPhone 16e + 아무 기종)에 테스트 계정 2개로 진행하거나, 실기기 테스트 단계(7번)로 미뤄도 됨.

- [ ] 데모 아닌 러닝 시작 → 10초 후 앱 강제 종료 → 재실행 → "마치지 못한 러닝이 있어요" 다이얼로그 확인
- [ ] "기록 저장" → FinishScreen 진입 + Firestore results 반영 확인
- [ ] "버리기" → 다이얼로그 재등장 없음 확인
- [ ] 정상 완료한 러닝 후에는 다이얼로그가 뜨지 않는 것 확인

## 2. UI 간격/폴리시 전면 정리

전 화면을 `design/prototype_v2.html`과 나란히 비교하며 패딩·간격·정렬·크기를 맞출 것. 유저 피드백: "전체적으로 간격이나 이런 것들이 깔끔하지 않다"

- [ ] 화면별로 스크린샷 → 프로토타입 비교 → 차이 목록 보고 → 수정 순서로 진행

## 3. 햅틱 확장

현재 롱프레스 제스처(보고싶어)에만 적용됨. 확장:

- [ ] 로비 카운트다운(3-2-1: light, 출발: heavy), 러닝 종료 확정, 제스처 수신 시
- [ ] 과하지 않게 — 각 순간에 한 번, 패턴은 순간의 무게에 비례

## 4. Live Activities (잠금화면 / Dynamic Island)

- [ ] `live_activities` 패키지 + Swift 위젯 익스텐션 추가 (Xcode에서 타겟 생성 필요 — 절차를 단계별로 안내할 것)
- [ ] 표시 데이터: 경과 시간, 내 거리, 상대 이름, 앱 컬러(lime/coral) 반영
- [ ] 러닝 시작 시 시작, 종료/취소 시 반드시 종료 처리 (좀비 Live Activity 방지)

## 5. 기술 부채 (TECH_REVIEW.md 2026-07-12 지적 사항 중 잔여)

- [ ] `withOpacity` → `withValues` 일괄 치환 (57곳, 기계적)
- [ ] friendsStream 이중 구독 정리 — RootScreen에서 한 번만 구독해 홈/우리 탭에 내려주기
- [ ] 세션 상태 전이(waiting→ready→running→finished)에 대한 유닛 테스트 작성

## 6. 심사 준비

- [x] ~~차단~~ — 요청·수락 모델과 함께 구현됨(홈 롱프레스 → 차단, 설정 → 차단 목록에서 해제)
- [ ] **설정에 신고 연락처(이메일) 노출** — 차단은 끝났고 신고 경로만 남음. 참고: 유저 간 자유 입력 텍스트는 이름·아이디뿐이고 GO? 거절 메시지는 3개 중 선택식이라, 가이드라인 1.2의 초점은 유해 텍스트 필터링이 아니라 **동의 없는 연락 차단**임(그건 요청·수락 + 차단으로 대응됨)
- [ ] `PrivacyInfo.xcprivacy` 작성 (위치·유저 데이터 수집 명시)
- [ ] 위치 권한 설명 문구(NSLocationAlwaysAndWhenInUseUsageDescription 등) 심사 기준으로 재작성
- [ ] 심사관용 데모 모드 안내를 App Review 노트에 쓸 문구 초안
- [ ] 두 명이 실제로 함께 달리는 30초 시연 영상 촬영(실전 테스트 때 화면 녹화) → App Review 노트에 링크 첨부

## 7. 출시 검증

- [ ] 실기기 GPS 테스트 (실외 1km 이상, 폰 잠근 상태 + 강제 종료 복구 포함)
- [ ] 친구 1명과 실전 테스트
- [ ] TestFlight 배포

---

## 완료된 과제

- [x] 우리 탭 구현 (us_screen.dart)
- [x] 설정 탭 구현 (settings_screen.dart)
- [x] Crashlytics 도입 (main.dart 삼중 캐치 + 전 서비스 recordError)
- [x] 러닝 복구 구현 (run_recovery.dart — 검증은 1번 과제)
- [x] 2026-08-13 안정성 감사: 시간 계산(타임스탬프 차이 ✓), 집계(트랜잭션+증분 ✓), GPS 필터(30m/10m·s ✓) — 문제 없음 확인
- [x] 폰트 번들 전환(런타임 다운로드 제거) + `flutter analyze` 정상화(8,536→124, build/ 제외)
- [x] 데모 복구 버그 — 데모 러닝이 RunRecovery에 저장돼 심사관이 무한 다이얼로그를 밟을 수 있던 문제. 저장·복구 양쪽 가드 + 회귀 테스트 6개
- [x] **친구 연결을 '요청 → 수락' 모델로 전환** + 차단. 보안 규칙에서 friends 직접 쓰기를 봉쇄함

## 검증이 남은 것 (2인 필요 — 실기기/시뮬레이터 2대)

요청·수락 흐름은 계정 2개가 있어야 끝까지 볼 수 있음. 7번 실전 테스트 때 함께 확인:
- [ ] A가 요청 → B 홈 상단에 "나에게 온 요청" 카드 → 수락 → 양쪽 친구 목록에 반영
- [ ] 거절이 조용히 처리되는지(A에게 알림 없음), A가 재요청 가능한지
- [ ] 차단 후 상대가 나를 검색하면 "그런 아이디를 쓰는 사람이 없어요"가 나오는지
- [ ] 차단 해제 후 다시 요청→수락으로 연결되는지
