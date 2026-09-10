import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

import 'firebase_options.dart';
import 'firebase_options_staging.dart';

/// 이 빌드가 **어느 Firebase 프로젝트를 보는가**.
///
/// 왜 필요한가: GoingOn은 2인 앱이라 혼자서는 초대·러닝·응원 흐름을 끝까지
/// 밟아볼 수 없다. 그래서 상대 역할을 하는 봇을 띄울 건데, 봇이 만드는 계정과
/// 세션·러닝 기록이 운영 데이터에 섞이면 곤란하다. 더 나쁜 건 그걸 치우는
/// 삭제 스크립트를 운영에 겨눈 채로 계속 유지해야 한다는 점이다 —
/// 조건 하나 잘못 쓰면 실사용자 기록이 날아가고 되돌릴 수 없다.
/// 연습실을 따로 두면 그 스크립트가 **아예 없어도 된다.**
///
/// ## 기본값은 반드시 운영이다
///
/// `String.fromEnvironment`는 컴파일 시점에 박히는 상수이고,
/// TestFlight·App Store 빌드는 `--dart-define`을 주지 않는다. 그래서
/// **표지판이 없으면 무조건 운영**이 되도록 했다. 연습실은 명시적으로
/// 요청해야만 열린다 — 실수로 리뷰어 빌드가 연습실을 보는 일이 구조적으로
/// 일어날 수 없게 하기 위해서다. 이 기본값은 `test/firebase_env_test.dart`가
/// 지킨다.
///
/// ## 쓰는 법
///
/// ```
/// flutter run                                  # 운영
/// flutter run --dart-define=GO_ENV=staging     # 연습실
/// ```
///
/// ## 연습실에서 안 되는 것
///
/// **Google 로그인은 연습실에 OAuth 클라이언트가 없어서 동작하지 않는다.**
/// (운영 plist에만 `CLIENT_ID`/`REVERSED_CLIENT_ID`가 있다.) Apple 로그인은
/// 정상 동작하고, 봇은 custom token으로 들어오므로 지금 검증하려는 흐름에는
/// 지장이 없다. 연습실에서 Google 로그인까지 봐야 할 일이 생기면 그때
/// OAuth 클라이언트를 만들고 URL 스킴을 추가하면 된다.
class FirebaseEnv {
  const FirebaseEnv._();

  static const String _name =
      String.fromEnvironment('GO_ENV', defaultValue: 'prod');

  /// 연습실을 보고 있는가. 화면에 배지를 띄우는 등 눈에 보이는 표시에 쓴다 —
  /// 어느 데이터를 보고 있는지 헷갈린 채로 판단하는 것이 가장 위험하다.
  static bool get isStaging => _name == 'staging';

  /// 로그·배지에 쓰는 이름.
  static String get label => isStaging ? 'staging' : 'prod';

  /// `Firebase.initializeApp(options: ...)`에 넣을 값.
  static FirebaseOptions get options => isStaging
      ? StagingFirebaseOptions.ios
      : DefaultFirebaseOptions.currentPlatform;
}
