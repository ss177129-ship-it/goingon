// 알림 권한을 **언제** 물을 것인가.
//
// iOS는 한 번 거절당하면 앱이 다시 묻지 못한다(설정에서 켜야 하고, 아무도
// 안 켠다). 그래서 이 질문은 딱 한 번 쓸 수 있는 카드다. 카드를 언제 쓰느냐가
// 곧 알림 수신율이고, 알림 수신율이 고스트런 3막(§3-3)의 루프를 살린다.
//
// **첫 완주 직후에 묻는다**(P5). 이전에는 프로필이 준비된 뒤 RootScreen
// 진입에서 물었는데, 그 시점의 유저는 아직 이 앱이 무엇인지 모른다 —
// "알림을 보내도 될까요?"에 그렇다고 할 이유가 없다. 첫 8분을 완주한
// 직후에는 다르다: 방금 좋은 것을 겪었고, 그 다음이 궁금하다.
//
// 판정을 이 파일 하나에 모아 둔 이유: 조건이 화면마다 흩어지면 어느 화면이
// 먼저 뜨느냐에 따라 카드가 엉뚱한 데서 소모된다.
class PushPermissionGate {
  const PushPermissionGate._();

  /// 지금 물어도 되는가.
  ///
  /// [completedRuns]는 완주한 러닝 수(부분 완주는 세지 않는다 — 4분에서
  /// 그만둔 사람에게 "알림 받을래요?"는 이르다).
  /// [alreadyAsked]가 true면 카드는 이미 쓰였다. 다시 묻지 않는다.
  /// [isDemo]는 심사관용 데모 — 데모를 완주했다고 권한을 묻지 않는다.
  static bool shouldAsk({
    required int completedRuns,
    required bool alreadyAsked,
    bool isDemo = false,
  }) =>
      !alreadyAsked && !isDemo && completedRuns >= 1;

  /// 물어본 적이 있다는 사실을 어디에 남기는가.
  ///
  /// 기기 로컬이다(서버가 아니라). 권한은 기기의 성질이고, 폰을 바꾸면
  /// 다시 물을 수 있어야 한다 — 새 기기에서는 카드가 새로 생긴다
  static const prefsKey = 'push_permission_asked_v1';
}
