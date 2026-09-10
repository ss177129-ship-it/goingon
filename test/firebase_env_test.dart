import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goingon/firebase_env.dart';
import 'package:goingon/firebase_options.dart';
import 'package:goingon/firebase_options_staging.dart';

/// 이 파일이 지키는 약속은 하나다: **표지판이 없으면 운영이다.**
///
/// 왜 테스트로까지 못 박는가. `GO_ENV`는 컴파일 시점 상수라 TestFlight·
/// App Store 빌드에는 `--dart-define`이 안 들어간다. 그래서 기본값이 한 번
/// 잘못 바뀌면 **릴리즈 빌드가 조용히 연습실 데이터를 보게 된다.** 화면은
/// 멀쩡히 뜨고 로그인도 되기 때문에 눈으로는 못 잡는다 — 리뷰어가 자기
/// 기록이 사라졌다고 말해줘야 아는 종류의 사고다.
///
/// `flutter test`는 `--dart-define` 없이 도니까, 여기서 보이는 값이 곧
/// 릴리즈 빌드가 보게 될 값이다.
void main() {
  group('표지판이 없을 때', () {
    test('연습실이 아니다', () {
      expect(FirebaseEnv.isStaging, isFalse);
      expect(FirebaseEnv.label, 'prod');
    });

    test('운영 프로젝트를 가리킨다', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(FirebaseEnv.options.projectId, 'goingon-c12f3');
      expect(FirebaseEnv.options.appId, DefaultFirebaseOptions.ios.appId);
    });
  });

  group('두 환경은 실제로 다른 곳을 가리킨다', () {
    test('프로젝트·앱ID·버킷이 모두 다르다', () {
      const prod = DefaultFirebaseOptions.ios;
      const staging = StagingFirebaseOptions.ios;

      expect(staging.projectId, isNot(prod.projectId));
      expect(staging.appId, isNot(prod.appId));
      expect(staging.storageBucket, isNot(prod.storageBucket));
      expect(staging.messagingSenderId, isNot(prod.messagingSenderId));
    });

    test('번들ID는 같다 — 그래서 pbxproj를 안 건드려도 된다', () {
      // Firebase 프로젝트가 다르면 번들ID는 겹쳐도 된다. 이 덕분에 프로비저닝
      // 프로파일도 entitlements도 그대로 쓴다. 이게 깨지면 연습실 접속에
      // Xcode 설정 변경이 따라붙게 되므로, 값이 갈라지면 알아야 한다.
      expect(
        StagingFirebaseOptions.ios.iosBundleId,
        DefaultFirebaseOptions.ios.iosBundleId,
      );
    });
  });
}
