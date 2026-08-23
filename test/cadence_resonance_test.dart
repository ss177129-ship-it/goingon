// P2 — 공명 판정의 입력이 케이던스가 됐다.
//
// 여기서 지키는 것 셋:
//   1. 케이던스 차이가 §1-3의 문턱과 정확히 맞물리는가 (Δ3 → 공명 문턱 위)
//   2. 정수비 폴리리듬이 열리되, 아무 데서나 열리지는 않는가
//   3. **시차 공명이 라이브 공명과 같은 판정을 타는가** — 고스트가 열등한
//      대체재가 아니라는 설계 결정(D-001)이 코드에서 지켜지는지
import 'package:flutter_test/flutter_test.dart';
import 'package:goingon/services/cadence/partner_cadence.dart';
import 'package:goingon/services/resonance.dart';

Duration _secs(double s) =>
    Duration(microseconds: (s * Duration.microsecondsPerSecond).round());

void main() {
  final t0 = DateTime.utc(2026, 8, 22, 6);

  group('케이던스 → 발맞춤 사상', () {
    test('같으면 1.0, 30spm 벌어지면 0', () {
      expect(CadenceMatch.closeness(170, 170), 1.0);
      expect(CadenceMatch.closeness(150, 180), 0.0);
    });

    test('§1-3의 3spm이 공명 진입 문턱 위에 온다', () {
      // 이것이 맞지 않으면 문서와 코드가 다른 말을 하는 것이다
      final at3 = CadenceMatch.closeness(170, 173)!;
      expect(at3, greaterThan(ResonanceThresholds.resonantEnter));
      final at6 = CadenceMatch.closeness(170, 176)!;
      expect(at6, closeTo(ResonanceThresholds.resonantExit, 0.001),
          reason: 'Δ6이 정확히 이탈 문턱 — 문턱 표를 케이던스 축으로 읽을 수 있다');
      expect(CadenceMatch.closeness(170, 179)!,
          closeTo(ResonanceThresholds.alignedEnter, 0.001));
    });

    test('방향은 상관없다', () {
      expect(CadenceMatch.closeness(160, 175),
          CadenceMatch.closeness(175, 160));
    });

    test('한쪽이라도 모르면 null — 0이 아니다', () {
      expect(CadenceMatch.closeness(null, 170), isNull);
      expect(CadenceMatch.closeness(170, null), isNull);
    });

    test('사람의 대역 밖이면 null — 헛것을 발맞춤 0이라 단정하지 않는다', () {
      expect(CadenceMatch.closeness(170, 999), isNull);
      expect(CadenceMatch.closeness(0, 170), isNull);
      expect(CadenceMatch.closeness(170, double.nan), isNull);
    });
  });

  group('정수비 폴리리듬 (§1-3)', () {
    test('1:2 — 내가 뛰고 상대가 걸으면 공명이 열린다', () {
      expect(CadenceMatch.isResonantGap(176, 88), isTrue);
      expect(CadenceMatch.closeness(176, 88), 1.0);
    });

    test('2:3 — 180 대 120도 공명이다', () {
      expect(CadenceMatch.isResonantGap(180, 120), isTrue);
    });

    test('정수비에서 벗어나면 열리지 않는다', () {
      expect(CadenceMatch.isResonantGap(176, 100), isFalse,
          reason: '100은 88(1:2)에서도 117(2:3)에서도 멀다');
    });

    test('달리는 사람 둘 사이에서 정수비가 공명을 만들지는 않는다', () {
      // 러닝 대역(140~190)을 전부 훑는다. 정수비가 발맞춤 값을 조금 올리는
      // 경우는 있다(140 대 170에서 170×2/3=113 쪽으로 접혀 차이가 30→26.7).
      // 그러나 **공명이 열리려면 접힌 차이가 3spm 이내**여야 하고, 그건
      // 러닝 대역 안에서는 실제로 가까울 때만 성립한다. 정수비 때문에
      // 엉뚱한 짝이 공명하는 일은 없다는 것이 지켜야 할 선이다.
      for (var mine = 140.0; mine <= 190; mine += 1) {
        for (var theirs = 140.0; theirs <= 190; theirs += 1) {
          final direct = (mine - theirs).abs();
          expect(CadenceMatch.isResonantGap(mine, theirs), direct <= 3,
              reason: '$mine vs $theirs — 직접 차이 $direct');
        }
      }
    });
  });

  group('공명 진입 8초 · 해제 10초 (§1-3)', () {
    /// [mine]/[theirs]를 [seconds]초 동안 0.5초 간격으로 흘려 넣는다
    DateTime feed(ResonanceEngine e, DateTime from, double mine, double theirs,
        {required double seconds}) {
      var at = from;
      final until = from.add(_secs(seconds));
      while (at.isBefore(until)) {
        at = at.add(_secs(0.5));
        e.addCadences(mine: mine, theirs: theirs, at: at);
      }
      return at;
    }

    test('Δ2spm이어도 8초를 못 채우면 공명이 아니다', () async {
      final e = ResonanceEngine();
      final at = feed(e, t0, 170, 172, seconds: 6);
      expect(e.state, isNot(SyncState.resonant));
      feed(e, at, 170, 172, seconds: 4);
      expect(e.state, SyncState.resonant);
      e.dispose();
    });

    test('잠깐 벌어져도 10초를 못 채우면 깨지지 않는다', () async {
      final e = ResonanceEngine();
      var at = feed(e, t0, 170, 172, seconds: 12);
      expect(e.state, SyncState.resonant);

      // 신호등에서 6초 벌어짐 — 공명은 유지되어야 한다
      at = feed(e, at, 170, 145, seconds: 6);
      expect(e.state, SyncState.resonant,
          reason: '어렵게 얻은 것이 6초 만에 깨지면 러닝이 시험이 된다');

      // 계속 벌어지면 해제
      feed(e, at, 170, 145, seconds: 8);
      expect(e.state, isNot(SyncState.resonant));
      e.dispose();
    });

    test('해제에 실패음이 붙지 않는다 — 이벤트는 전이뿐', () async {
      final e = ResonanceEngine();
      final events = <ResonanceEvent>[];
      e.events.listen(events.add);
      var at = feed(e, t0, 170, 171, seconds: 12);
      await pumpEventQueue(); // 스트림은 비동기 — 비우기 전에 도착시킨다
      events.clear();
      feed(e, at, 170, 140, seconds: 14);
      await pumpEventQueue();
      // 해제는 상태 전이로만 알린다. 별도의 '깨짐' 이벤트는 존재하지 않는다.
      // (벌어지는 동안에도 아직 공명이므로 유지 알림은 계속 날 수 있다 —
      //  그건 실패가 아니라 "아직 함께"라는 사실이다)
      expect(events.every((x) => x is ResonanceStateChanged || x is ResonanceHeld),
          isTrue,
          reason: '해제에 붙는 별도 이벤트가 생기면 거기에 실패음이 붙는다');
      expect(events.whereType<ResonanceStateChanged>().last.from,
          SyncState.resonant);
      e.dispose();
    });

    test('모르는 값은 아무 일도 일으키지 않는다', () {
      final e = ResonanceEngine();
      expect(e.addCadences(mine: 170, theirs: null, at: t0), isNull);
      expect(e.hasCloseness, isFalse,
          reason: '상대를 모르는데 상태어를 말하면 거짓말이 된다');
      e.dispose();
    });
  });

  group('입력 소스 — 라이브와 고스트가 같은 문으로', () {
    test('라이브는 낡으면 모른다고 답한다', () {
      final live = LivePartnerCadence();
      live.update(spm: 168, at: t0);
      expect(live.spmAt(elapsed: Duration.zero, now: t0.add(_secs(3))), 168);
      expect(live.spmAt(elapsed: Duration.zero, now: t0.add(_secs(9))), isNull,
          reason: '옛 값으로 나란히 달린다고 말하면 그건 거짓말이다');
    });

    test('고스트는 세션 경과 시간축으로 답한다 — 벽시계와 무관', () {
      final ghost = GhostCadenceTimeline([160, 165, 170, null, 172]);
      // 벽시계를 아무리 바꿔도 답이 같다: 장소도 시각도 독립(§3-2)
      for (final now in [t0, t0.add(const Duration(days: 3))]) {
        expect(ghost.spmAt(elapsed: _secs(2), now: now), 170);
        expect(ghost.spmAt(elapsed: _secs(3), now: now), isNull);
      }
      expect(ghost.isExhausted(elapsed: _secs(5)), isTrue);
      expect(ghost.isExhausted(elapsed: _secs(4)), isFalse);
    });

    test('delta 압축은 되돌려도 같은 값이다', () {
      final original = GhostCadenceTimeline([158, 161, 160, null, 173, 174]);
      final back = GhostCadenceTimeline.fromDeltas(original.toDeltas());
      expect(back.spmPerSecond, original.spmPerSecond);
    });

    test('여러 출처는 앞의 것이 우선', () {
      final live = LivePartnerCadence();
      final ghost = GhostCadenceTimeline([120, 121, 122]);
      final both = FirstAvailableCadence([live, ghost]);
      expect(both.spmAt(elapsed: _secs(1), now: t0), 121,
          reason: '라이브가 비면 고스트가 답한다');
      live.update(spm: 175, at: t0);
      expect(both.spmAt(elapsed: _secs(1), now: t0), 175);
    });

    test('시차 공명은 라이브 공명과 같은 판정을 탄다', () async {
      // 같은 케이던스 열을 라이브로 한 번, 고스트로 한 번 흘려 넣으면
      // 결과가 같아야 한다. 다르면 고스트런이 '가짜 함께'가 된다
      final series = List<double?>.generate(30, (i) => 171);
      SyncState runWith(PartnerCadenceSource source) {
        final e = ResonanceEngine();
        for (var i = 0; i < 30; i++) {
          final now = t0.add(_secs(i.toDouble()));
          if (source is LivePartnerCadence) {
            source.update(spm: series[i], at: now);
          }
          e.addCadences(
            mine: 170,
            theirs: source.spmAt(elapsed: _secs(i.toDouble()), now: now),
            at: now,
          );
        }
        final s = e.state;
        e.dispose();
        return s;
      }

      final liveResult = runWith(LivePartnerCadence());
      final ghostResult = runWith(GhostCadenceTimeline(series));
      expect(liveResult, SyncState.resonant);
      expect(ghostResult, liveResult,
          reason: '시차 동행이 동시성의 열등한 대체재가 아니라는 D-001의 코드판');
    });
  });
}
