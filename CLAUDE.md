# GoingOn (고잉온)

멀리 있는 친구·연인과 **같은 시간에 함께 달리는** iOS 앱. 핵심 철학: **"기록이 아니라 관계"** — Strava식 퍼포먼스 경쟁이 아니라, 떨어져 있는 두 사람이 발을 맞추는 감각을 판다. 창업자(이찬웅)는 비전공자 1인 개발이며, 한 달 내 App Store 출시가 목표.

## 디자인 기준 (가장 중요)

`design/prototype_v2.html` 이 **디자인의 단일 기준(source of truth)**. 화면 작업 전 반드시 이 파일을 열어 해당 화면의 마크업/CSS를 확인하고 간격·라운딩·타이포를 그대로 따를 것.

- 색: paper `#F0EAE0`, canvas `#EBE4D6`, lime `#C5E040`, limeDark `#6A9810`, coral `#F05840`, coralDark `#B03020`, ink `#1A1A16`, resonance(골드) `#D4A84B`, amber `#D97706`, mid `#78746E`, dim `#B0ACA6`, line `rgba(26,26,22,.09)` → `lib/theme.dart`의 `GoColors`
- 타이포: 타이틀/숫자 = Instrument Serif *italic* (`GoTheme.serif()`), 본문 = Noto Sans KR
- 컬러 의미: 나 = lime, 상대 = coral, 공명/kcal = 골드. 절대 섞지 말 것
- 카드 라운딩 18~22px, 화면 좌우 여백 22~28px, 섹션 라벨은 11px/600/letterSpacing 1.2/dim
- **이모지 글리프 사용 금지** — Noto Sans KR 폴백 이슈로 ?로 깨짐. Material Icons 또는 텍스트만 사용 (이미 한 차례 전부 교체함)

## 현재 최우선 과제 (유저가 직접 지시한 것)

1. **UI 간격/폴리시 전면 정리** — 전 화면을 prototype_v2.html과 나란히 비교하며 패딩·간격·정렬·크기를 맞출 것. 유저 피드백: "전체적으로 간격이나 이런 것들이 깔끔하지 않다"
2. **'우리' 탭 구현** — 프로토타입의 `s-us` 화면 참조. 함께한 여정(합산 거리로 두 도시 사이 거리를 몇 번 메웠는지), 스트릭, 마일스톤, 함께한 순간 리스트. MVP에선 Firestore `sessions`(status=finished)를 읽어 실데이터로 구성하되, 데이터 없으면 빈 상태 디자인
3. **'설정' 탭 구현** — 프로토타입의 `s-settings` 참조. MVP 범위: 프로필(이름 변경), 내 초대 코드 표시, 알림 토글(로컬 저장), 로그아웃, 회원탈퇴, 버전. GoingOn+ 구독 항목은 넣지 말 것(수익화는 출시 후)

## 아키텍처

- Flutter + Firebase (Apple 로그인, Firestore). 백엔드 서버 없음
- `lib/screens/`: main.dart(스플래시 게이트) → login(Apple 로그인) → nickname(닉네임 설정, 로그인 성공 후 항상 거침) → home → invite(초대코드) → lobby(준비단계) → run(GPS) → finish(합산+공유카드)
- `lib/services/`: auth(Apple 로그인+초대코드 발급), friend(코드로 양방향 연결), run(세션 생명주기), location(GPS+보정)
- Firestore: `users/{uid}` {name, inviteCode, friends[]}, `inviteCodes/{code}` {uid}, `sessions/{id}` {hostId, guestId, participants, status: waiting|ready|running|finished|cancelled, ready{}, results{uid:{seconds,km,kcal}}}
- 보안 규칙: `firestore.rules` (콘솔에 게시된 버전과 동기화 유지할 것. 세션은 hostId/guestId 직접 비교 — in participants 쓰면 쿼리 권한 거부남)

## 의도된 설계 결정 (바꾸지 말 것)

- **러닝 중 실시간 동기화 없음** — 함께 시작하고, 끝나면 합산. 라이브 합산은 v1.1 (개발 난이도의 절반이 여기 있어서 의도적으로 잘랐음)
- **백그라운드 위치 추적 있음** (2026-07-15 결정 변경 — 원래는 심사 난이도 때문에 없음이었으나, 폰을 잠그면 GPS·타이머가 멈춰 기록이 끊기는 문제가 실사용에 치명적이라 판단해 도입함). `location_service.dart`는 `AppleSettings(allowBackgroundLocationUpdates: true, showBackgroundLocationIndicator: true, pauseLocationUpdatesAutomatically: false)` 사용, Info.plist `UIBackgroundModes`에 `location` 포함, `wakelock_plus`로 화면 꺼짐 방지. 심사 시 위치 권한 설명 문구(NSLocationAlwaysAndWhenInUseUsageDescription 등)를 더 꼼꼼히 써야 하고 리젝 가능성이 있음을 인지하고 진행 중
- **Apple 로그인 필수 — 익명 로그인 없음** — 모든 가입은 Apple 인증(`AuthService.signInWithApple`)을 거쳐야 하고, 성공 후에는 이름을 받았든 안 받았든 항상 `NicknameScreen`을 거쳐 홈으로 이동. 계정이 실제 신원에 묶여 있어 로그아웃/재설치 후에도 항상 복구됨. Google 로그인(`AuthService.signInWithGoogle`)도 구현·연동 완료 — Apple이 이미 있으므로 추가해도 'Sign in with Apple' 의무와 무관. 카카오 등 다른 소셜로그인은 계속 v1.1로 미룸
- **데모 모드** (`demo: true` 플래그, lobby/run/finish 관통) — 가상 파트너 '지수'와 전체 플로우 체험. 혼자 테스트용 + **Apple 심사관용이므로 절대 제거 금지**
- **완료 화면 공유 카드** — RepaintBoundary 캡처 → share_plus. 셋로그식 성장 엔진이라 완성도 유지가 전략적으로 중요

## 실행

VS Code: 우하단 디바이스 선택(iPhone 16e) → Run > Start Debugging. 저장 시 핫 리로드.
수정 후에는 시뮬레이터로 직접 화면을 확인하고 마무리할 것.

## 로드맵 (참고)

실기기 GPS 테스트 → 친구 1명과 실전 테스트 → TestFlight → 스토어 심사(위치 권한 설명 중요, 리젝 1~2회 예상) → 출시 후: 푸시(FCM), 라이브 합산, 정기런, 카카오 로그인, 구독
