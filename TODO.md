# TODO — 실무 과제

> **2026-09-02 — 제품 로드맵은 없다.** 방향(고객 세그먼트·미션·디자인 철학·수익 모델)이 비어 있으므로 기능 계획도 비어 있다. 아래는 **어느 방향으로 가든 버려지지 않는 것들**만 남긴 목록이다: 법·심사·검증·환경.
>
> 이전 로드맵(개편 P1~P8, 도전신청서 1R/2R/3R)은 삭제했다. 필요하면 `git show 4ae3998:TODO.md`.

작업 지시는 "TODO.md N번 해줘" 형식으로. 모든 과제는 CLAUDE.md의 **완료 기준**을 통과해야 완료.

---

## 1. ⛔ 법·심사 차단 — 이게 안 되면 출시 자체가 막힌다

### 1.1 위치기반서비스사업 신고
러닝앱인 한 무조건 필요하다. 무료·2주·온라인(emsit.go.kr), 1인기업 특례로 개시 후 1개월 유예.
**미신고 시 3년 이하 징역 또는 3천만원 이하 벌금.** 스트라바가 한국에서 철수한 원인이 이 규제 대응이었다.

- [ ] **사업자등록** (선행 조건)
- [ ] 신고서 제출

### 1.2 법률 문서
초안은 `docs/legal/`에 있다. 수집 항목은 2026-09-01에 **코드에서 직접 확인해** 적었다(좌표 미저장·마이크 미사용·탈퇴 시 세션 잔존까지).

- [ ] `[확인 필요]` 채우기 — 사업자명·대표자·보호책임자·문의 이메일·시행일
- [ ] **법률 검토** — 초안 상태로 게시 금지
- [ ] **호스팅** — App Store Connect의 개인정보처리방침 URL이 필수 항목이다
- [ ] **위치정보 이용약관** — 아직 없는 세 번째 문서. 확인자료 보유근거·보유기간(6개월) 명시 필요
- [ ] 로그인 화면에 **누를 수 있는 링크**로 넣기 (2026-09-01에 링크 없는 고지 문구를 뺐다 — 없는 문서에 동의를 받고 있었다)
- [ ] 기능이 바뀌면 문서도 같이. 특히 **마이크를 되살리면 §2에 추가**

### 1.3 위치정보 이용·제공 사실 확인자료
법이 요구하는 **기능**이라 코드가 필요하다.

- [ ] 자동 기록 + 6개월 보존 구현

### 1.4 신고 경로
- [ ] **설정에 신고 연락처(이메일) 노출.** 차단은 구현돼 있다(홈 롱프레스 → 차단, 설정 → 차단 목록에서 해제). 가이드라인 1.2가 요구하는 나머지 한쪽이 신고다
- [ ] 위치 권한 설명 문구(`NSLocationAlwaysAndWhenInUseUsageDescription` 등) 심사 기준으로 재작성
- [ ] 심사관용 데모 모드 안내를 App Review 노트에 쓸 문구 초안

### 1.5 끝난 것
- [x] **`PrivacyInfo.xcprivacy`** (2026-09-01) — UserID·Name·EmailAddress·PhotosorVideos·Fitness·DeviceID·CrashData. 전부 `AppFunctionality`, 추적 없음.
      **위치는 신고하지 않았다** — 좌표가 기기 밖으로 안 나가기 때문. 경로 저장을 도입하면 `PreciseLocation` 추가 필수.
      오디오도 없다(마이크 미사용). `NSPrivacyAccessedAPITypes`는 비었다.
      `project.pbxproj` 네 곳에 등록해 `Runner.app/PrivacyInfo.xcprivacy` 존재를 확인했다
- [x] 차단 — 요청·수락 모델과 함께 구현
- [x] 마이크 권한·`record` 의존성 제거 (2026-09-01). 되살릴 때 순서: `record` 추가 → `redesign-p5-p6.5`에서 `voice_note_service.dart`·`cooldown_screen.dart` 가져오기 → Info.plist 문구 복원 → xcprivacy에 `AudioData` 추가. **Storage의 `voices/` 규칙은 안 지웠다**

---

## 2. 아직 안 끝난 검증

시뮬레이터 화면은 접근성 클릭(§5.1)으로 직접 눌러 확인한다. 아래는 그걸로도 안 되는 것들 — 실기기·계정 2개·시스템 UI가 필요하다.

### 2.1 푸시 알림 — 실기기 도착 확인됨 (2026-09-11 23:18), TestFlight 새 빌드만 남음

**푸시는 한 번도 간 적이 없었다.** 원인은 두 겹이었고 첫 번째는 코드로 풀렸다.

1. **APNs 토큰이 발급되지 않던 것 — 해결(6e44bc8).** firebase_messaging 15.x가 이 앱의
   UIScene 구조(`FlutterImplicitEngineDelegate`)에서 등록 콜백을 못 받는 알려진 버그
   (flutterfire #17859, 16.1.0에서 scene 델리게이트 채택으로 수정). FlutterFire를
   4.x/16.x 계열로 올리자 실기기(iPhone 14, iOS 26.6)에서 **처음으로**
   `users/{uid}.fcmTokens`에 토큰이 들어갔다. 아래 표의 "정상"들이 전부 맞았던 이유다 —
   iOS도 키도 서명도 문제가 없었고 플러그인이 콜백을 놓치고 있었다.
2. **Firebase 콘솔의 APNs 자격 증명이 무효 — 남음.** 토큰이 생긴 뒤
   `push-check.js send`가 `messaging/third-party-auth-error: Invalid APNs credential`.
   로컬 키 `4FX4S6SZNR`은 `tools/apns-probe.py`로 애플에 직접 물어 **정상 확인**
   (운영·샌드박스 모두 400 BadDeviceToken = 인증 통과). 즉 파일이 아니라 콘솔에
   올라간 쪽이 틀렸다(다른 파일을 올렸거나 키ID·팀ID 오기).

**콘솔 — 끝남(2026-09-11).** 운영 프로젝트에 APNs 키를 지우고 다시 올린 뒤에도
한동안 `InvalidProviderToken`이 계속됐고, **약 1시간 뒤(23:18)부터** FCM이 200을 돌려줬다.
FCM이 APNs용 JWT를 캐시하는 것으로 보인다 — **키를 바꾼 뒤 바로 실패해도 한 시간은 기다려
볼 것.** 그동안 연습실에 올렸다 운영에 올렸다 헷갈린 일이 있어 연습실 콘솔 이름을
`goingon STAGING - NOT THE APP`으로 바꿨다.

- [x] ~~APNs 키 재업로드~~ → `push-check.js send` **성공 1 / 실패 0** (실기기 도착)
- [ ] TestFlight 새 빌드(`./tools/ship-testflight.sh`, **요청받았을 때만**) — 지금 올라간
      +23은 옛 플러그인이라 토큰을 못 받는다. 새 빌드를 깔아야 다른 계정들도 토큰이 생긴다
- [ ] 실제 흐름: 상대에게 GO? → 앱을 완전히 종료한 상태에서 잠금화면에 뜨는지.
      DM은 한 번만 와야 하고(`onRunRequest`와 `onThreadMessage` 중복 없음), 거절에 알림이 새로 온다

**실기기 작업 시 주의:**
- **`flutter run`의 기기 ID는 `00008110-001635211E11401E`.** `devicectl`이 보여주는 UUID
  (`A42CE0A5-…`)는 flutter가 못 잡는다
- **케이블로 연결할 것.** 무선이면 profile 빌드+설치가 10분을 넘기고 로그도 안 읽힌다.
  케이블이면 설치까지 1분 안팎
- 빌드 중 Firestore Swift에서 `Cannot find type 'ExprBridge' in scope`가 쏟아지면
  SDK 버전이 바뀐 뒤 SPM 캐시가 옛 판을 문 것 — `rm -rf build/ios/SourcePackages` 후 다시
- **debug 빌드는 기기에서 단독 실행이 안 된다** — iOS 14+ 제약. 맥에 연결된
  `flutter run` 상태에서만 돈다. 폰에 남겨두면 "실행되지 않는 앱"이 된다.
  로그를 봐야 할 때만 debug로 띄우고, 끝나면 profile로 되돌릴 것
- **실행 중인 앱 위에 새 빌드를 설치하면 예전 프로세스가 얼어붙는다.**
  화면은 남는데 탭이 하나도 안 먹어서 앱 버그로 오해하기 쉽다. 설치 전에
  `xcrun devicectl device process terminate` 로 먼저 죽일 것
- profile 빌드는 `aps-environment: development` 토큰을 **운영 타입**으로 등록한다
  (플러그인이 `#ifdef DEBUG`로만 가른다). 콘솔 키를 고친 뒤에도 이 빌드로는
  전송이 실패할 수 있으니, 발송 검증은 TestFlight 빌드(운영 entitlement)로 할 것

### 2.2 프로필 사진 (업로드 경로는 검증됨, 사진첩 picker는 시스템 UI라 접근성 클릭 밖)
- [ ] 설정 → 프로필 편집 → 사진첩에서 한 장 골라 아바타가 바뀌는지
- [ ] 그 사진이 홈(내 카드)·우리 탭 짝 아바타에도 반영되는지
- [ ] '사진 지우기' 후 이름 첫 글자 아바타로 돌아오는지

### 2.3 러닝 복구 (2026-08-13 구현됨)
데모가 아닌 러닝은 상대의 준비완료가 필요하므로 **혼자 재현 불가.** 2.5와 함께 할 것.

- [ ] 러닝 시작 → 10초 후 앱 강제 종료 → 재실행 → "마치지 못한 러닝이 있어요" 확인
- [ ] "기록 저장" → FinishScreen 진입 + Firestore results 반영
- [ ] "버리기" → 다이얼로그 재등장 없음
- [ ] 정상 완료 후에는 다이얼로그가 뜨지 않는 것

### 2.4 실기기 GPS (야외)
- [ ] **육상 트랙 400m × 10바퀴** → 4.00km ±1%. 정확도 비례 계수(1.0)가 과한지 여기서 드러난다
- [ ] **10분 가만히 서 있기** → 거리 증가 없어야 함
- [ ] **러닝 중 다른 앱 10분 쓰고 복귀** → `maxFixAge: 10초`가 배경 복귀 시 정상 fix까지 버리지 않는지. 버린다면 값을 늘려야 한다
- [ ] **천천히 걷기 구간** → 거리가 뭉텅이로라도 반영되는지
- [ ] 폰 잠근 상태 + 강제 종료 복구 포함 1km 이상

### 2.5 2인 검증 (계정 2개 필요)
- [ ] A가 요청 → B에게 카드 → 수락 → 양쪽 목록에 반영
- [ ] 거절이 조용한지(A에게 알림 없음), A가 재요청 가능한지
- [ ] 차단 후 상대가 검색하면 "그런 아이디를 쓰는 사람이 없어요"
- [ ] 차단 해제 후 다시 연결되는지
- [ ] **`runs` 목록의 관계 갈래** — 상대 계정에 실제 러닝이 있어야 밟힌다. 상대가 달린 뒤 그 리듬이 보이는지
- [x] ~~A가 요청 → B에게 카드 → 수락 → 양쪽 목록에 반영~~ **(2026-09-11, 파트너 봇으로 관통)**
      이 과정에서 `friendRequests` 생성 규칙에 `cheer`가 빠져 **18일간 요청이 전부
      거부되던 버그**를 잡았다. 수정 후 연습실·운영 모두 배포됨
- [x] ~~GO? → 수락 → 로비 준비 상태 양방향 전파 → 러닝 → 결과 제출~~ **(2026-09-11)**
      `./tools/env.sh staging` 후 `flutter run -t lib/main_partner_bot.dart
      --dart-define=GO_ENV=staging -d <두 번째 시뮬레이터>` — 90초면 한 판이 돈다
- [ ] **라이브 동기화** — 상대 원이 움직이는지 / 발을 맞췄을 때 공명(골드·종소리·햅틱)이 뜨는지 / 한 명이 앱을 배경으로 내려도 사라지지 않는지 / Always 권한 없이 화면 유지 모드일 때도 같은지
- [ ] 30분 러닝 후 Firestore 쓰기 횟수 — 인당 600회 이하 예상

### 2.6 케이던스 실측 (아직 파라미터가 가설이다)
합성 신호 검증은 통과했지만(`test/cadence_engine_test.dart` 17개) **실주행 CSV가 없다.** 절차는 `docs/m0_spike.md`.

- [ ] `main_cadence_probe` — 주머니·암밴드·손 각 1회, 걷기↔달리기 전환 3회 포함
- [ ] `tools/analyze-probe-csv.py`로 랩 구간별 수동 카운트 대비 **±3spm** 확인
- [ ] `main_tempo_probe` — **실기에서** 지터 p95 측정. 시뮬레이터 값은 iOS 기기를 대표하지 않는다
- [ ] 통과하면 `cadence_engine.dart`에 "실측 확정(날짜)" 주석. 미달이면 kThresholdK·검출 창 튜닝 후 재실측

---

## 3. 아직 안 돌린 시뮬레이터 시나리오

- [ ] `./tools/sim-gps.py run track400` — 곡선에서 얼마나 짧게 잡히는지(§5.3의 트레이드오프 실제 크기)
- [ ] `./tools/sim-gps.py run stationary` — 정지 드리프트, 정답 0m

---

## 4. 배포·서명 (건드리지 말 것)

- Release는 **수동 서명** + `GoingOn App Store` 프로파일. 자동 서명으로 바꾸면 아카이브가 개발용 프로파일을 요구해 **케이블 없이는 빌드가 아예 안 된다** (한 번 시도했다 되돌림)
- `aps-environment`는 빌드별 분리: Debug/Profile → `Runner.entitlements`(development), Release → `RunnerRelease.entitlements`(production). 섞이면 앱은 정상인데 **알림만 조용히 안 온다**
- 같은 이름의 프로파일이 맥에 둘 이상 설치돼 있으면 export가 엉뚱한 걸 집는다. 재발급 후 옛것을 지울 것
- 실기 설치는 `--profile`로. `--release`는 App Store 프로파일이라 기기 설치가 거부된다
- **배포 타깃 iOS 26.0** — iOS 25 이하 기기는 설치 불가. 테스트용 아이폰이 iOS 26이어야 한다

---

## 5. 알려진 한계 — 다시 부딪히지 말 것

### 5.1 시뮬레이터 화면은 접근성 클릭으로 검증한다
탭·버튼·행 전부 코드로 누를 수 있다. "탭을 못 해서 못 봤다"는 이유는 성립하지 않는다.

```bash
# 1) 창 위치
osascript -e 'tell application "System Events" to tell process "Simulator" to get {position, size} of window 1'
# 2) 창 캡처(2x)로 대상 픽셀 찾기 → 화면 좌표 = 창 원점 + 픽셀/2
screencapture -x -R X,Y,W,H /tmp/win.png
# 3) 누르기 (자체 타임아웃 — osascript가 가끔 안 끝난다)
( osascript -e 'tell application "System Events" to click at {X, Y}' & pid=$!; sleep 8; kill $pid 2>/dev/null )
# 4) 결과
xcrun simctl io booted screenshot /tmp/check.png
```

- `cliclick`·CGEvent 좌표 클릭은 시뮬레이터가 버린다 — 쓰지 말 것. 접근성 API(System Events)만 통한다
- `tell application "Simulator" to activate`는 Automation 권한 프롬프트에 걸려 멈춘다 — 필요 없다
- 손쉬운 사용 권한은 프로세스 시작 시점에 캐시된다. 안 먹으면 터미널을 재시작
- 사진 picker 같은 **Flutter 밖 시스템 UI**는 이 경로로 못 누른다. `idb`는 macOS 26 미지원
- 특정 경로만 빨리 띄우려면 `lib/main_*_probe.dart` 임시 진입점(확인 후 삭제). 설치 → `simctl privacy grant location-always` → 실행 순서

### 5.2 시뮬레이터로 못 보는 것
- **`horizontalAccuracy`를 조종할 수 없다** — simctl이 노출하지 않는다. 정확도 필터는 단위 테스트 담당
- **배경 동작을 재현할 수 없다** — 시뮬레이터는 실기기처럼 앱을 억제하지 않는다

### 5.3 GPS 필터의 트레이드오프
기준점을 붙드는 방식이라 **굽은 길에서 약간 짧게 잡힌다** — 30m를 붙들면 그 구간을 직선으로 재기 때문. 정확도가 좋으면(5m) 임계값도 5m라 영향이 미미하고, 나쁠 때만 커진다. 신호가 나쁠 때 데이터가 거친 건 어차피 피할 수 없는 쪽이라 감수했다.

### 5.4 배경 스냅샷 — 메커니즘을 확정하지 못했다 (2026-08-16)
감사 #15 수정 후 최대 공백이 35초 → 6초로 줄었지만, 그 측정에서 **위치 콜백은 130초나 비었는데도** 스냅샷이 6초 간격을 유지했다. 즉 이번엔 **타이머가 배경에서도 돌았다** — "타이머가 멈추니 위치 콜백이 메운다"는 가설과 다르다.

왜 지난번엔 비고 이번엔 안 비었는지 **확정 못 했다.** 다만 배경 실행 허용이 상황마다 다르다면 한 가지에만 의존하는 것이 위험하다는 뜻이므로, 타이머와 위치 콜백 **양쪽**에 건 수정은 그대로 옳다. **"이 수정 덕분에 6초가 됐다"고 단정하지는 말 것.**

남은 한계: 가만히 있으면서 배경에 있는 상황은 여전히 못 막는다(타이머도 위치 콜백도 안 옴). 달리는 중이 아니라 잃을 기록도 거의 없다.

### 5.5 순간 페이스는 계산되지만 화면에 없다
`stats.instantSecPerKm`(30초 평활)이 계산되는데 RunScreen은 여전히 **누적 평균**을 보여준다. 화면에 어떻게 넣을지는 미결.

---

## 완료된 것 (다시 만들지 말 것)

- [x] 우리 탭 · 설정 탭 · Crashlytics 삼중 캐치 · 러닝 복구 구현
- [x] 폰트 번들 전환(런타임 다운로드 제거)
- [x] GPS 감사 수정 #1~#4·#9 — `maxFixAge` 10초(1시간 전 캐시 fix로 5190m → 190m), `minHorizontalAccuracy` 0(음수 정확도 거부), `keepAnchorOnRejectedFix`(튐 1회에 20m 손실 → 0), 정확도 비례 최소 이동(10분 정지 1102m → 0m), 30초 페이스 평활.
      **CLAUDE.md가 보호하는 네 값은 그대로다** — 없던 필터를 켠 것이고 `RunFilterConfig.legacy`가 차이를 지킨다
- [x] GPS 검증 3층 — 단위 테스트 / `tools/sim-gps.py` + `main_gps_probe` / 실기기
- [x] 감사 #15 배경 스냅샷 (§5.4)
- [x] 배포 타깃 iOS 26.0 인상 — 업로드 경고 90068 해소
- [x] `withOpacity` → `withValues` 73곳 · friendsStream 이중 구독 정리(`shared_stream.dart`) · 세션 상태 전이 유닛 테스트(`session_rules.dart`, 22개)
- [x] 데모 복구 버그 — 데모 러닝이 RunRecovery에 저장돼 심사관이 무한 다이얼로그를 밟을 수 있던 문제
- [x] 친구 연결 '요청 → 수락' 모델 + 차단, 규칙에서 직접 쓰기 봉쇄
- [x] `friends` → `follows`/`following` 이관 (expand-migrate-contract, 2026-09-01)
- [x] 보안 규칙 회귀 테스트 하네스 `test_rules/` 21개 — 만들자마자 **비공개 런이 목록으로 새던 실제 구멍**을 잡았다
