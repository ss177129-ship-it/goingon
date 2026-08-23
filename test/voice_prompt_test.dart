import 'package:flutter_test/flutter_test.dart';
import 'package:goingon/services/cooldown/voice_prompt.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 사연이 들어오는 유일한 문을 지키는 테스트.
///
/// 틀렸을 때의 증상이 양쪽 다 조용하다 — 너무 자주 물으면 사람들이 아예
/// 안 보게 되고(로그에 안 남는다), 너무 안 물으면 사연 공급이 마른다.
void main() {
  final now = DateTime(2026, 8, 23, 20);

  group('언제 묻는가', () {
    test('처음에는 매번 묻는다', () {
      expect(
          VoicePrompt.shouldAsk(
              consecutiveSkips: 0, lastAskedAt: null, now: now),
          isTrue);
      expect(
          VoicePrompt.shouldAsk(
              consecutiveSkips: 2,
              lastAskedAt: now.subtract(const Duration(minutes: 1)),
              now: now),
          isTrue);
    });

    test('세 번 연속 지나치면 방금 물었어도 다시 묻지 않는다', () {
      expect(
          VoicePrompt.shouldAsk(
              consecutiveSkips: VoicePrompt.kQuietAfter,
              lastAskedAt: now.subtract(const Duration(days: 6)),
              now: now),
          isFalse);
    });

    test('내려간 뒤에도 일주일이 지나면 다시 묻는다', () {
      expect(
          VoicePrompt.shouldAsk(
              consecutiveSkips: 9,
              lastAskedAt: now.subtract(VoicePrompt.kQuietInterval),
              now: now),
          isTrue);
    });

    test('부분 완주와 데모에는 묻지 않는다', () {
      expect(
          VoicePrompt.shouldAsk(
              consecutiveSkips: 0,
              lastAskedAt: null,
              now: now,
              completed: false),
          isFalse);
      expect(
          VoicePrompt.shouldAsk(
              consecutiveSkips: 0,
              lastAskedAt: null,
              now: now,
              isDemo: true),
          isFalse);
    });
  });

  group('연속이지 누적이 아니다', () {
    test('한 번 대답하면 0으로 돌아간다', () {
      expect(VoicePrompt.nextSkips(current: 5, answered: true), 0);
    });

    test('지나치면 하나씩 쌓인다', () {
      expect(VoicePrompt.nextSkips(current: 0, answered: false), 1);
      expect(VoicePrompt.nextSkips(current: 2, answered: false), 3);
    });

    test('대답 한 번이 문을 다시 연다', () async {
      SharedPreferences.setMockInitialValues({
        VoicePrompt.skipsKey: 3,
        VoicePrompt.lastAskedKey: now.toIso8601String(),
      });
      expect(await VoicePrompt.shouldAskNow(now: now), isFalse);
      await VoicePrompt.record(answered: true, now: now);
      expect(await VoicePrompt.shouldAskNow(now: now), isTrue);
    });
  });
}
