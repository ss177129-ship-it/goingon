# GoingOn (고잉온)

멀리 있는 친구·연인과 **같은 시간에 함께 달리는** iOS 앱. 핵심 철학: **"기록이 아니라 관계"** — Strava식 퍼포먼스 경쟁이 아니라, 떨어져 있는 두 사람이 발을 맞추는 감각을 판다. 창업자(이찬웅)는 비전공자 1인 개발.

**출시 목표일은 정해두지 않는다.** "일정이 급하다"를 이유로 완료 기준이나 심사 준비 항목을 생략하지 말 것.

**작업 과제는 `TODO.md`에.** 이 파일은 변하지 않는 규칙과, 깨뜨려봐야만 알 수 있는 사실만 담는다.

## 진행 방식

**기본은 묻지 말고 진행한다.** 판단이 서면 하고, 왜 그렇게 했는지와 버린 대안을 결과와 함께 보고한다. 매 단계 승인을 받으려 멈추지 말 것.

다만 아래는 되돌리기가 비싸거나 밖으로 나가는 일이라 **반드시 먼저 물을 것**:

- **GPS 필터 값 변경** — 실측으로 검증된 값이고, 틀리면 사용자 기록이 조용히 망가진다 (아래 참조)
- **배포 타깃 되돌리기** — 설치 가능한 기기가 줄어든다
- **"의도된 설계 결정"과 충돌하는 구현** — 이미 내린 결정을 뒤집는 일이다
- **밖으로 나가는 것** — TestFlight 업로드, Firebase 배포, 스토어 제출
- **되돌릴 수 없는 삭제** — 계정, 저장소 데이터, 커밋 이력

그 외(라이브러리 도입, 네이티브 API, 구조 변경 등)는 판단해서 진행하고 결과에서 설명한다.

**작업 하나가 끝나면 그 자리에서 커밋한다.** 완료 기준을 통과한 시점이 곧 커밋 시점이다.

## 디자인 기준 (가장 중요)

`design/prototype_v2.html` 이 **디자인의 단일 기준**. 화면 작업 전 해당 화면의 마크업/CSS를 열어 간격·라운딩·타이포를 그대로 따를 것.

**사운드 작업은 `docs/sound_ux_v1.md`가 단일 기준.** 사운드·햅틱·브리핑 관련 코드를 만지기 전에 반드시 읽을 것. 문서의 금지 목록(실패음, 상시 배경음 등)은 협상 불가. 세션 화면 개편 프롬프트는 `docs/session_ui_prompts.md`에 있다.

**프로토타입과 이 파일이 충돌하면 이 파일이 우선.** 프로토타입에 이모지가 있어도 쓰지 않고, GoingOn+ 구독 항목이 있어도 구현하지 않는다.

- 색: paper `#F0EAE0`, canvas `#EBE4D6`, lime `#C5E040`, limeDark `#6A9810`, coral `#F05840`, coralDark `#B03020`, ink `#1A1A16`, resonance(골드) `#D4A84B`, amber `#D97706`, mid `#78746E`, dim `#B0ACA6`, line `rgba(26,26,22,.09)` → `lib/theme.dart`의 `GoColors`
- 타이포: 타이틀/숫자 = Instrument Serif *italic* (`GoTheme.serif()`), 본문 = Noto Sans KR
- 컬러 의미: 나 = lime, 상대 = coral, **공명 = 골드(전용)**. 절대 섞지 말 것. kcal 등 일반 지표는 ink/mid — 골드가 "우리 둘이 만든 것"이라는 희소성을 가지려면 공명 외에는 쓰지 않는다 (2026-08-16 결정, 이전 규칙은 공명/kcal 공용이었음)
- 카드 라운딩 18~22px, 화면 좌우 여백 22~28px, 섹션 라벨은 11px/600/letterSpacing 1.2/dim

### 폰트 — 번들이 유일한 안전망

폰트는 `assets/fonts/`에 **번들**되어 있고, 패밀리 이름은 `pubspec.yaml`의 `fonts:`와 `lib/theme.dart`의 `_serifFamily`/`_sansFamily`가 일치해야 한다.

**이 환경에는 시스템 폰트 폴백이 아예 작동하지 않는다.** 2026-08-16에 세 조건을 나란히 렌더해 확인함 — `fontFamily`를 지정하지 않으면 이모지는 물론 **한글까지 두부(?)로 깨진다.** 한글이 나오는 건 폴백 덕분이 아니라 NotoSansKR을 번들해 이름으로 직접 지정했기 때문이다. 여기서 따라오는 것들:

- **Instrument Serif에는 한글 글리프가 없다.** `GoTheme.serif()`가 `fontFamilyFallback`으로 NotoSansKR을 물고 있어야 하며, 이 연결을 끊으면 세리프 타이틀의 한글이 전부 깨진다 (실제로 한 번 깨뜨렸다 복구함)
- **이모지 사용 금지 — Material Icons 또는 텍스트만.** `fontFamilyFallback`에 `Apple Color Emoji` 같은 시스템 폰트 이름을 넣는 방법은 **두 번 실패했으니 다시 시도하지 말 것**
- **번들 폰트에 없는 글리프는 안전망이 없다.** 새 문자 집합(다른 언어, 특수 기호)을 도입하면 조용히 두부가 되므로 반드시 시뮬레이터에서 눈으로 확인할 것
- **기하 기호(▲ ● ★)는 정상 렌더된다** — 이모지가 아니라 NotoSansKR에 든 일반 글리프
- **Flutter가 그리지 않는 문자열은 예외** — 공유 시트 텍스트, 푸시 알림 본문 등은 받는 쪽이 시스템 폰트로 렌더하므로 이모지를 써도 된다 (`finish_screen.dart`의 공유 문구가 이 경우)
- 굳이 이모지가 필요하면 남은 길은 이모지 폰트를 함께 번들하는 것뿐인데, IPA가 30%가량 커진다. 지금은 비용이 이득보다 크다는 판단

## 아키텍처

Flutter + Firebase(Apple 로그인, Firestore, Storage, Cloud Messaging) + Cloud Functions(`functions/`, TypeScript). 화면·서비스 구성은 `lib/screens/`, `lib/services/`를 직접 읽을 것. 아래는 **코드만 봐서는 모르는 함정들**이다.

### Cloud Functions
- Functions는 **푸시 발송 + 세션 정리**만 담당. 앱 로직을 서버로 옮기지 말 것 — 읽기/쓰기는 계속 클라이언트가 Firestore와 직접 한다
- Firestore가 `nam5`(미국)라 **트리거는 us-central1**이어야 함 (`setGlobalOptions`)
- `maxInstances: 10`은 무한 루프가 나도 청구서가 터지지 않게 하는 안전장치. 풀지 말 것
- 배포: `firebase deploy --only functions --project goingon-c12f3` (Blaze 필수)

### Firestore·Storage
- **친구 요청은 문서의 존재 자체가 "대기 중"**이다. status 필드가 없고 수락·거절·취소가 전부 삭제. id가 `보낸사람_받는사람`이라 중복 요청이 구조적으로 불가능하고 복합 인덱스도 필요 없다
- 존재하지 않는 요청 문서를 배치에서 `delete`하면 규칙이 `resource`를 못 읽어 **권한 거부**가 난다 — 반드시 `exists` 확인 후 배치에 넣을 것
- 세션은 hostId/guestId **직접 비교**. `in participants`를 쓰면 쿼리 권한 거부가 난다
- 세션 update는 **필드 허용 목록** 방식이라, 새 필드를 쓰려면 규칙에도 추가해야 한다. hostId/guestId/createdAt은 생성 후 불변이고 ready/late/joined/results 맵은 자기 uid 항목만 쓸 수 있다
- **친구 추가는 대기 중인 요청이 실제로 존재할 때만 통과한다.** `friends`에 직접 쓰는 코드를 새로 만들지 말 것 — 규칙이 거부한다
- 프로필 사진은 **Storage** `avatars/{uid}.jpg`에 두고 문서에는 주소(`photoUrl`)만. 이미지를 문서에 넣지 말 것 — 친구 목록이 실시간 스트림이라 매 스냅샷마다 따라온다. 덮어쓸 때마다 다운로드 토큰이 새로 발급돼 주소가 바뀌므로 **업로드 후 `photoUrl` 갱신을 반드시 함께** 할 것
- 규칙·인덱스는 소스가 기준: `firebase deploy --only firestore,storage --project goingon-c12f3` (배포 전 `--dry-run`)

## 기술 원칙

- **시간 계산**: 경과 시간은 Timer 틱 누적이 아니라 **타임스탬프 차이**로. iOS는 백그라운드에서 Timer를 멈추므로 틱 누적은 반드시 틀린다. 세션의 공동 출발 시각(`startedAt`)은 serverTimestamp이며 먼저 찍힌 값을 유지한다
- **세션 복구**: 러닝 중 앱이 죽어도 기록이 살아남아야 한다. `run_recovery.dart`가 5초마다 로컬 스냅샷을 남기고 RootScreen이 발견해 마무리를 제안한다. 이 경로를 끊지 말 것
- **GPS 필터** (`run_accumulator.dart`의 `RunFilterConfig`): accuracy 30m 초과 무시, 두 지점 간 속도 10m/s 초과는 이상치(dt≤0이면 절대 거리 50m), distanceFilter 5m. **이 네 값은 실측으로 검증됐고 변경은 승인 필요** — 바꾸면 실내 드리프트가 재발한다. 감사 수정으로 켠 필터들(fix 나이·음수 정확도·기준점 유지·정확도 비례 최소 이동)은 이 네 값을 건드리지 않고 추가된 것이며, `RunFilterConfig.legacy`가 수정 이전 동작을 보존해 회귀 테스트가 차이를 지킨다
- **집계 필드**: `users`의 monthKm/totalRuns/weekStreak는 반드시 트랜잭션(`_bumpMonthlyStats`) 경유. 재제출 시 이중 집계 방지(isFirstSubmit)를 우회하는 직접 쓰기 금지
- **username 변경**: `usernames/{old}` 삭제 + `usernames/{new}` 생성 + `users/{uid}` 갱신은 **하나의 트랜잭션**으로. 실패하면 아이디가 유령으로 남거나 탈취될 수 있다
- **상태 관리**: StatefulWidget + setState + Stream 구독이 기존 패턴. 다른 패턴이 필요하면 도입하되 왜 바꿨는지 설명할 것
- **에러 보고**: 삼중 캐치(FlutterError.onError + PlatformDispatcher.onError + runZonedGuarded)로 Crashlytics 연동됨. 서비스 호출 실패는 `recordError(fatal: false)` + 유저 안내가 관례
- **권한 추가**: Info.plist 설명 문구 + `PrivacyInfo.xcprivacy` 갱신을 한 세트로 (xcprivacy는 **아직 없음** — 최초 작성은 TODO 심사 준비 항목)
- **푸시**: 발송은 서버(`functions/src/push.ts`)만, 앱은 토큰 등록·탭 처리만. 토큰은 `users/{uid}.fcmTokens` 배열이고 죽은 토큰은 서버가 지운다. 알림 권한은 첫 실행이 아니라 **프로필이 준비된 뒤(RootScreen 진입)** 묻는다 — iOS는 한 번 거절당하면 다시 못 묻는다
- `UIBackgroundModes`에 `remote-notification`을 **넣지 않았다.** 알림 방식만 쓰므로 불필요하고, 안 쓰는 배경 모드 선언은 심사에서 지적받는다. 무음 데이터 메시지나 Live Activity 원격 갱신을 쓰게 되면 그때 추가할 것

## Apple 네이티브 통합

완성도 있는 iOS 네이티브 경험이 목표. 검증된 플러그인 우선, 없으면 `ios/Runner`에 Swift + MethodChannel.

- **배포 타깃은 iOS 26.0** (2026-08-16에 13.0에서 올림). 타깃을 얼리어답터로 좁히고 최신 API를 쓰기로 한 결정. `@available` 분기나 버전 체크를 넣지 말 것 — 불필요한 복잡도다
- **`HKWorkoutSession`은 아이폰에서 백그라운드 실행을 보장하지 않는다** (2026-08-16 확인). API는 iOS 26부터 아이폰에서 쓸 수 있는 게 맞지만(SDK 헤더에서 `initWithHealthStore:configuration:error:`와 `HKLiveWorkoutBuilder`가 `API_AVAILABLE(ios(26.0))`로 확인됨), **워치와 달리 아이폰 세션은 "시스템의 통상적인 포그라운드/백그라운드 생명주기"를 따른다.** 즉 지금의 위치 배경 모드보다 나은 실행 보장을 주지 않는다
  - 아이폰 세션이 주는 것은 **잠금 상태에서도 건강 데이터에 접근할 권한**(첫 세션 시작 시 시스템 프롬프트)이지 실행 보장이 아니다. 애플이 잠금화면 대책으로 권하는 것은 **Live Activities**다
  - 따라서 "러닝 중 앱이 죽어 기록이 날아가는" 문제의 해법으로는 부적절하다. 그 문제는 배경 스냅샷 저장(감사 #15)·GPS 실패 시 기록 보존(#7)으로 훨씬 싸게 다룰 것
  - HealthKit은 건강 앱 연동·경로 저장·kcal 정확도를 위해서는 여전히 의미가 있으나, 권한이 거부될 수 있어 위치 기반 경로는 어차피 폴백으로 남는다 — 교체가 아니라 이중화다
- capability/entitlement 추가는 Xcode에서 수행하고, 변경된 파일(Runner.entitlements, RunnerRelease.entitlements, Info.plist, project.pbxproj)을 커밋에 포함할 것
- **승인된 통합**: 햅틱(HapticFeedback), Live Activities(ActivityKit — 잠금화면/Dynamic Island)

## 의도된 설계 결정 (바꾸지 말 것)

- **러닝 중 실시간 동기화 없음** — 함께 시작하고, 끝나면 합산. 라이브 합산은 v1.1(개발 난이도의 절반이 여기 있어 의도적으로 잘랐음). 단, 제스처 신호(`gesture` 필드 하나 덮어쓰기)는 순간 이벤트라 이 원칙과 무관하다
- **백그라운드 위치 추적 있음** — Always 권한을 받았을 때만 `allowBackgroundLocationUpdates`를 켠다. When In Use만 있는데 켜면 iOS가 앱을 강제 종료시킨다. Always를 못 받으면 wakelock으로 화면을 켜두고 사용자에게 알린다. 심사 리젝 가능성을 인지하고 진행 중
- **Apple 로그인 필수 — 익명 로그인 없음.** 모든 가입은 Apple 인증을 거쳐 항상 `NicknameScreen`으로. Google도 연동 완료, 카카오는 v1.1
- **데모 모드** (`demo: true`, lobby/run/finish 관통) — 가상 파트너 '지수'와 전체 흐름 체험. **Apple 심사관용이므로 절대 제거 금지** (핵심 기능이 2인 동시 러닝이라 심사관이 혼자 체험할 유일한 수단). 친구 0명·기기 1대·권한 없음 상태에서도 반드시 진입 가능해야 하고, 진입점은 설정('혼자 미리 체험하기')에 **항상 유지**. 데모 러닝은 RunRecovery에 저장하지 않는다
- **수익화 UI 출시 전 노출 금지** — 결제 관련 화면·버튼은 프로토타입에 있어도 구현하지 않는다
- **친구 연결은 '요청 → 수락' 모델** — 아이디로 찾아 요청을 보내고 상대가 수락해야 연결된다. 아이디를 아는 사람이 곧 연결 권한이 되는 구조는 폐기함
  - **차단은 필수** — 요청·수락만으로는 반복 요청을 못 막는다. 차단된 상대는 요청 전송·검색 노출·세션 생성이 모두 거부되며 보안 규칙에서도 막는다
  - 거절은 **상대에게 알리지 않는다**(조용히 사라짐). 거절 통보는 상처를 주고 재요청을 유발한다
  - 자유 입력 텍스트는 이름·아이디뿐이다(GO? 거절 메시지는 선택식). 즉 심사 대응의 초점은 유해 텍스트 필터링이 아니라 **동의 없는 연락 차단**이다
- **완료 화면 공유 카드** — RepaintBoundary 캡처 → share_plus. 셋로그식 성장 엔진이라 완성도 유지가 전략적으로 중요
- **GO? 요청 TTL 30분** — 같은 상대에게 살아 있는 요청이 있으면 재사용(중복 세션 방지)

## 완료 기준 (이게 전부 통과하기 전엔 "완료"라고 말하지 말 것)

1. `flutter analyze` — 에러 0, 새로 추가된 워닝 0
2. `flutter test` — 전부 통과 (테스트를 통과시키려고 테스트를 약화·삭제하는 것 금지)
3. 빌드가 실제로 됨 — 시뮬레이터에서 앱이 크래시 없이 해당 화면까지 도달
4. 화면 작업이면: `xcrun simctl io booted screenshot /tmp/check.png`로 스크린샷을 찍어 직접 보고 prototype_v2.html과 비교한 결과를 보고할 것 ("확인했음" 한 줄 금지 — 무엇이 일치하고 무엇이 다른지 명시)
5. 실패하면: 원인 분석 → 수정 → 1번부터 다시. 우회 금지

## 금지 사항

- firestore.rules를 느슨하게 풀어서 권한 에러를 "해결"하지 말 것 — 규칙이 거부하면 쿼리가 틀린 것
- `design/prototype_v2.html` 수정 금지 (디자인 기준이지 작업 대상이 아님)
- 이 파일에 작업 과제를 추가하지 말 것 — 과제는 TODO.md에
