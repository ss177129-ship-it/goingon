import '../resonance.dart';

/// 1km 브리핑 문장을 만든다. **소리를 내지 않는 순수 함수만** 여기 둔다 —
/// 문장이 자연스러운지는 읽어보면 알 수 있어야 하고, 그러려면 TTS를 띄우지
/// 않고도 시험할 수 있어야 한다.
///
/// 구조는 설계서(`docs/sound_ux_v1.md` §3)가 고정한 3요소, 이 순서:
/// `"{N}킬로미터. {스플릿}. {상대 정보}."`
///
/// 요소를 넷으로 늘리지 않는다. 달리면서 듣는 문장이라 네 번째는 안 들린다.
class BriefingScript {
  const BriefingScript._();

  /// 단위는 '킬로미터'가 아니라 **'킬로'**다. 설계서 예문은 킬로미터지만
  /// 같은 문서가 정한 4초 상한이 더 강한 규칙이고, 실측에서 최장 문장이
  /// 그것 때문에 4초를 넘겼다(2026-08-16). 상대 요소가 이미 "3.4킬로"라
  /// 말투도 이쪽이 일관된다
  static String sentence({
    required int km,
    required Duration split,
    required String partnerNote,
  }) =>
      '$km킬로. ${splitText(split)}. $partnerNote.';

  /// "5분 32초". 분이나 초가 0이면 그 조각을 빼서 짧게 만든다 —
  /// "5분 0초"는 사람이 하지 않는 말이다
  static String splitText(Duration split) {
    final m = split.inMinutes;
    final s = split.inSeconds % 60;
    if (m == 0) return '$s초';
    if (s == 0) return '$m분';
    return '$m분 $s초';
  }

  /// 상대 정보 한 조각. **절대 비우지 않는다** — 이 문장이 이 앱만 할 수
  /// 있는 말이고, 빼면 그냥 러닝 앱의 안내 음성이 된다.
  ///
  /// 우선순위(해당되는 첫 번째 하나만):
  /// 1. 방금 온 신호  2. 공명 유지 중  3. 상대 누적 거리  4. 함께 달리는 중
  ///
  /// 4번이 있는 이유: 지금 실제 세션에는 상대의 거리도 발맞춤도 없다
  /// (러닝 중 실시간 동기화 없음). 그래도 상대를 언급할 수는 있어야 한다
  static String partnerNote({
    required String name,
    SignalKind? recentSignal,
    bool resonating = false,
    double? partnerKm,
  }) {
    if (recentSignal != null) {
      final what = switch (recentSignal) {
        SignalKind.here => '여기 있대요',
        SignalKind.cheer => '힘내래요',
        SignalKind.slow => '천천히 가재요',
      };
      return '$name${subjectParticle(name)} $what';
    }
    if (resonating) return '지금 나란히예요';
    if (partnerKm != null) {
      return '$name${topicParticle(name)} ${partnerKm.toStringAsFixed(1)}킬로';
    }
    return '$name${withParticle(name)} 함께 달리는 중';
  }

  // ── 조사 ──
  // 받침 유무를 안 따지면 "지수은 3.4킬로"처럼 읽힌다. TTS는 이런 걸
  // 고쳐주지 않고 그대로 읽는다

  /// 이/가
  static String subjectParticle(String word) => _hasFinal(word) ? '이' : '가';

  /// 은/는
  static String topicParticle(String word) => _hasFinal(word) ? '은' : '는';

  /// 과/와
  static String withParticle(String word) => _hasFinal(word) ? '과' : '와';

  /// 마지막 글자에 받침이 있는가. 한글이 아니면 없는 것으로 본다
  static bool _hasFinal(String word) {
    if (word.isEmpty) return false;
    final code = word.runes.last;
    if (code < 0xAC00 || code > 0xD7A3) return false;
    return (code - 0xAC00) % 28 != 0;
  }
}
