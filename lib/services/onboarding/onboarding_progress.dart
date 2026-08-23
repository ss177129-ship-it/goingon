import 'package:shared_preferences/shared_preferences.dart';

import 'runner_level.dart';

/// 온보딩이 어디까지 왔는가.
///
/// 두 곳에 나눠 담는다 — 나눈 게 아니라 **주인이 다르다**:
///   · 여덟 걸음은 가입 **전**이라 계정이 없다. 기기(prefs)가 유일한 주인이다
///   · 레벨은 계정의 성질이다. 폰을 바꿔도 따라와야 하고 홈이 매번 읽는다
class OnboardingProgress {
  const OnboardingProgress._();

  static const eightStepsKey = 'onboarding_eight_steps_v1';

  static Future<bool> eightStepsDone() async =>
      (await SharedPreferences.getInstance()).getBool(eightStepsKey) ?? false;

  static Future<void> markEightStepsDone() async =>
      (await SharedPreferences.getInstance()).setBool(eightStepsKey, true);

  /// 가입 뒤 온보딩(데모런 → 레벨 → 초대)이 아직 남았는가.
  ///
  /// **레벨 하나로 판정한다.** 셋을 각각 기록하면 어중간한 조합마다
  /// "그럼 어디로 보낼 것인가"가 새로 생긴다. 반드시 답이 있어야 하는 것은
  /// 홈의 기본값 하나뿐이고, 데모런과 초대는 둘 다 지나쳐도 되는 것들이다
  static bool needsRunnerLevel(Map<String, dynamic>? profile) =>
      profile == null || (profile['level'] as String?) == null;

  /// 저장된 답. 없으면 입문자 — 틀렸을 때의 비용이 한쪽으로 기울어 있다
  /// ([RunnerLevel.fromWire] 참조)
  static RunnerLevel levelOf(Map<String, dynamic>? profile) =>
      RunnerLevel.fromWire(profile?['level'] as String?);
}
