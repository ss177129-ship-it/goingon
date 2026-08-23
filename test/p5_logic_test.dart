// P5의 로직 층 — 화면과 무관하게 먼저 못 박아두는 것들.
//
// 와이어프레임 없이도 확정할 수 있는 판정만 여기 있다: 레벨의 기본값,
// '오늘의 상대'의 우선순위, 알림 권한을 묻는 시점.
import 'package:flutter_test/flutter_test.dart';
import 'package:goingon/services/ghost/ghost_run.dart';
import 'package:goingon/services/ghost/today_partner.dart';
import 'package:goingon/services/onboarding/push_permission_gate.dart';
import 'package:goingon/services/onboarding/runner_level.dart';

GhostRun _g(String id, {String? uid, String? story, int seconds = 480}) =>
    GhostRun(
      id: id,
      uid: uid ?? 'someone',
      startedAt: DateTime.utc(2026, 8, 20),
      duration: Duration(seconds: seconds),
      km: 1.4,
      cadence: List.filled(seconds, 165.0),
      story: story,
    );

void main() {
  group('레벨 — 온보딩 질문 하나', () {
    test('모르면 입문자', () {
      expect(RunnerLevel.fromWire(null), RunnerLevel.beginner);
      expect(RunnerLevel.fromWire('알수없음'), RunnerLevel.beginner,
          reason: '경험자에게 8분은 보너스지만, 입문자에게 자유런은 막막함이다');
      expect(RunnerLevel.fromWire('experienced'), RunnerLevel.experienced);
    });

    test('선택지가 숫자를 묻지 않는다', () {
      for (final l in RunnerLevel.values) {
        expect(RegExp(r'\d').hasMatch(l.choiceLabel), isFalse,
            reason: '"주 몇 회"는 기록이 부끄러운 사람에게 첫 질문부터 시험이 된다');
      }
    });
  });

  group("'오늘의 상대' 우선순위 (§3-3 1막)", () {
    test('페이스메이트 → 나의 과거 → 사연 고스트 순', () {
      final out = TodayPartnerPicker.rank(
        fromPacemates: [_g('p1')],
        mine: [_g('m1', uid: 'me')],
        seeds: [_g('s1')],
      );
      expect(out.map((e) => e.reason).toList(),
          [PartnerReason.pacemate, PartnerReason.myPast, PartnerReason.seed]);
    });

    test('나의 과거는 두 개까지만 — 전부 내 것이면 회고가 된다', () {
      final out = TodayPartnerPicker.rank(
        mine: [for (var i = 0; i < 5; i++) _g('m$i', uid: 'me')],
        seeds: [_g('s1')],
      );
      expect(out.where((e) => e.reason == PartnerReason.myPast), hasLength(2));
      expect(out.last.reason, PartnerReason.seed);
    });

    test('같은 고스트는 두 번 나오지 않는다', () {
      final same = _g('dup');
      final out =
          TodayPartnerPicker.rank(fromPacemates: [same], seeds: [same, _g('s2')]);
      expect(out.map((e) => e.ghost.id).toList(), ['dup', 's2']);
    });

    test('2분 미만은 후보가 아니다', () {
      final out = TodayPartnerPicker.rank(
          fromPacemates: [_g('short', seconds: 100), _g('ok')]);
      expect(out.map((e) => e.ghost.id).toList(), ['ok']);
    });

    test('같은 층 안에서는 사연 있는 쪽이 앞', () {
      final out = TodayPartnerPicker.rank(fromPacemates: [
        _g('no-story'),
        _g('has-story', story: '오늘은 바람이 셌어요'),
      ]);
      expect(out.first.ghost.id, 'has-story',
          reason: '맥락이 있는 쪽이 고르기 쉽고, 그게 사연 채집의 보상이다');
    });

    test('상한을 넘기지 않는다', () {
      final out = TodayPartnerPicker.rank(
        fromPacemates: [for (var i = 0; i < 20; i++) _g('p$i')],
      );
      expect(out.length, TodayPartnerPicker.kMax);
    });
  });

  group('알림 권한 — 카드는 한 장뿐', () {
    test('첫 완주 전에는 묻지 않는다', () {
      expect(
          PushPermissionGate.shouldAsk(completedRuns: 0, alreadyAsked: false),
          isFalse,
          reason: '이 앱이 뭔지 모르는 사람에게 알림을 물으면 거절이 기본값이 된다');
    });

    test('첫 완주 직후에 묻는다', () {
      expect(PushPermissionGate.shouldAsk(completedRuns: 1, alreadyAsked: false),
          isTrue);
    });

    test('한 번 물었으면 다시 묻지 않는다', () {
      expect(PushPermissionGate.shouldAsk(completedRuns: 9, alreadyAsked: true),
          isFalse, reason: 'iOS는 두 번째 기회를 주지 않는다');
    });

    test('데모 완주로는 카드를 쓰지 않는다', () {
      expect(
          PushPermissionGate.shouldAsk(
              completedRuns: 1, alreadyAsked: false, isDemo: true),
          isFalse,
          reason: '심사관의 데모 체험이 진짜 유저의 카드를 소모하면 안 된다');
    });
  });
}
