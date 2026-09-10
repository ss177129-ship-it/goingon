// 연습실(staging) Firebase 설정 — `firebase apps:sdkconfig`에서 옮겨 적었다.
//
// **FlutterFire CLI로 만들지 않았다.** `flutterfire configure`는 실행할 때마다
// 운영용 `ios/Runner/GoogleService-Info.plist`와 `firebase_options.dart`를
// 덮어쓴다. 그러면 TestFlight 빌드가 연습실을 보게 되고, 리뷰어 앱이 통째로
// 엉뚱한 데이터를 보게 된다. 그 사고를 아예 불가능하게 하려고 손으로 적었다.
//
// 값이 바뀌면 아래로 다시 뽑는다 (덮어쓰기 없음, 출력만 함):
//   firebase apps:sdkconfig IOS 1:153894173198:ios:85c35ec778f48591581a5f \
//     --project goingon-staging
//
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

/// 연습실 프로젝트(`goingon-staging`)의 iOS 설정.
///
/// 운영(`goingon-c12f3`)과 **번들ID가 같다** — Firebase 프로젝트가 다르면
/// 번들ID는 겹쳐도 된다. 덕분에 `project.pbxproj`도 프로비저닝도 건드리지
/// 않고 연습실에 접속할 수 있다.
///
/// Firestore 리전도 운영과 같은 `nam5`다. 다르게 두면 Functions 트리거
/// 리전이 어긋나서 "연습실에선 됐는데 운영에선 안 되는" 상황이 생긴다 —
/// 그 순간 리허설이 리허설이 아니게 된다.
class StagingFirebaseOptions {
  const StagingFirebaseOptions._();

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCgYjKYHqdEfE-pDqGp3jhBE6smPPoij4w',
    appId: '1:153894173198:ios:85c35ec778f48591581a5f',
    messagingSenderId: '153894173198',
    projectId: 'goingon-staging',
    storageBucket: 'goingon-staging.firebasestorage.app',
    iosBundleId: 'com.chanwoong.goingon',
  );
}
