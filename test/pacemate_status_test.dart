import 'package:flutter_test/flutter_test.dart';
import 'package:goingon/services/pacemate_status.dart';

/// 홈 카드의 상태 한 줄. **없는 데이터를 지어내지 않는 것**이 이 함수의
/// 존재 이유라, "무엇을 말하지 않는가"를 같이 못박아 둔다.
void main() {
  // 2026-09-09는 수요일 — 그 주 월요일은 2026-09-07
  final now = DateTime(2026, 9, 9, 14);
  const thisWeek = '2026-09-07';
  const lastWeek = '2026-08-31';

  test('이번 주에 달렸으면 그 사실이 먼저다', () {
    final s = PacemateStatus.of({'lastRunWeek': thisWeek}, now);
    expect(s.tone, PacemateTone.active);
    expect(s.label, '이번 주 달렸어요');
  });

  test('연속 주는 2주부터 붙는다 — 1주 연속은 그냥 이번 주다', () {
    final one = PacemateStatus.of(
        {'lastRunWeek': thisWeek, 'weekStreak': 1}, now);
    expect(one.label, '이번 주 달렸어요');

    final three = PacemateStatus.of(
        {'lastRunWeek': thisWeek, 'weekStreak': 3}, now);
    expect(three.label, '이번 주 달렸어요 · 3주 연속');
    expect(three.tone, PacemateTone.active);
  });

  test('지난주 기록은 active가 아니라 steady', () {
    final s = PacemateStatus.of({'lastRunWeek': lastWeek}, now);
    expect(s.tone, PacemateTone.steady);
    expect(s.label, '지난주에 달렸어요');
  });

  test('그보다 오래됐으면 이번 달 거리로 내려간다', () {
    final s = PacemateStatus.of({
      'lastRunWeek': '2026-08-03',
      'monthKey': '2026-09',
      'monthKm': 12.34,
    }, now);
    expect(s.tone, PacemateTone.steady);
    expect(s.label, '이번 달 12.3km');
  });

  test('monthKey가 지난달이면 monthKm은 이번 달 기록이 아니다', () {
    // 달이 바뀌어도 monthKm은 다음 러닝 전까지 지난달 값을 들고 있다.
    // monthKey를 안 보면 없는 거리를 만들어 내게 된다
    final s = PacemateStatus.of({
      'monthKey': '2026-08',
      'monthKm': 42.0,
    }, now);
    expect(s.tone, PacemateTone.quiet);
    expect(s.label, isNot(contains('42')));
  });

  test('기록이 하나도 없는 새 계정도 죽지 않는다', () {
    expect(PacemateStatus.of(const {}, now).tone, PacemateTone.quiet);
    expect(PacemateStatus.of(null, now).tone, PacemateTone.quiet);
  });

  test('lastRunWeek 형식이 깨져 있어도 화면이 죽지 않는다', () {
    // 옛 데이터·수기 수정으로 파싱 불가능한 값이 들어올 수 있다
    final s = PacemateStatus.of({'lastRunWeek': 'last-week'}, now);
    expect(s.tone, PacemateTone.quiet);
  });

  group('연속 주가 살아 있는가 — 끊긴 연속은 사실이 아니다', () {
    test('이번 주에 달렸으면 살아 있다', () {
      expect(
          PacemateStatus.streakAlive(
              {'lastRunWeek': thisWeek, 'weekStreak': 3}, now),
          isTrue);
    });

    test('지난주에 달렸으면 아직 이을 수 있다', () {
      expect(
          PacemateStatus.streakAlive(
              {'lastRunWeek': lastWeek, 'weekStreak': 3}, now),
          isTrue);
    });

    test('두 주 넘게 비었으면 끊긴 것이다 — 숫자는 남아 있어도', () {
      // weekStreak은 러닝할 때만 갱신되므로 문서에는 3이 그대로 남는다.
      // 그걸 그대로 보여주면 몇 달 전에 멈춘 사람이 "3주 연속"이 된다
      expect(
          PacemateStatus.streakAlive(
              {'lastRunWeek': '2026-08-24', 'weekStreak': 3}, now),
          isFalse);
    });

    test('달린 적이 없으면 살아 있을 수 없다', () {
      expect(PacemateStatus.streakAlive({'weekStreak': 3}, now), isFalse);
      expect(
          PacemateStatus.streakAlive(
              {'lastRunWeek': thisWeek, 'weekStreak': 0}, now),
          isFalse);
      expect(PacemateStatus.streakAlive(null, now), isFalse);
    });
  });

  test('실시간 상태를 말하지 않는다 — 해상도는 주 단위다', () {
    // presence는 보안 규칙상 읽을 수 없다. 시간 단위 문장이 새어 나오면
    // 데이터가 없는 것을 있다고 말하는 것이다
    for (final user in [
      {'lastRunWeek': thisWeek, 'weekStreak': 5},
      {'lastRunWeek': lastWeek},
      {'monthKey': '2026-09', 'monthKm': 3.0},
      const <String, dynamic>{},
    ]) {
      final label = PacemateStatus.of(user, now).label;
      for (final banned in ['지금', '뛰는 중', '온라인', '분 전', '시간 전', '접속']) {
        expect(label, isNot(contains(banned)), reason: label);
      }
    }
  });
}
