import 'package:shared_preferences/shared_preferences.dart';

/// "오늘 러닝, 어땠어요?"를 **언제 물을 것인가**(§5-2).
///
/// 이 질문은 이 앱에서 사연이 들어오는 유일한 문이다 — 사연 아카이브도,
/// 러닝 카드의 캡션도, 릴레이 한 마디도 전부 여기서 나온다. 그래서 자주
/// 묻고 싶어지는데, 자주 물어서 매번 지나쳐지면 문이 있으나 마나가 된다.
///
/// **세 번 연속 지나치면 주 1회로 내린다.** 대답하지 않는 것은 거부가 아니라
/// "지금은 아니다"이고, 그걸 매번 다시 묻는 건 조르는 것이다. 한 번이라도
/// 대답하면 다시 매번 묻는다 — 마음이 열린 사람에게는 문이 자주 있는 게 낫다.
class VoicePrompt {
  const VoicePrompt._();

  /// 이만큼 연속으로 지나치면 빈도를 내린다
  static const kQuietAfter = 3;

  /// 내려간 뒤의 간격
  static const kQuietInterval = Duration(days: 7);

  /// 한 마디의 상한. 이보다 길어지면 그건 한 마디가 아니라 이야기이고,
  /// 완주 직후 숨찬 사람이 20초 넘게 말할 일도 없다
  static const kMaxLength = Duration(seconds: 20);

  static const skipsKey = 'voice_prompt_skips_v1';
  static const lastAskedKey = 'voice_prompt_last_asked_v1';

  /// 지금 물어도 되는가.
  ///
  /// [completed]가 false면 묻지 않는다 — 4분에서 그만둔 사람에게 "오늘 어땠어요?"는
  /// 질문이 아니라 지적이다. [isDemo]도 마찬가지로 묻지 않는다(심사관의 체험에
  /// 마이크 권한 팝업을 끼워 넣지 않는다).
  static bool shouldAsk({
    required int consecutiveSkips,
    required DateTime? lastAskedAt,
    required DateTime now,
    bool completed = true,
    bool isDemo = false,
  }) {
    if (!completed || isDemo) return false;
    if (consecutiveSkips < kQuietAfter) return true;
    if (lastAskedAt == null) return true;
    return now.difference(lastAskedAt) >= kQuietInterval;
  }

  /// 지나친 뒤의 연속 횟수. 대답하면 0으로 돌아간다 —
  /// **누적이 아니라 연속**이라는 게 요점이다
  static int nextSkips({required int current, required bool answered}) =>
      answered ? 0 : current + 1;

  // ── 기기에 남는 값 ───────────────────────────────────────────
  // 계정이 아니라 기기에 두는 이유: 폰을 바꾸면 다시 매번 묻는 게 맞다.
  // 새 기기는 새 습관이고, 옛 폰에서 세 번 지나쳤다는 사실이 새 폰까지
  // 따라와 문을 좁힐 이유가 없다

  static Future<bool> shouldAskNow({
    required DateTime now,
    bool completed = true,
    bool isDemo = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString(lastAskedKey);
    return shouldAsk(
      consecutiveSkips: prefs.getInt(skipsKey) ?? 0,
      lastAskedAt: last == null ? null : DateTime.tryParse(last),
      now: now,
      completed: completed,
      isDemo: isDemo,
    );
  }

  /// 물어본 사실과 그 결과를 남긴다
  static Future<void> record({
    required bool answered,
    required DateTime now,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      skipsKey,
      nextSkips(current: prefs.getInt(skipsKey) ?? 0, answered: answered),
    );
    await prefs.setString(lastAskedKey, now.toIso8601String());
  }
}
