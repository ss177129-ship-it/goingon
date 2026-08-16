import 'package:flutter_test/flutter_test.dart';
import 'package:goingon/services/resonance.dart';
import 'package:goingon/services/sound/briefing_script.dart';

/// 1km 브리핑 문장(`docs/sound_ux_v1.md` §3).
///
/// TTS를 띄우지 않고도 문장이 자연스러운지 볼 수 있어야 해서 문자열 생성만
/// 따로 떼어냈다. 여기서 잡는 것은 **읽었을 때 사람 말인가**다 —
/// "지수은 3.4킬로", "5분 0초" 같은 것.
void main() {
  group('문장 구조', () {
    test('3요소가 이 순서로 온다', () {
      final s = BriefingScript.sentence(
        km: 3,
        split: const Duration(minutes: 5, seconds: 32),
        partnerNote: '지수가 힘내래요',
      );
      expect(s, '3킬로. 5분 32초. 지수가 힘내래요.');
    });

    test('요소는 셋을 넘지 않는다', () {
      // 마침표로 끊기는 조각이 셋 — 넷째는 달리면서 안 들린다
      final s = BriefingScript.sentence(
        km: 1,
        split: const Duration(minutes: 6),
        partnerNote: '지수와 함께 달리는 중',
      );
      expect(s.split('.').where((p) => p.trim().isNotEmpty), hasLength(3));
    });
  });

  group('스플릿 읽기', () {
    test('분과 초', () {
      expect(BriefingScript.splitText(const Duration(minutes: 5, seconds: 32)),
          '5분 32초');
    });

    test('초가 0이면 분만 — "5분 0초"는 사람이 하지 않는 말이다', () {
      expect(BriefingScript.splitText(const Duration(minutes: 5)), '5분');
    });

    test('1분이 안 되면 초만', () {
      expect(BriefingScript.splitText(const Duration(seconds: 48)), '48초');
    });
  });

  group('상대 정보 — 우선순위', () {
    test('방금 온 신호가 가장 먼저', () {
      expect(
        BriefingScript.partnerNote(
          name: '지수',
          recentSignal: SignalKind.cheer,
          resonating: true,
          partnerKm: 3.4,
        ),
        '지수가 힘내래요',
      );
    });

    test('신호가 없으면 공명 유지 중', () {
      expect(
        BriefingScript.partnerNote(
            name: '지수', resonating: true, partnerKm: 3.4),
        '지금 나란히예요',
      );
    });

    test('그다음이 상대 누적 거리', () {
      expect(BriefingScript.partnerNote(name: '지수', partnerKm: 3.4),
          '지수는 3.4킬로');
    });

    test('아무것도 모를 때도 상대를 빼지 않는다', () {
      // 지금 실제 세션이 여기 해당한다(상대 거리도 발맞춤도 없음).
      // 그래도 이 앱만 할 수 있는 문장이어야 한다
      expect(BriefingScript.partnerNote(name: '지수'), '지수와 함께 달리는 중');
    });

    test('신호 3종이 각각 다른 말이 된다', () {
      String note(SignalKind k) =>
          BriefingScript.partnerNote(name: '지수', recentSignal: k);
      expect(note(SignalKind.here), '지수가 여기 있대요');
      expect(note(SignalKind.cheer), '지수가 힘내래요');
      expect(note(SignalKind.slow), '지수가 천천히 가재요');
    });
  });

  group('조사', () {
    test('받침이 있으면 이/은/과', () {
      expect(BriefingScript.partnerNote(name: '찬웅', recentSignal: SignalKind.here),
          '찬웅이 여기 있대요');
      expect(BriefingScript.partnerNote(name: '찬웅', partnerKm: 2.0),
          '찬웅은 2.0킬로');
      expect(BriefingScript.partnerNote(name: '찬웅'), '찬웅과 함께 달리는 중');
    });

    test('받침이 없으면 가/는/와', () {
      expect(BriefingScript.partnerNote(name: '지수', recentSignal: SignalKind.here),
          '지수가 여기 있대요');
      expect(BriefingScript.partnerNote(name: '지수', partnerKm: 2.0),
          '지수는 2.0킬로');
      expect(BriefingScript.partnerNote(name: '지수'), '지수와 함께 달리는 중');
    });

    test('한글이 아닌 이름에서도 터지지 않는다', () {
      expect(BriefingScript.partnerNote(name: 'Alex'), 'Alex와 함께 달리는 중');
      expect(BriefingScript.partnerNote(name: ''), '와 함께 달리는 중');
    });
  });
}
