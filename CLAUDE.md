# GoingOn (고잉온)

멀리 있는 친구·연인과 **같은 시간에 함께 달리는** iOS 앱. 핵심 철학: **"기록이 아니라 관계"** — Strava식 퍼포먼스 경쟁이 아니라, 떨어져 있는 두 사람이 발을 맞추는 감각을 판다. 창업자(이찬웅)는 비전공자 1인 개발.

**출시 목표일은 정해두지 않는다.** 남은 일정은 `TODO.md`의 우선순위가 기준이며, "일정이 급하다"를 이유로 완료 기준이나 심사 준비 항목을 생략하지 말 것.

**작업 과제는 `TODO.md` 참조.** 이 파일(CLAUDE.md)은 변하지 않는 규칙만 담는다 — 여기에 할 일을 추가하지 말 것.

## 디자인 기준 (가장 중요)

`design/prototype_v2.html` 이 **디자인의 단일 기준(source of truth)**. 화면 작업 전 반드시 이 파일을 열어 해당 화면의 마크업/CSS를 확인하고 간격·라운딩·타이포를 그대로 따를 것.

**단, 프로토타입과 이 파일의 규칙이 충돌하면 이 파일이 우선.** 대표 사례: 프로토타입에 이모지가 있어도 쓰지 않음(아래 이모지 규칙), 프로토타입 설정 화면에 GoingOn+ 구독 항목이 있어도 구현하지 않음(수익화는 출시 후 — "의도된 설계 결정" 참조).

- 색: paper `#F0EAE0`, canvas `#EBE4D6`, lime `#C5E040`, limeDark `#6A9810`, coral `#F05840`, coralDark `#B03020`, ink `#1A1A16`, resonance(골드) `#D4A84B`, amber `#D97706`, mid `#78746E`, dim `#B0ACA6`, line `rgba(26,26,22,.09)` → `lib/theme.dart`의 `GoColors`
- 타이포: 타이틀/숫자 = Instrument Serif *italic* (`GoTheme.serif()`), 본문 = Noto Sans KR
- 컬러 의미: 나 = lime, 상대 = coral, 공명/kcal = 골드. 절대 섞지 말 것
- 카드 라운딩 18~22px, 화면 좌우 여백 22~28px, 섹션 라벨은 11px/600/letterSpacing 1.2/dim
- 폰트는 `assets/fonts/`에 **번들**되어 있음(런타임 다운로드 아님). 패밀리 이름은 `pubspec.yaml`의 `fonts:`와 `lib/theme.dart`의 `_serifFamily`/`_sansFamily`가 일치해야 함
  - **Instrument Serif에는 한글 글리프가 없음.** 그래서 `GoTheme.serif()`는 `fontFamilyFallback`으로 NotoSansKR을 반드시 물고 있어야 하고, 이 연결을 끊으면 세리프 타이틀의 한글이 전부 ?(두부)로 깨짐 — 실제로 한 번 깨뜨렸다가 복구함
- **이모지 글리프 사용 금지** — 2026-08-13 시뮬레이터에서 직접 검증함: `fontFamilyFallback`에 `Apple Color Emoji`를 넣어도 **본문·세리프 양쪽 모두 ?(두부)로 깨짐**. 한글 폴백과는 다른 원인임(한글은 NotoSansKR 폴백으로 해결됨). 두부 모양이 특정 폰트의 .notdef 글리프라, 폴백 사슬이 이모지 코드포인트에서 시스템 폰트로 넘어가기 전에 멈추는 것으로 보임 — 다시 시도할 사람을 위한 단서. **Material Icons 또는 텍스트만 사용**
  - **2026-08-16 재검증: 배포 타깃을 iOS 26으로 올린 뒤에도 동일하게 깨짐.** 이건 iOS 버전 제약이 아니라 Flutter 폰트 폴백 문제라 최소 버전 인상으로 풀리지 않는다. 같은 화면에서 대조군(`가 A 1 ▲`)은 정상 렌더됐으므로 폰트 설정 자체는 멀쩡하다. **세 번째로 시도하지 말 것**
  - 다만 **기하 기호(▲ ● ★ 등)는 이모지가 아니라 일반 글리프라 정상 렌더된다.** 프로토타입의 상태바 `▲▲` 같은 표현은 그대로 쓸 수 있음

## 아키텍처

- Flutter + Firebase (Apple 로그인, Firestore, Cloud Messaging) + **Cloud Functions**(`functions/`, TypeScript)
  - "백엔드 서버 없음" 원칙은 2026-08-13 폐기함 — 푸시는 클라이언트끼리 못 보내므로 서버가 반드시 필요. 서버리스라 관리 부담은 작고, 무료 한도(월 200만 호출) 대비 실사용은 수천 건 수준
  - Functions는 **푸시 발송 + 세션 정리**만 담당. 앱 로직을 서버로 옮기지 말 것 — 읽기/쓰기는 계속 클라이언트가 Firestore와 직접
  - Firestore가 `nam5`(미국)에 있어 **Firestore 트리거는 us-central1**이어야 함. `setGlobalOptions`에 지정돼 있음
  - `maxInstances: 10` 상한이 걸려 있음 — 무한 루프가 생겨도 청구서가 터지지 않게 하는 안전장치. 풀지 말 것
  - 배포: `firebase deploy --only functions --project goingon-c12f3` (Blaze 플랜 필수)
- `lib/screens/`: main.dart(스플래시 게이트) → login(Apple 로그인) → nickname(닉네임 설정, 로그인 성공 후 항상 거침) → root(홈/우리/설정 3탭 셸) → invite(초대코드) → lobby(준비단계) → run(GPS) → finish(합산+공유카드)
- `lib/services/`: auth(Apple/Google 로그인+프로필 생성), friend(아이디 검색 → 확인 → 양방향 연결/삭제), run(세션 생명주기), location(GPS+보정), run_recovery(러닝 중 강제 종료 대비 로컬 스냅샷), active_run_guard, story_labels, week_key
- Firestore: `users/{uid}` {name, username, photoUrl?, friends[], blocked[], monthKey, monthKm, totalRuns, lastRunWeek, weekStreak}, `usernames/{username}` {uid}, `friendRequests/{fromUid}_{toUid}` {fromUid, toUid, createdAt}, `sessions/{id}` {hostId, guestId, participants, status: waiting|ready|running|finished|cancelled, ready{}, joined{}, late{}, gesture{}, results{uid:{seconds,km,kcal,mood}}}
  - **친구 요청은 문서의 존재 자체가 "대기 중"**임 — status 필드가 없고 수락·거절·취소가 전부 삭제. id가 `보낸사람_받는사람`으로 고정이라 중복 요청이 구조적으로 불가능하고, 받은 요청 조회는 `toUid` 단일 조건이라 복합 인덱스도 필요 없음
  - 존재하지 않는 요청 문서를 배치에서 `delete`하면 규칙이 `resource`를 못 읽어 **권한 거부**가 남 — 반드시 `exists` 확인 후 배치에 넣을 것
- 프로필 사진은 **Firebase Storage** `avatars/{uid}.jpg`에 두고 Firestore에는 주소(`photoUrl`)만 저장 (`avatar_service.dart`). 이미지를 문서에 직접 넣지 말 것 — 친구 목록이 실시간 스트림이라 매 스냅샷마다 따라옴. 파일 이름이 uid로 고정이라 사진을 바꾸면 항상 덮어씀(고아 파일 없음). 덮어쓸 때마다 다운로드 토큰이 새로 발급돼 주소가 바뀌므로 업로드 후 `photoUrl` 갱신을 반드시 함께 할 것
- 보안 규칙: `firestore.rules` + `storage.rules`, 복합 인덱스: `firestore.indexes.json` — 셋 다 소스가 기준이고 `firebase deploy --only firestore,storage --project goingon-c12f3`로 배포. 배포 전 `--dry-run`으로 규칙 컴파일 확인할 것
  - 세션은 hostId/guestId 직접 비교 (in participants 쓰면 쿼리 권한 거부남). `participants` 필드는 남아 있지만 읽는 곳이 없음
  - 세션 update는 필드 허용 목록 방식 — hostId/guestId/createdAt은 생성 후 불변이고, ready/late/joined/results 맵은 자기 uid 항목만 쓸 수 있음. 새 필드를 쓰려면 규칙의 허용 목록에도 추가해야 함
  - **친구 추가는 "대기 중인 요청이 실제로 존재할 때"만 통과함** (내 문서·상대 문서 양쪽 모두). 수락 배치에서 요청 문서를 함께 지워도 규칙은 배치 이전 상태를 보므로 `exists()`가 참임. `friends`에 직접 쓰는 코드를 새로 만들지 말 것 — 규칙이 거부함
  - 차단은 `users/{uid}.blocked`. 차단은 친구 관계를 동시에 끊어야 해서 `blocked`+`friends`를 같이 바꾸는 것만 허용되고, 그 경로에서 friends는 줄어들기만 가능

## 기술 원칙 (모든 구현이 따라야 함)

- **시간 계산**: 경과 시간은 Timer 틱 누적이 아니라 **타임스탬프 차이(now - startedAt)**로 계산 (run_screen에 이미 구현됨 — 이 방식을 유지할 것). iOS는 백그라운드에서 Timer를 정지시키므로 틱 누적은 반드시 틀린다. 세션의 공동 출발 시각(`startedAt`)은 serverTimestamp이며 먼저 찍힌 값을 유지함
- **세션 복구**: 러닝 중 앱이 죽어도 기록이 살아남아야 함. `run_recovery.dart`가 러닝 중 5초마다 스냅샷을 로컬 저장하고, RootScreen 진입 시 발견하면 기록 마무리를 제안함. 이 경로를 끊지 말 것. 24시간 넘게 running인 세션은 사실상 종료로 간주(run_service.finishedSessionsWith와 기준 공유)
- **GPS 필터** (location_service.dart — 검증된 값이므로 **유저 승인 없이 변경 금지**): accuracy 30m 초과 무시, 두 지점 간 속도 10m/s 초과 시 이상치로 버림(dt≤0이면 절대 거리 50m 기준), distanceFilter 5m. 이 기준을 바꾸면 실내 드리프트(가만히 있어도 거리 증가)가 재발할 수 있음
- **집계 필드**: `users`의 monthKm/totalRuns/weekStreak 갱신은 반드시 트랜잭션(`_bumpMonthlyStats`) 경유. 결과 재제출 시 이중 집계 방지(isFirstSubmit)가 걸려 있음 — 이 구조를 우회하는 직접 쓰기 금지
- **상태 관리**: StatefulWidget + setState + Stream 구독이 기존 패턴. 새 상태 관리 라이브러리/패턴 도입은 유저 승인 후에만
- **에러 보고**: 삼중 캐치(FlutterError.onError + PlatformDispatcher.onError + runZonedGuarded)로 Crashlytics 연동 완료. 서비스 호출 실패는 `recordError(fatal: false)` + 유저 안내가 기존 관례 — 새 코드도 따를 것
- **username 변경**: `usernames/{old}` 삭제 + `usernames/{new}` 생성 + `users/{uid}` 갱신은 반드시 **하나의 트랜잭션**으로. 실패 시 아이디가 유령으로 남거나 탈취될 수 있음
- **권한 추가**: Info.plist 설명 문구 + `PrivacyInfo.xcprivacy` 갱신을 항상 한 세트로 처리 (xcprivacy는 **아직 없음** — 최초 작성은 TODO 심사 준비 항목)
- **푸시**: 발송은 서버(`functions/src/push.ts`)만, 앱은 토큰 등록·알림 탭 처리만 함. 토큰은 `users/{uid}.fcmTokens` 배열(기기 여러 대·재설치 대비)이고 죽은 토큰은 발송 시점에 서버가 지움. 알림 권한은 앱 첫 실행이 아니라 **프로필이 준비된 뒤(RootScreen 진입)** 물음 — iOS는 한 번 거절당하면 다시 못 물음
  - `UIBackgroundModes`에 `remote-notification`을 **넣지 않았음.** 알림(alert) 방식만 쓰므로 불필요하고, 안 쓰는 배경 모드 선언은 심사에서 지적받을 수 있음. 나중에 무음 데이터 메시지나 Live Activity 원격 갱신을 쓰게 되면 그때 추가할 것

## Apple 네이티브 통합 방침

완성도 있는 iOS 네이티브 경험이 목표. 네이티브 기능은 검증된 플러그인 우선, 없으면 `ios/Runner`에 Swift + MethodChannel로 구현.

- **배포 타깃은 iOS 26.0** (2026-08-16에 13.0에서 올림). 타깃 사용자를 얼리어답터로 좁히고 최신 API를 쓰기로 한 결정이며, 그 아래 버전은 설치 자체가 불가능함. 되돌리려면 유저 승인 필요
  - 이 덕분에 **`HKWorkoutSession`을 아이폰에서 쓸 수 있음** — 워치 없이도 OS가 보장하는 백그라운드 실행을 얻는 경로라, "러닝 중 앱이 죽어 기록이 날아가는" 문제의 근본 해법이 열렸음 (GPS 감사 I-1)
  - 새 API를 쓸 때 `@available` 분기나 버전 체크를 넣지 말 것 — 최소 버전이 26이므로 불필요한 복잡도임

- capability/entitlement 추가는 Xcode에서 수행하고, 변경된 파일(Runner.entitlements, Info.plist, project.pbxproj)을 커밋에 포함할 것
- **승인된 통합 (출시 전)**: 햅틱(HapticFeedback — 롱프레스 제스처에 일부 적용됨, 카운트다운·종료 등으로 확장 예정), Live Activities(ActivityKit — 잠금화면/Dynamic Island에 러닝 세션 표시)
- **v1.1 예정**: HealthKit(워크아웃 기록 + kcal 정확도 — 현재는 MET 9.8 × 65kg 고정 추정), CMPedometer(GPS 교차 검증)
- 이 외 네이티브 API 도입은 유저 승인 후에만

## 의도된 설계 결정 (바꾸지 말 것)

- **러닝 중 실시간 동기화 없음** — 함께 시작하고, 끝나면 합산. 라이브 합산은 v1.1 (개발 난이도의 절반이 여기 있어서 의도적으로 잘랐음). 단, 제스처 신호(탭/스와이프/롱프레스 → `gesture` 필드 하나 덮어쓰기)는 순간 이벤트라 이 원칙과 무관하게 허용됨
- **백그라운드 위치 추적 있음** (2026-07-15 결정 변경). Always 권한을 받았을 때만 `allowBackgroundLocationUpdates`를 켬 — When In Use만 있는데 켜면 iOS가 앱을 강제 종료시킴. Info.plist `UIBackgroundModes`에 `location` 포함, `wakelock_plus`로 화면 꺼짐 방지. 심사 시 위치 권한 설명 문구를 꼼꼼히 써야 하고 리젝 가능성 인지하고 진행 중
- **Apple 로그인 필수 — 익명 로그인 없음** — 모든 가입은 Apple 인증을 거쳐야 하고, 성공 후 항상 `NicknameScreen`을 거쳐 홈으로. Google 로그인도 구현·연동 완료. 카카오 등은 v1.1
- **데모 모드** (`demo: true` 플래그, lobby/run/finish 관통) — 가상 파트너 '지수'와 전체 플로우 체험. 혼자 테스트용 + **Apple 심사관용이므로 절대 제거 금지** (심사 가이드라인 2.1 — 핵심 기능이 2인 동시 러닝이라 심사관이 혼자 체험할 유일한 수단). 친구 0명·기기 1대 상태에서도 반드시 진입 가능해야 함. 진입점: 설정('혼자 미리 체험하기' — **항상 유지**) + 홈(친구 0명일 때 — UI 정리 시 조정 가능). 데모 러닝은 RunRecovery에 저장하지 않음
- **수익화 UI 출시 전 노출 금지** — GoingOn+ 구독 등 결제 관련 화면·버튼은 프로토타입에 있어도 구현하지 않음. 수익화는 출시 후 별도 결정
- **친구 연결은 '요청 → 수락' 모델** (2026-08-13 결정, 구현 예정 — TODO 참조). 아이디로 찾아 **요청을 보내고, 상대가 수락해야** 연결됨. 인스타 팔로우 요청 방식이며, 타깃 사용자가 SNS에 익숙해 이 쪽이 오히려 자연스럽다는 판단. 아이디를 아는 사람이 곧 연결 권한이 되는 구조(카톡 방식)는 폐기함
  - **차단은 필수** — 요청·수락만으로는 같은 사람이 요청을 반복해 보내는 걸 못 막음. 차단된 상대는 요청 전송·검색 결과 노출·세션 생성이 모두 거부돼야 하며, 이는 보안 규칙에서도 막을 것
  - 거절은 **상대에게 알리지 않음**(조용히 사라짐). 거절 통보는 상처를 주고 재요청을 유발함
  - 자유 입력 텍스트는 이름·아이디뿐임(GO? 거절 메시지는 3개 중 선택식). 즉 심사 대응의 초점은 유해 텍스트 필터링이 아니라 **동의 없는 연락 차단**임
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
- "의도된 설계 결정" 섹션과 충돌하는 구현 금지 — 충돌하면 구현을 멈추고 유저에게 물을 것
- 이 파일에 작업 과제를 추가하지 말 것 — 과제는 TODO.md에

## 실행

VS Code: 우하단 디바이스 선택(iPhone 16e) → Run > Start Debugging. 저장 시 핫 리로드.

## 로드맵 (참고)

UI 폴리시 → 햅틱 확장 → Live Activities → 심사 준비(Privacy Manifest·권한 문구) → 실기기 GPS 테스트(복구 플로우 포함) → 친구 1명과 실전 테스트 → TestFlight → 스토어 심사(리젝 1~2회 예상) → 출시 후(v1.1): 푸시(FCM), 라이브 합산, HealthKit, CMPedometer, 정기런, 카카오 로그인, 구독
