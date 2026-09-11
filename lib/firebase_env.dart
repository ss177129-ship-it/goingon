import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'firebase_options_staging.dart';

/// 이 빌드가 **어느 Firebase 프로젝트를 보는가**, 그리고 그게 의도한 것인가.
///
/// 왜 필요한가: GoingOn은 2인 앱이라 혼자서는 초대·러닝·응원 흐름을 끝까지
/// 밟아볼 수 없다. 그래서 상대 역할을 하는 봇을 띄울 건데, 봇이 만드는 계정과
/// 세션·러닝 기록이 운영 데이터에 섞이면 곤란하다. 더 나쁜 건 그걸 치우는
/// 삭제 스크립트를 운영에 겨눈 채로 계속 유지해야 한다는 점이다 —
/// 조건 하나 잘못 쓰면 실사용자 기록이 날아가고 되돌릴 수 없다.
/// 연습실을 따로 두면 그 스크립트가 **아예 없어도 된다.**
///
/// ## 전환하는 것은 plist이지 이 플래그가 아니다
///
/// **2026-09-10에 알아낸 것:** firebase_core 플러그인이 Dart의 `main()`보다
/// 먼저 `GoogleService-Info.plist`를 읽어 `[DEFAULT]` 앱을 만든다. 그래서
/// iOS에서는 plist가 이기고, Dart의 `FirebaseOptions`로는 프로젝트를 바꿀 수
/// 없다. 다른 설정으로 다시 만들려 하면 `[core/duplicate-app]`이 나는데, 그
/// 예외가 `runApp()`까지 못 가게 막아 **런치 스크린인 채로 멈춘다** —
/// 크래시도 에러 화면도 없어서 원인이 보이지 않는다. 실제로 여기서 한 번
/// 헤맸다.
///
/// 그래서 역할을 이렇게 나눴다:
///
/// * **`tools/env.sh`** 가 plist를 바꾼다 — 이게 진짜 스위치다
/// * **`GO_ENV` 플래그**는 "내가 어디에 있다고 생각하는지"를 말한다
/// * **[verify]** 가 둘이 일치하는지 본다. 어긋나면 시작하자마자 멈춘다
///
/// 둘 중 **어느 쪽을 잊어도 잡힌다.** plist만 바꾸고 플래그를 안 주면
/// "운영인 줄 알았는데 연습실"이고, 플래그만 주고 plist를 안 바꾸면
/// "연습실인 줄 알았는데 운영"이다. 후자가 특히 위험하다 — 봇이 운영에
/// 데이터를 만들기 시작하는 경로가 바로 그것이기 때문이다.
///
/// ## 기본값은 반드시 운영이다
///
/// `String.fromEnvironment`는 컴파일 시점 상수이고, TestFlight·App Store
/// 빌드는 `--dart-define`을 주지 않는다. 그래서 **표지판이 없으면 무조건
/// 운영**이 되도록 했다. 저장소에 커밋된 plist도 언제나 운영이어야 한다 —
/// 둘 다 `test/firebase_env_test.dart`가 지킨다.
///
/// ## 쓰는 법
///
/// ```
/// ./tools/env.sh staging
/// flutter run --dart-define=GO_ENV=staging
///
/// ./tools/env.sh prod
/// flutter run
/// ```
///
/// ## 연습실에서 안 되는 것
///
/// **Google 로그인은 연습실에 OAuth 클라이언트가 없어서 동작하지 않는다.**
/// (운영 plist에만 `CLIENT_ID`/`REVERSED_CLIENT_ID`가 있다.) Apple 로그인은
/// 정상 동작하고, 봇은 custom token으로 들어오므로 지금 검증하려는 흐름에는
/// 지장이 없다.
class FirebaseEnv {
  const FirebaseEnv._();

  static const String _name =
      String.fromEnvironment('GO_ENV', defaultValue: 'prod');

  /// 연습실을 보고 있다고 **주장**하는가. 실제로 그런지는 [verify]가 본다.
  static bool get isStaging => _name == 'staging';

  /// 로그·배지에 쓰는 이름.
  static String get label => isStaging ? 'staging' : 'prod';

  /// 이 플래그가 기대하는 설정. 실제 값과 대조하는 데만 쓴다 —
  /// `initializeApp`에 넘기지 않는다 (위 주석 참조).
  static FirebaseOptions get expected =>
      isStaging ? StagingFirebaseOptions.ios : DefaultFirebaseOptions.ios;

  /// 실제로 초기화된 프로젝트가 플래그와 일치하는지 본다.
  ///
  /// 어긋났을 때 **조용히 넘어가지 않는 것**이 이 함수의 전부다. 어긋난
  /// 상태로 계속 돌면 봇이나 개발 빌드가 운영 데이터를 건드리게 되고,
  /// 그건 화면만 봐서는 알 수 없다 — 앱이 멀쩡히 뜨고 로그인도 되기 때문이다.
  ///
  /// 어긋나면 [EnvMismatch]를 던진다. 부르는 쪽이 잡아서 사람이 읽을 수 있는
  /// 화면을 띄운다.
  static void verify() {
    final actual = Firebase.app().options.projectId;
    if (actual != expected.projectId) {
      throw EnvMismatch(flag: _name, expected: expected.projectId, actual: actual);
    }
  }
}

/// plist와 `GO_ENV` 플래그가 서로 다른 곳을 가리킬 때.
class EnvMismatch implements Exception {
  const EnvMismatch({
    required this.flag,
    required this.expected,
    required this.actual,
  });

  /// `--dart-define=GO_ENV`로 들어온 값 (없으면 'prod')
  final String flag;

  /// 그 플래그가 기대한 프로젝트
  final String expected;

  /// plist가 실제로 물고 온 프로젝트
  final String actual;

  /// 무엇을 해야 하는지까지 알려준다 — 이 상황에서 필요한 것은 진단이 아니라
  /// "그래서 뭘 치면 되는가"이다
  String get remedy => actual == 'goingon-staging'
      ? './tools/env.sh prod'
      : './tools/env.sh staging';

  @override
  String toString() =>
      'EnvMismatch: GO_ENV=$flag 는 $expected 를 기대했는데 '
      'plist는 $actual 를 가리킨다. 고치려면: $remedy';
}
