# GoingOn (고잉온)

**멀리서도 서로의 발걸음 소리를 느끼며 함께 뛰는 러닝앱(iOS).** 창업자(이찬웅)는 비전공자 1인 개발.

> **2026-09-02 — 제품 판단은 비어 있다.** 대전제 한 줄을 빼면 고객 세그먼트·미션·비전·디자인 철학·수익 모델이 정해져 있지 않다. 이 파일에는 **실무적인 근거만** 남겼다 — 기술이 강제하는 것, 법이 요구하는 것, 심사가 막는 것, 그리고 깨뜨려봐야 알 수 있었던 사실들.
>
> **여기 없는 규칙을 "원래 이랬으니까"라고 말하지 말 것.** 제품 설계·전략·UX·사운드 문서는 2026-09-02에 전부 삭제했다. 필요하면 `git show 4ae3998^:docs/redesign/` 등으로 꺼낼 수 있지만, 꺼낸 것은 **효력 없는 과거 기록**이다.

**출시 목표일은 정해두지 않는다.** "일정이 급하다"를 이유로 완료 기준이나 심사 준비 항목을 생략하지 말 것.

**작업 과제는 `TODO.md`에.** 이 파일은 변하지 않는 제약과, 깨뜨려봐야만 알 수 있는 사실만 담는다.

## 지금 코드가 어떤 상태인가 (사실 확인용)

**화면**: 로그인 → 닉네임 → 홈(프로필 카드 + 친구 목록 + GO?) · 로비 · 러닝 · 완료 · 탭바(홈/우리/설정). 2026-08-23~09-01에 만든 개편 UI는 2026-09-01에 롤백했고 `redesign-p5-p6.5` 브랜치에 보존돼 있다.

**서비스 계층이 화면보다 앞서 있다.** 아래는 코드·규칙·배포까지 살아 있지만 **화면이 없어 지금은 쓰이지 않는다.** 없는 줄 알고 다시 만드는 것이 가장 비싼 실수다:

- 케이던스 검출(`services/cadence/`) · 공명 판정(`resonance.dart`) · 사운드 재생 층(`services/sound/`)
- 고스트런(`services/ghost/`) — 케이던스 타임라인 저장·재생, 규칙·인덱스 배포됨
- 응원 브리지(`services/cheer/`) — `cheers` 컬렉션·`onCheer` 푸시 배포됨
- 페이스메이트 관계(`follows` 간선 + `users.following`) — 이관 완료, 옛 `friends` 필드는 전 계정에서 삭제됨
- 라이브 동기화(세션 문서의 `live` 맵) — 실세션에서 동작 확인됨
- 보안 규칙 회귀 테스트(`test_rules/`) 21개 · 자동화 테스트 275개

**심사 차단 하나가 남아 있다**: 위치기반서비스사업 신고. 개인정보처리방침·이용약관은 **초안까지**(`docs/legal/`), `PrivacyInfo.xcprivacy`는 작성·번들 확인 완료. 로그인 화면에는 링크가 없다 — 호스팅 주소가 없어서 2026-09-01에 고지 문구를 뺐다.

## 진행 방식

**기본은 묻지 말고 진행한다.** 판단이 서면 하고, 왜 그렇게 했는지와 버린 대안을 결과와 함께 보고한다. 매 단계 승인을 받으려 멈추지 말 것.

다만 아래는 되돌리기가 비싸거나 밖으로 나가는 일이라 **반드시 먼저 물을 것**:

- **GPS 필터 값 변경** — 실측으로 검증된 값이고, 틀리면 사용자 기록이 조용히 망가진다 (아래 참조)
- **배포 타깃 되돌리기** — 설치 가능한 기기가 줄어든다
- **밖으로 나가는 것** — TestFlight 업로드, Firebase 배포, 스토어 제출
- **되돌릴 수 없는 삭제** — 계정, 저장소 데이터, 커밋 이력

그 외(라이브러리 도입, 네이티브 API, 구조 변경 등)는 판단해서 진행하고 결과에서 설명한다.

**작업 하나가 끝나면 그 자리에서 커밋한다.** 완료 기준을 통과한 시점이 곧 커밋 시점이다.

## 폰트 — 번들이 유일한 안전망

폰트는 `assets/fonts/`에 **번들**되어 있고, 패밀리 이름은 `pubspec.yaml`의 `fonts:`와 `lib/theme.dart`의 `_serifFamily`/`_sansFamily`가 일치해야 한다.

**이 환경에는 시스템 폰트 폴백이 아예 작동하지 않는다.** 2026-08-16에 세 조건을 나란히 렌더해 확인함 — `fontFamily`를 지정하지 않으면 이모지는 물론 **한글까지 두부(?)로 깨진다.** 한글이 나오는 건 폴백 덕분이 아니라 NotoSansKR을 번들해 이름으로 직접 지정했기 때문이다. 여기서 따라오는 것들:

- **Instrument Serif에는 한글 글리프가 없다.** `GoTheme.serif()`가 `fontFamilyFallback`으로 NotoSansKR을 물고 있어야 하며, 이 연결을 끊으면 세리프 타이틀의 한글이 전부 깨진다 (실제로 한 번 깨뜨렸다 복구함)
- **이모지를 쓸 수 없다 — Material Icons 또는 텍스트만.** 취향이 아니라 글리프가 없어서다. `fontFamilyFallback`에 `Apple Color Emoji` 같은 시스템 폰트 이름을 넣는 방법은 **두 번 실패했으니 다시 시도하지 말 것**
- **번들 폰트에 없는 글리프는 안전망이 없다.** 새 문자 집합(다른 언어, 특수 기호)을 도입하면 조용히 두부가 되므로 반드시 시뮬레이터에서 눈으로 확인할 것
- **기하 기호(▲ ● ★)는 정상 렌더된다** — 이모지가 아니라 NotoSansKR에 든 일반 글리프
- **Flutter가 그리지 않는 문자열은 예외** — 공유 시트 텍스트, 푸시 알림 본문 등은 받는 쪽이 시스템 폰트로 렌더하므로 이모지를 써도 된다 (`finish_screen.dart`의 공유 문구가 이 경우)
- 굳이 이모지가 필요하면 남은 길은 이모지 폰트를 함께 번들하는 것뿐인데, IPA가 30%가량 커진다

색·타이포 토큰의 소스는 `lib/theme.dart`의 `GoColors`/`GoTheme`다. 값 자체는 판단이므로 바꿀 수 있지만, **바꾼다면 한 곳(theme.dart)에서** 바꾼다.

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
- **관계는 대기 중인 요청이 실제로 존재할 때만 성립한다.** `follows`/`following`에 직접 쓰는 코드를 새로 만들지 말 것 — 규칙이 거부한다
- 프로필 사진은 **Storage** `avatars/{uid}.jpg`에 두고 문서에는 주소(`photoUrl`)만. 이미지를 문서에 넣지 말 것 — 친구 목록이 실시간 스트림이라 매 스냅샷마다 따라온다. 덮어쓸 때마다 다운로드 토큰이 새로 발급돼 주소가 바뀌므로 **업로드 후 `photoUrl` 갱신을 반드시 함께** 할 것
- **목록(list) 규칙에서 `resource.data`는 문서 내용이 아니라 쿼리 조건으로 채워진다** (2026-08-23 에뮬레이터로 확인). 그래서 목록 규칙이 참조하는 필드는 클라이언트가 `where`로 좁혀야 하고, 안 좁히면 조건이 성립하지 않아 쿼리가 거부된다. **`.get(필드, 기본값)`을 목록 규칙에 쓰지 말 것** — 기본값이 있으면 안 좁힌 쿼리가 기본값으로 통과한다. 실제로 `runs`의 `.get('visibility','pacemates')` 때문에 **비공개 런이 목록으로 새어 나왔다.** 단일 문서(get)는 문서 내용을 보므로 같은 규칙이라도 거부됐고, 그래서 눈으로는 안 보이는 구멍이었다
- **규칙을 바꾸면 `test_rules/`를 돌릴 것**: `cd test_rules && npm test` (에뮬레이터 필요 — `brew install openjdk` 후 `PATH=/usr/local/opt/openjdk/bin:$PATH`). 실기기로는 상대 계정에 실제 러닝이 있어야 밟히는 갈래가 있어 검증이 사실상 불가능하다
- **`runs` 목록 쿼리와 규칙은 한 쌍이다.** 목록 규칙은 돌아오는 문서를 하나씩 판정하고 **하나라도 막히면 쿼리 전체가 거부**된다. 그래서 클라이언트가 `visibility`로 비공개를 미리 빼고 던져야 하며(`GhostService.recentFrom`), 규칙만 고치거나 쿼리만 고치면 목록이 통째로 빈다. 분기 총량 30 제한 때문에 uid 청크는 15가 천장이다(15 × 공개범위 2)
- 목록 규칙이 보는 것은 **내 관계 목록**(`myFollowing()`)이지 상대의 것이 아니다 — 상대 문서를 읽으면 사람 수만큼 `get()`이 생겨 한도(10)를 넘긴다
- 규칙·인덱스는 소스가 기준: `firebase deploy --only firestore,storage --project goingon-c12f3` (배포 전 `--dry-run`)
- **마이그레이션의 마지막 단계는 "필드를 지우는 것"이 아니라 "그 이름을 전부 훑는 것"이다.** `friends` → `follows` 이관에서 규칙·Functions·탈퇴 경로·프로필 생성 네 곳을 놓쳐 조용히 죽은 기능이 생겼다

## 기술 원칙

- **시간 계산**: 경과 시간은 Timer 틱 누적이 아니라 **타임스탬프 차이**로. iOS는 백그라운드에서 Timer를 멈추므로 틱 누적은 반드시 틀린다. 세션의 공동 출발 시각(`startedAt`)은 serverTimestamp이며 먼저 찍힌 값을 유지한다
- **세션 복구**: 러닝 중 앱이 죽어도 기록이 살아남아야 한다. `run_recovery.dart`가 5초마다 로컬 스냅샷을 남기고 RootScreen이 발견해 마무리를 제안한다. 이 경로를 끊지 말 것
- **GPS 필터** (`run_accumulator.dart`의 `RunFilterConfig`): accuracy 30m 초과 무시, 두 지점 간 속도 10m/s 초과는 이상치(dt≤0이면 절대 거리 50m), distanceFilter 5m. **이 네 값은 실측으로 검증됐고 변경은 승인 필요** — 바꾸면 실내 드리프트가 재발한다. 감사 수정으로 켠 필터들(fix 나이·음수 정확도·기준점 유지·정확도 비례 최소 이동)은 이 네 값을 건드리지 않고 추가된 것이며, `RunFilterConfig.legacy`가 수정 이전 동작을 보존해 회귀 테스트가 차이를 지킨다
- **집계 필드**: `users`의 monthKm/totalRuns/weekStreak는 반드시 트랜잭션(`_bumpMonthlyStats`) 경유. 재제출 시 이중 집계 방지(isFirstSubmit)를 우회하는 직접 쓰기 금지
- **username 변경**: `usernames/{old}` 삭제 + `usernames/{new}` 생성 + `users/{uid}` 갱신은 **하나의 트랜잭션**으로. 실패하면 아이디가 유령으로 남거나 탈취될 수 있다
- **상태 관리**: StatefulWidget + setState + Stream 구독이 기존 패턴. 다른 패턴이 필요하면 도입하되 왜 바꿨는지 설명할 것
- **에러 보고**: 삼중 캐치(FlutterError.onError + PlatformDispatcher.onError + runZonedGuarded)로 Crashlytics 연동됨. 서비스 호출 실패는 `recordError(fatal: false)` + 유저 안내가 관례
- **권한 추가**: Info.plist 설명 문구 + `PrivacyInfo.xcprivacy` 갱신을 한 세트로. **xcprivacy는 파일만 두면 번들에 안 들어간다** — `project.pbxproj`의 PBXBuildFile·PBXFileReference·Runner 그룹·Resources 빌드 단계 네 곳에 등록해야 한다
- **푸시**: 발송은 서버(`functions/src/push.ts`)만, 앱은 토큰 등록·탭 처리만. 토큰은 `users/{uid}.fcmTokens` 배열이고 죽은 토큰은 서버가 지운다. 알림 권한은 첫 실행이 아니라 **프로필이 준비된 뒤(RootScreen 진입)** 묻는다 — iOS는 한 번 거절당하면 다시 못 묻는다
- `UIBackgroundModes`에 `remote-notification`을 **넣지 않았다.** 알림 방식만 쓰므로 불필요하고, 안 쓰는 배경 모드 선언은 심사에서 지적받는다. 무음 데이터 메시지나 Live Activity 원격 갱신을 쓰게 되면 그때 추가할 것
- **연합(federated) 플러그인은 안 쓰는 플랫폼 구현이 iOS 빌드를 깨뜨린다.** `record: ^5.1.2`의 `record_linux`가 인터페이스 시그니처와 어긋나 iOS 빌드가 죽었다 — Flutter는 모든 플랫폼 구현을 컴파일한다

## Apple 네이티브 통합

완성도 있는 iOS 네이티브 경험이 목표. 검증된 플러그인 우선, 없으면 `ios/Runner`에 Swift + MethodChannel.

- **배포 타깃은 iOS 26.0** (2026-08-16에 13.0에서 올림). `@available` 분기나 버전 체크를 넣지 말 것 — 불필요한 복잡도다
- **`HKWorkoutSession`은 아이폰에서 백그라운드 실행을 보장하지 않는다** (2026-08-16 확인). API는 iOS 26부터 아이폰에서 쓸 수 있는 게 맞지만(SDK 헤더에서 `initWithHealthStore:configuration:error:`와 `HKLiveWorkoutBuilder`가 `API_AVAILABLE(ios(26.0))`로 확인됨), **워치와 달리 아이폰 세션은 시스템의 통상적인 포그라운드/백그라운드 생명주기를 따른다.** 즉 지금의 위치 배경 모드보다 나은 실행 보장을 주지 않는다
  - 아이폰 세션이 주는 것은 **잠금 상태에서도 건강 데이터에 접근할 권한**이지 실행 보장이 아니다. 애플이 잠금화면 대책으로 권하는 것은 **Live Activities**다
  - HealthKit은 건강 앱 연동·경로 저장·kcal 정확도에는 여전히 의미가 있으나, 권한이 거부될 수 있어 위치 기반 경로는 어차피 폴백으로 남는다 — 교체가 아니라 이중화다
- **백그라운드 위치는 Always 권한이 있을 때만 켠다.** When In Use만 있는데 `allowBackgroundLocationUpdates`를 켜면 iOS가 앱을 강제 종료시킨다. Always를 못 받으면 wakelock으로 화면을 켜두고 사용자에게 알린다
- capability/entitlement 추가는 Xcode에서 수행하고, 변경된 파일(Runner.entitlements, RunnerRelease.entitlements, Info.plist, project.pbxproj)을 커밋에 포함할 것

## 법·심사 게이트 (제품 방향과 무관하게 남는다)

**법**
- 위치정보 수집·이용 **별도 동의**, 이용·제공 사실 확인자료 **자동 기록·6개월 보존**, 위치정보 이용약관 별도 운영, **위치기반서비스사업 신고**(미신고 시 3년 이하 징역 또는 3천만원 이하 벌금)
- 개인정보처리방침·이용약관과 그 **공개 URL** — App Store Connect 필수 항목
- 만 14세 미만 처리

**심사**
- **차단·신고 수단은 필수다.** 사람이 사람에게 닿는 기능이 있는 한 App Store 가이드라인 1.2가 요구한다. *어떻게* 생겼는지는 열려 있지만 없앨 수는 없다
- `PrivacyInfo.xcprivacy`와 App Store Connect 개인정보 설문이 **일치**할 것. 지금 위치는 신고하지 않았다 — 좌표가 기기 밖으로 나가지 않기 때문이며, **경로 저장을 도입하면 `PreciseLocation`을 반드시 추가**해야 한다
- **혼자서 전체를 볼 수 있는 길**을 남길 것. 핵심이 2인 러닝이라 심사관이 혼자 체험할 수단이 없으면 막힌다(지금은 설정의 데모 모드)

## 완료 기준 (이게 전부 통과하기 전엔 "완료"라고 말하지 말 것)

1. `flutter analyze` — 에러 0, 새로 추가된 워닝 0
2. `flutter test` — 전부 통과 (테스트를 통과시키려고 테스트를 약화·삭제하는 것 금지)
3. 빌드가 실제로 됨 — 시뮬레이터에서 앱이 크래시 없이 해당 화면까지 도달
4. 화면 작업이면: `xcrun simctl io booted screenshot /tmp/check.png`로 스크린샷을 찍어 **직접 보고** 무엇이 의도대로고 무엇이 다른지 명시할 것 ("확인했음" 한 줄 금지)
5. **보안 규칙을 만졌으면** `cd test_rules && npm test` — 에뮬레이터 회귀 21개. 규칙은 틀려도 조용해서(느슨하면 아무도 모르고, 빡빡하면 목록이 그냥 빈다) 눈으로는 못 잡는다
6. 실패하면: 원인 분석 → 수정 → 1번부터 다시. 우회 금지

## 금지 사항

- firestore.rules를 느슨하게 풀어서 권한 에러를 "해결"하지 말 것 — 규칙이 거부하면 쿼리가 틀린 것
- **없는 것을 있다고 말하지 말 것** — 화면·문서·신청서 어디에서도. 실제로 없는 문서에 "동의한 것으로 간주"한다고 적어 두었던 적이 있다(2026-09-01 제거)
- `~/.secrets/goingon-firebase-adminsdk.json`은 **보안 규칙을 우회하는 관리자 키**다. 앱이나 저장소에 절대 넣지 말 것
- 이 파일에 작업 과제를 추가하지 말 것 — 과제는 TODO.md에
