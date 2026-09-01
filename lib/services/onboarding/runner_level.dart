// 온보딩 질문 하나가 정하는 것 — 홈의 기본값.
//
// **질문은 하나뿐이다**(§2-3). 온보딩에서 묻는 것마다 이탈이 생기고, 우리가
// 정말 알아야 하는 것은 "이 사람의 결핍이 무엇인가" 하나다:
//   · 입문자의 결핍은 "러닝이 부담" → 8분 완결이 약
//   · 경험자의 결핍은 "함께의 부재" → 연결 레이어가 약
// 연결 레이어(공명·고스트·응원·여정)는 길이를 가리지 않으므로 제품 하나로
// 두 결핍을 다 다룬다. 갈라지는 것은 홈의 첫 화면뿐이다.
enum RunnerLevel {
  /// 이제 시작하거나 가끔 달리는 사람
  beginner('beginner'),

  /// 꾸준히 달리는 사람
  experienced('experienced');

  const RunnerLevel(this.wire);

  final String wire;

  /// 모르면 입문자로 본다. 경험자에게 8분을 권하는 것은 "이왕 나온 김에"로
  /// 이어지지만, 입문자에게 자유런을 여는 것은 막막함으로 이어진다 —
  /// 틀렸을 때의 비용이 한쪽으로 기울어 있다
  static RunnerLevel fromWire(String? s) =>
      values.firstWhere((v) => v.wire == s, orElse: () => beginner);

  /// 온보딩에서 보여줄 선택지. **숫자를 묻지 않는다** — "주 몇 회"나
  /// "몇 km"는 기록이 부끄러운 1차 세그먼트(D-006)에게 첫 질문부터
  /// 시험처럼 느껴진다
  String get choiceLabel => switch (this) {
        RunnerLevel.beginner => '이제 시작하거나, 가끔 달려요',
        RunnerLevel.experienced => '꾸준히 달리는 편이에요',
      };
}
