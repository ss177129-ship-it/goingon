import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:goingon/firebase_env.dart';
import 'package:goingon/firebase_options.dart';
import 'package:goingon/firebase_options_staging.dart';

/// 이 파일이 지키는 약속은 둘이다.
///
/// 1. **표지판이 없으면 운영이다.** `GO_ENV`는 컴파일 시점 상수라
///    TestFlight·App Store 빌드에는 `--dart-define`이 안 들어간다.
/// 2. **커밋된 plist도 언제나 운영이다.** iOS에서는 plist가 실제 스위치라,
///    연습실 상태로 커밋되면 리뷰어 빌드가 연습실 데이터를 보게 된다.
///
/// 둘 다 조용히 틀리는 종류다 — 앱은 멀쩡히 뜨고 로그인도 되기 때문에
/// 화면으로는 잡을 수 없다. `flutter test`는 `--dart-define` 없이 도니까,
/// 여기서 보이는 값이 곧 릴리즈 빌드가 보게 될 값이다.
String _projectIdOf(String path) {
  final text = File(path).readAsStringSync();
  final m = RegExp(
    r'<key>PROJECT_ID</key>\s*<string>([^<]+)</string>',
  ).firstMatch(text);
  expect(m, isNotNull, reason: '$path 에서 PROJECT_ID를 못 찾았다');
  return m!.group(1)!;
}

void main() {
  group('표지판이 없을 때', () {
    test('연습실이 아니다', () {
      expect(FirebaseEnv.isStaging, isFalse);
      expect(FirebaseEnv.label, 'prod');
    });

    test('운영 프로젝트를 기대한다', () {
      expect(FirebaseEnv.expected.projectId, 'goingon-c12f3');
      expect(FirebaseEnv.expected.appId, DefaultFirebaseOptions.ios.appId);
    });
  });

  group('커밋된 plist', () {
    const active = 'ios/Runner/GoogleService-Info.plist';

    test('활성 plist는 운영이다 — 연습실인 채로 커밋되면 안 된다', () {
      expect(_projectIdOf(active), 'goingon-c12f3',
          reason: '연습실 상태로 커밋됐다. ./tools/env.sh prod 를 실행할 것');
    });

    test('활성 plist가 prod 사본과 같다', () {
      expect(
        File(active).readAsStringSync(),
        File('ios/Runner/GoogleService-Info-prod.plist').readAsStringSync(),
      );
    });

    test('연습실 사본은 연습실을 가리킨다', () {
      expect(_projectIdOf('ios/Runner/GoogleService-Info-staging.plist'),
          'goingon-staging');
    });

    test('plist와 Dart 설정이 같은 곳을 말한다', () {
      // 둘이 갈라지면 verify()가 멀쩡한 실행을 어긋났다고 판정하거나,
      // 반대로 어긋난 실행을 통과시킨다
      expect(_projectIdOf(active), DefaultFirebaseOptions.ios.projectId);
      expect(_projectIdOf('ios/Runner/GoogleService-Info-staging.plist'),
          StagingFirebaseOptions.ios.projectId);
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
      expect(
        StagingFirebaseOptions.ios.iosBundleId,
        DefaultFirebaseOptions.ios.iosBundleId,
      );
    });
  });

  group('EnvMismatch', () {
    test('연습실을 보고 있으면 운영으로 되돌리라고 말한다', () {
      const e = EnvMismatch(
          flag: 'prod', expected: 'goingon-c12f3', actual: 'goingon-staging');
      expect(e.remedy, './tools/env.sh prod');
    });

    test('운영을 보고 있으면 연습실로 가라고 말한다', () {
      const e = EnvMismatch(
          flag: 'staging', expected: 'goingon-staging', actual: 'goingon-c12f3');
      expect(e.remedy, './tools/env.sh staging');
      expect(e.toString(), contains('goingon-staging'));
    });
  });
}
