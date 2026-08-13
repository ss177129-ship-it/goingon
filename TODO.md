# TODO — 작업 과제 (우선순위 순)

## 0. ⚠️ 푸시 알림 — 마지막 검증 한 걸음만 남음 (2026-08-14 기준)

**끝난 것** (전부 검증됨):
- Blaze 플랜, APNs 인증 키(.p8) → Firebase 업로드
- Cloud Functions 4개 배포 (`onFriendRequest`, `onFriendRequestResolved`, `onRunRequest`, `cleanupSessions`)
- App ID에 Push Notifications 활성화, `GoingOn App Store` 프로파일 재발급
- IPA 빌드 + 서명 검증 (`codesign -d --entitlements`로 `aps-environment=production` 직접 확인)
- TestFlight 업로드 + 내부 테스트 그룹 설정

**남은 것 — 이것만 하면 끝:**
- [ ] 폰 TestFlight에서 **GoingOn 0.1.1 (5)** 설치 → 앱 실행 → **알림 권한 "허용"**
- [ ] 토큰 등록 확인: `cd functions && NODE_PATH=./node_modules node ../tools/push-check.js list`
      → 해당 사용자 "기기 1대"로 바뀌면 APNs 설정이 전부 맞은 것
- [ ] 실제 발송: `... push-check.js send <uid>` → **앱을 완전히 종료한 상태**에서 잠금화면에 뜨는지
- [ ] 되면 친구 요청/GO?로 실제 트리거도 확인 (Functions 로그: `firebase functions:log --project goingon-c12f3`)

**2026-08-14 시점 상태: 사용자 7명 전원 `fcmTokens` 0대** — 아직 실기기에서 앱을 켜지 않았음.

### 실기기 관련 제약 (중요)
**케이블이 없어서 개발용 빌드를 못 함.** 개발용 프로비저닝 프로파일은 기기 등록이 필요한데 기기를 연결할 수 없음. 따라서 **실기기 검증은 TestFlight가 유일한 경로**이고, 한 사이클이 20~40분 걸림. 시뮬레이터는 APNs 토큰 자체를 못 받아 푸시 검증이 구조적으로 불가능.

### 서명 설정 (건드리지 말 것)
- Release는 **수동 서명** + `GoingOn App Store` 프로파일. 자동 서명으로 바꾸면 아카이브 단계에서 개발용 프로파일을 요구해 **케이블 없이는 빌드가 아예 안 됨** (한 번 시도했다 되돌림)
- `aps-environment`는 빌드별로 분리: Debug/Profile → `Runner.entitlements`(development), Release → `RunnerRelease.entitlements`(production). 섞이면 앱은 정상인데 알림만 조용히 안 옴
- 같은 이름의 프로파일이 맥에 두 개 이상 설치돼 있으면 export가 엉뚱한 걸 집음. 재발급 후엔 옛것을 지울 것


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
