import 'package:flutter_test/flutter_test.dart';
import 'package:goingon/services/onboarding/onboarding_progress.dart';
import 'package:goingon/services/onboarding/runner_level.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 온보딩 진행 판정 — 화면이 아니라 **어디로 보낼 것인가**를 지키는 테스트.
///
/// 이 판정이 틀리면 증상이 조용하다: 온보딩을 다시 보거나(짜증), 온보딩을
/// 건너뛴 채 홈에 들어가(홈의 기본값이 없다) 화면이 비어 보인다. 둘 다
/// 크래시가 아니라 로그에 안 남는다
void main() {
  group('가입 뒤 온보딩이 남았는가', () {
    test('레벨이 없으면 남았다', () {
      expect(OnboardingProgress.needsRunnerLevel(null), isTrue);
      expect(OnboardingProgress.needsRunnerLevel({}), isTrue);
      expect(
          OnboardingProgress.needsRunnerLevel(
              {'name': '찬웅', 'username': 'chan'}),
          isTrue);
    });

    test('레벨이 있으면 끝났다 — 초대를 건너뛰었어도', () {
      expect(OnboardingProgress.needsRunnerLevel({'level': 'beginner'}),
          isFalse);
      expect(OnboardingProgress.needsRunnerLevel({'level': 'experienced'}),
          isFalse);
    });

    test('모르는 값이 들어와도 온보딩으로 되돌리지 않는다', () {
      // 규칙이 열거를 강제하지만, 규칙보다 오래된 문서가 있을 수 있다.
      // 값을 못 읽는 것과 답이 없는 것은 다르다 — 답은 이미 했다
      expect(OnboardingProgress.needsRunnerLevel({'level': 'pro'}), isFalse);
      expect(OnboardingProgress.levelOf({'level': 'pro'}), RunnerLevel.beginner);
    });

    test('레벨을 읽으면 홈의 기본값이 나온다', () {
      expect(OnboardingProgress.levelOf({'level': 'experienced'}),
          RunnerLevel.experienced);
      expect(OnboardingProgress.levelOf({'level': 'beginner'}),
          RunnerLevel.beginner);
      expect(OnboardingProgress.levelOf(null), RunnerLevel.beginner);
    });
  });

  group('여덟 걸음은 기기에 남는다', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('처음에는 안 지났고, 표시하면 지난 것이 된다', () async {
      expect(await OnboardingProgress.eightStepsDone(), isFalse);
      await OnboardingProgress.markEightStepsDone();
      expect(await OnboardingProgress.eightStepsDone(), isTrue);
    });
  });
}
