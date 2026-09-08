# 스플래시 브랜드 모션 — 통합 작업 지시서

프로토타입에서 확정한 로고 애니메이션(심볼 드로잉 → 손글씨 워드마크 → o 점프,
총 2.7s)을 실제 앱 스플래시에 연결하는 작업. 아래를 Claude Code에 그대로
붙여 넣으면 된다.

## 이미 돼 있는 것

- `lib/widgets/splash_motion/goingon_brand_motion.dart` — `GoingOnBrandMotion`
  위젯. Scaffold 없이 심볼+워드마크만 그리는 `CustomPaint` 두 개. 인트로가
  끝나면 `onIntroComplete` 콜백, 이후 원하면 아주 옅은 숨쉬기 루프
  (`idlePulseAfterIntro`)로 넘어간다.
- `lib/widgets/splash_motion/goingon_splash_paths.dart` — 워드마크 글자 path
  데이터 (수정 금지).
- `pubspec.yaml`에 `path_drawing: ^1.0.1` 추가 완료. `flutter pub get` 필요.
- 색은 전부 `GoColors`(coral/lime/ink)를 참조하도록 만들어서 theme.dart의
  "위젯 코드에 Color(0x…) 쓰지 않는다" 규칙을 지켰다. **단, 원본 아이콘
  파일(goingon_symbol.svg)의 링 색(FF6A55 / D6F24E)은 앱 팔레트의
  coral(F05840)·lime(C5E040)과 정확히 같지 않다 — 여기서는 GoColors 값으로
  통일했다.** 아이콘 고유색을 꼭 살리고 싶으면 아래 "열린 질문 1" 참고.

## 연결 작업

`lib/main.dart`의 `_SplashGateState._splash()` (약 210번째 줄)를 보면
현재 이렇게 되어 있다:

```dart
AnimatedBuilder(
  animation: _pulse,
  builder: (_, __) => BrandMark.pulsing(
    leftScale: 1 + _pulse.value * .16,
    rightScale: 1 + (1 - _pulse.value) * .16,
  ),
),
const SizedBox(height: 30),
Text('goingon', style: GoTheme.serif(42)),
```

이 세 줄(AnimatedBuilder + SizedBox + Text)을 아래로 교체:

```dart
GoingOnBrandMotion(),
```

그리고:

1. `import '../widgets/splash_motion/goingon_brand_motion.dart';` 추가.
2. `_pulse` `AnimationController`(initState의 `..repeat(reverse: true)`)와
   `dispose()`의 `_pulse.dispose()`는 더 이상 필요 없으면 제거 —
   단, **열린 질문 2**를 먼저 확인.
3. 그 아래 있던 태그라인(`'멀리 있어도, 함께'`)과 "화면을 누르면
   시작해요" 힌트, 탭하면 `_skip` 완료시키는 `GestureDetector`는 전부
   그대로 둔다 — 스플래시의 실제 대기/스킵 로직(`_resolve()`)은 건드리지
   않는다.
4. `flutter pub get` 실행.
5. 실기기/시뮬레이터에서 확인:
   - 최초 실행(첫 설치)에서 2초 최소 노출 로직과 2.7초 애니메이션이
     자연스럽게 맞물리는지 (애니메이션이 먼저 끝나면 정지 화면으로
     잠깐 대기하다 다음 화면으로 넘어가는지).
   - `flutter analyze` 통과.
   - 접근성 "동작 줄이기" 켰을 때 인트로 없이 완성 상태로 바로 뜨는지
     (`GoingOnBrandMotion`에 이미 처리돼 있음 — `MediaQuery.disableAnimations`).

## 열린 질문 (임의로 정하지 말고 확인 후 진행)

1. **링 색을 아이콘 원본(FF6A55/D6F24E)으로 할지, 앱 팔레트
   (GoColors.coral/lime)로 통일할지.** 지금 코드는 팔레트 통일 쪽으로
   구현돼 있다. 아이콘 원본을 쓰려면 `theme.dart`의 GoColors에 새 토큰을
   추가하고(예: `iconCoral`, `iconLime`) `goingon_brand_motion.dart`의
   `_paintRings`에서 그 토큰을 참조하도록 바꾼다.

2. **인트로가 끝난 뒤 옅은 숨쉬기 루프(`idlePulseAfterIntro: true`)를
   유지할지.** 원래 `_pulse`가 하던 "아직 로딩 중" 신호를 대신하려고
   넣었는데, 손글씨가 다 그려진 뒤라 원래보다 훨씬 은은하다(스케일
   ±1.2%). 네트워크가 느려서 스플래시가 5초 이상 걸릴 수 있는 계정이면
   유지 권장, 항상 1~2초 안에 끝난다면 꺼도 무방(`false`로 넘기면 됨).

3. **최초 실행 최소 노출(2000ms)과 인트로(2700ms)의 관계.** 지금은 둘이
   독립적으로 흘러서 인트로가 700ms 더 길다 — 첫 실행엔 문제없지만,
   재실행(최소 300ms)에서는 인증이 빨리 끝나도 화면은 인트로가 다
   끝날 때까지(2.7s) 자연스럽게 유지된다. 재실행 시에도 매번 2.7초를
   다 보여주는 게 맞는지, 아니면 재실행에서는 인트로를 생략/단축할지는
   제품 판단이 필요하다.

## 참고

- 확정 프로토타입(브라우저에서 재생 가능): 대화에서 전달된
  `goingon_splash_motion.html` — 손으로 만질 최종 기준.
- 타이밍을 조정해야 하면 `goingon_brand_motion.dart`의 `SplashTimeline`
  클래스 상수만 바꾸면 된다. 글자별 손글씨 속도는 `SplashTimeline.k`
  하나로 전체가 스케일된다(0.8 확정).
