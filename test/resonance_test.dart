import 'dart:math' show Random;

import 'package:flutter_test/flutter_test.dart';
import 'package:goingon/services/demo_resonance.dart';
import 'package:goingon/services/resonance.dart';

/// 공명 이벤트 레이어 — 연속값(closeness)에서 **순간**을 뽑아내는 규칙.
///
/// 여기서 지켜야 하는 것은 "상태가 맞게 계산되는가"보다 **경계에서 튀지 않는가**
/// 다. 화면만 있을 땐 미세한 깜빡임이지만 소리·햅틱이 걸리면 진입음이 1초에
/// 열 번 울린다. 사람 손으로는 재현하기 어려운 종류의 실패라 여기서 잡는다.
void main() {
  final t0 = DateTime.utc(2026, 8, 16, 7);

  /// [seconds] 동안 [raw]를 [step] 간격으로 흘려 넣는다
  DateTime feed(
    ResonanceEngine e,
    DateTime from,
    double raw, {
    required double seconds,
    double step = 0.1,
  }) {
    var at = from;
    final until = from.add(_secs(seconds));
    while (at.isBefore(until)) {
      at = at.add(_secs(step));
      e.addSample(raw, at: at);
    }
    return at;
  }

  group('상태 판정 — 히스테리시스', () {
    test('올라갈 때는 진입 문턱을 넘어야 한다', () {
      const s = SyncStateMachine.resolve;
      expect(s(SyncState.drifting, 0.30), SyncState.drifting,
          reason: '문턱과 같으면 아직 아니다');
      expect(s(SyncState.drifting, 0.31), SyncState.approaching);
      expect(s(SyncState.approaching, 0.69), SyncState.approaching);
      expect(s(SyncState.approaching, 0.71), SyncState.aligned);
      expect(s(SyncState.aligned, 0.87), SyncState.aligned);
      expect(s(SyncState.aligned, 0.89), SyncState.resonant);
    });

    test('내려올 때는 이탈 문턱까지 버틴다', () {
      const s = SyncStateMachine.resolve;
      // 진입 문턱(0.88) 아래지만 이탈 문턱(0.80) 위 — 공명 유지
      expect(s(SyncState.resonant, 0.85), SyncState.resonant);
      expect(s(SyncState.resonant, 0.79), SyncState.aligned);
      expect(s(SyncState.aligned, 0.65), SyncState.aligned);
      expect(s(SyncState.aligned, 0.59), SyncState.approaching);
      expect(s(SyncState.approaching, 0.25), SyncState.approaching);
      expect(s(SyncState.approaching, 0.21), SyncState.drifting);
    });

    test('한 번에 여러 단계를 건너뛸 수 있다', () {
      // 신호등에서 멈췄다 다시 붙는 경우 — 중간 상태를 거치지 않는다
      expect(SyncStateMachine.resolve(SyncState.drifting, 0.95),
          SyncState.resonant);
      expect(SyncStateMachine.resolve(SyncState.resonant, 0.05),
          SyncState.drifting);
    });

    test('진입 문턱이 이탈 문턱보다 항상 높다', () {
      // 이게 뒤집히면 히스테리시스가 아니라 데드존이 되어 상태가 영영 안 바뀐다
      expect(ResonanceThresholds.resonantEnter,
          greaterThan(ResonanceThresholds.resonantExit));
      expect(ResonanceThresholds.alignedEnter,
          greaterThan(ResonanceThresholds.alignedExit));
      expect(ResonanceThresholds.approachingEnter,
          greaterThan(ResonanceThresholds.approachingExit));
    });
  });

  group('스무딩', () {
    test('시정수 한 번이면 계단 입력의 63%까지 간다', () async {
      final e = ResonanceEngine();
      e.addSample(0, at: t0);
      feed(e, t0, 1.0, seconds: 1.0, step: 0.01);
      // 1 - e^-1 = 0.632. 촘촘히 넣을수록 이 값에 수렴한다
      expect(e.smoothedCloseness, closeTo(0.632, 0.02));
      e.dispose();
    });

    test('배경에서 오래 멈췄다 돌아오면 현재 값으로 스냅된다', () async {
      // 그 사이의 값은 아무도 모른다. 옛 값을 붙들고 천천히 따라가면
      // 돌아온 뒤 수십 초 동안 화면이 거짓말을 한다
      final e = ResonanceEngine();
      e.addSample(0.1, at: t0);
      e.addSample(0.95, at: t0.add(const Duration(seconds: 35)));
      expect(e.smoothedCloseness, greaterThan(0.94));
      e.dispose();
    });

    test('시정수는 오디오와 공유하는 1초다', () {
      // 값이 갈라지면 소리와 화면이 서로 다른 속도로 붙었다 떨어진다
      expect(kSharedSmoothingTimeConstant, const Duration(seconds: 1));
    });
  });

  group('이벤트', () {
    test('공명에 들어가면 stateChanged와 resonanceEntered가 함께 난다', () async {
      final e = ResonanceEngine();
      final events = <ResonanceEvent>[];
      e.events.listen(events.add);

      e.addSample(0.05, at: t0);
      feed(e, t0, 0.95, seconds: 6);
      await pumpEventQueue();

      final entered = events.whereType<ResonanceEntered>();
      expect(entered, hasLength(1));
      expect(events.whereType<ResonanceStateChanged>().last.to,
          SyncState.resonant);
      expect(e.state, SyncState.resonant);
      e.dispose();
    });

    test('문턱 근처에서 흔들려도 상태는 한 번만 바뀐다', () async {
      // ── 히스테리시스 검증 ──
      // 0.95와 0.75를 0.5초마다 번갈아 넣으면, 스무딩된 값은 진입 문턱(0.88)을
      // 위아래로 몇 번이나 가로지른다. 문턱이 하나뿐이라면 그때마다 공명이
      // 켜졌다 꺼졌다 한다는 뜻
      final e = ResonanceEngine();
      final events = <ResonanceEvent>[];
      e.events.listen(events.add);

      var at = t0;
      e.addSample(0.95, at: at);
      at = feed(e, at, 0.95, seconds: 3); // 먼저 확실히 공명에 진입

      var crossings = 0;
      var above = e.smoothedCloseness > ResonanceThresholds.resonantEnter;
      final trace = <double>[];
      for (var i = 0; i < 20; i++) {
        at = feed(e, at, i.isEven ? 0.75 : 0.95, seconds: 0.5);
        trace.add(e.smoothedCloseness);
        final nowAbove =
            e.smoothedCloseness > ResonanceThresholds.resonantEnter;
        if (nowAbove != above) crossings++;
        above = nowAbove;
      }
      await pumpEventQueue();

      // 검증 로그 — 문턱 하나였다면 몇 번 튀었을지 눈으로 확인용
      printOnFailure('스무딩 값 궤적: '
          '${trace.map((v) => v.toStringAsFixed(3)).join(' ')}');
      expect(crossings, greaterThanOrEqualTo(2),
          reason: '문턱이 하나였다면 여기서 상태가 그만큼 튀었을 것');
      expect(events.whereType<ResonanceStateChanged>(), hasLength(1),
          reason: '히스테리시스가 있으면 진입 한 번뿐이어야 한다');
      expect(e.state, SyncState.resonant, reason: '이탈 문턱(0.80) 아래로는 안 내려갔다');
      e.dispose();
    });

    test('공명을 유지하면 10초·30초·60초에 알린다', () async {
      final e = ResonanceEngine();
      final held = <Duration>[];
      _only<ResonanceHeld>(e).listen((ev) => held.add(ev.held));

      e.addSample(0.95, at: t0);
      feed(e, t0, 0.95, seconds: 70, step: 0.5);
      await pumpEventQueue();

      expect(held, [
        const Duration(seconds: 10),
        const Duration(seconds: 30),
        const Duration(seconds: 60),
      ]);
      e.dispose();
    });

    test('공명이 끊기면 유지 시간이 처음부터 다시 센다', () async {
      final e = ResonanceEngine();
      final held = <Duration>[];
      _only<ResonanceHeld>(e).listen((ev) => held.add(ev.held));

      e.addSample(0.95, at: t0);
      var at = feed(e, t0, 0.95, seconds: 15, step: 0.5); // 10초 마일스톤 통과
      at = feed(e, at, 0.2, seconds: 5, step: 0.5); // 이탈
      feed(e, at, 0.95, seconds: 15, step: 0.5); // 재진입
      await pumpEventQueue();

      expect(held, [const Duration(seconds: 10), const Duration(seconds: 10)],
          reason: '두 번째 공명의 10초는 다시 울려야 한다');
      expect(e.resonanceHeldFor, lessThan(const Duration(seconds: 20)));
      e.dispose();
    });

    test('신호는 그대로 흘러나간다', () async {
      final e = ResonanceEngine();
      final events = <ResonanceEvent>[];
      e.events.listen(events.add);

      e.signalSent(SignalKind.slow, at: t0);
      e.signalReceived(SignalKind.cheer, at: t0.add(_secs(1)));
      await pumpEventQueue();

      expect(events, hasLength(2));
      expect((events[0] as SignalSent).kind, SignalKind.slow);
      expect((events[1] as SignalReceived).kind, SignalKind.cheer);
      e.dispose();
    });

    test('제스처 문자열 — 살아남은 뜻은 예전 값을 그대로 쓴다', () {
      // Firestore의 sessions/{id}.gesture.type에 실려 가는 값이라
      // 여기 이름을 바꿔도 문자열은 유지돼야 한다
      expect(SignalKind.fromGestureType('here'), SignalKind.here);
      expect(SignalKind.fromGestureType('enc'), SignalKind.cheer);
      expect(SignalKind.fromGestureType('dn'), SignalKind.slow);
      // 신호를 셋으로 줄이며 뺀 값들 — 구버전이 보내와도 터지지 않고
      // 가장 가까운 뜻(응원)으로 받는다
      expect(SignalKind.fromGestureType('up'), SignalKind.cheer);
      expect(SignalKind.fromGestureType('heart'), SignalKind.cheer);
      expect(SignalKind.fromGestureType('알 수 없는 값'), SignalKind.cheer,
          reason: '모르는 신호가 와도 터지지 않아야 한다');
    });

    test('마일스톤은 같은 지점을 두 번 내지 않는다', () async {
      final e = ResonanceEngine();
      final marks = <String>[];
      _only<MilestoneReached>(e)
          .listen((ev) => marks.add('${ev.kind.name}:${ev.value}'));

      for (var s = 1; s <= 20 * 60; s++) {
        e.updateProgress(
          km: s * 0.003, // 약 5'30"/km
          elapsed: Duration(seconds: s),
          at: t0.add(Duration(seconds: s)),
        );
      }
      await pumpEventQueue();

      expect(marks, [
        'distanceKm:1',
        'minutes:10',
        'distanceKm:2',
        'distanceKm:3',
        'minutes:20',
      ]);
      e.dispose();
    });

    test('구독자가 0명이어도 터지지 않는다', () async {
      // 이 레이어를 붙여도 아무도 듣지 않는 동안에는 앱 동작이 이전과 같아야 한다
      final e = ResonanceEngine();
      feed(e, t0, 0.95, seconds: 5);
      e.signalSent(SignalKind.cheer, at: t0);
      e.dispose();
      // dispose 이후에 늦게 도착하는 호출도 조용히 무시된다
      expect(() => e.signalSent(SignalKind.cheer, at: t0), returnsNormally);
    });
  });

  group('송신 쿨다운', () {
    test('같은 신호는 10초 안에 다시 못 보낸다', () {
      final c = SignalCooldown();
      expect(c.allow(SignalKind.here, t0), isTrue);
      expect(c.allow(SignalKind.here, t0.add(_secs(3))), isFalse);
      expect(c.allow(SignalKind.here, t0.add(_secs(9.9))), isFalse);
      expect(c.allow(SignalKind.here, t0.add(_secs(10))), isTrue);
    });

    test('다른 신호는 서로를 막지 않는다', () {
      // 탭 직후의 길게 누르기는 스팸이 아니라 말을 바꾼 것이다
      final c = SignalCooldown();
      expect(c.allow(SignalKind.here, t0), isTrue);
      expect(c.allow(SignalKind.cheer, t0), isTrue);
      expect(c.allow(SignalKind.slow, t0), isTrue);
      expect(c.allow(SignalKind.here, t0), isFalse);
    });

    test('막힌 시도는 쿨다운을 연장하지 않는다', () {
      // 연타로 막히는 동안 계속 밀리면 영영 못 보내게 된다
      final c = SignalCooldown();
      c.allow(SignalKind.cheer, t0);
      for (var i = 1; i < 10; i++) {
        c.allow(SignalKind.cheer, t0.add(_secs(i.toDouble())));
      }
      expect(c.allow(SignalKind.cheer, t0.add(_secs(10))), isTrue);
    });
  });

  group('데모 시나리오', () {
    test('세션당 공명이 최소 2번, 그것도 첫 90초 안에 온다', () async {
      // 심사관이 1분 만에 나가도 이 앱의 핵심 순간은 봐야 한다
      final e = ResonanceEngine();
      final entered = <Duration>[];
      _only<ResonanceEntered>(e)
          .listen((ev) => entered.add(ev.at.difference(t0)));

      final driver = DemoResonanceDriver(e, clock: _FakeClock(t0).now);
      driver.start();
      for (var i = 0; i < 900; i++) {
        driver.pump(); // 0.1초씩 90초
      }
      await pumpEventQueue();

      printOnFailure('공명 진입 시각: ${entered.map((d) => d.inSeconds).toList()}');
      expect(entered.length, greaterThanOrEqualTo(2));
      expect(entered.first, lessThan(const Duration(seconds: 30)));
      driver.stop();
      e.dispose();
    });

    test('긴 데모에서는 유지 마일스톤 60초까지 간다', () async {
      final e = ResonanceEngine();
      final held = <int>[];
      _only<ResonanceHeld>(e).listen((ev) => held.add(ev.held.inSeconds));

      final driver = DemoResonanceDriver(e, clock: _FakeClock(t0).now);
      driver.start();
      for (var i = 0; i < 2100; i++) {
        driver.pump(); // 210초 = 한 바퀴
      }
      await pumpEventQueue();

      expect(held, contains(60));
      driver.stop();
      e.dispose();
    });

    test('지수가 보내는 신호는 한 번씩만 도착한다', () async {
      final e = ResonanceEngine();
      final signals = <SignalKind>[];
      _only<SignalReceived>(e).listen((ev) => signals.add(ev.kind));

      final driver = DemoResonanceDriver(e, clock: _FakeClock(t0).now);
      driver.start();
      for (var i = 0; i < 1300; i++) {
        driver.pump(); // 130초
      }
      await pumpEventQueue();

      expect(signals, [
        SignalKind.here,
        SignalKind.cheer,
        SignalKind.slow,
      ], reason: '한 바퀴 안에 세 종류가 모두 한 번씩은 와야 한다');
      driver.stop();
      e.dispose();
    });

    test('내가 신호를 보내면 5~15초 안에 지수가 답한다', () async {
      // 신호를 보냈는데 아무 일도 없으면 다시는 안 보낸다 — 데모에서
      // 송신→응답 루프가 실제로 닫히는지가 이 테스트의 전부다
      final e = ResonanceEngine();
      final replies = <Duration>[];
      _only<SignalReceived>(e)
          .listen((ev) => replies.add(ev.at.difference(t0)));

      final driver = DemoResonanceDriver(e,
          clock: _FakeClock(t0).now, random: Random(7));
      driver.start();
      for (var i = 0; i < 20; i++) {
        driver.pump(); // 2초까지 진행 (지수가 먼저 보내는 신호는 24초부터)
      }
      e.signalSent(SignalKind.here, at: t0.add(_secs(2)));
      await pumpEventQueue();
      for (var i = 0; i < 180; i++) {
        driver.pump(); // 20초까지
      }
      await pumpEventQueue();

      expect(replies, hasLength(1), reason: '스크립트 신호가 오기 전 구간이다');
      final gap = replies.single - const Duration(seconds: 2);
      expect(gap, greaterThanOrEqualTo(DemoResonanceDriver.replyDelayMin));
      expect(gap, lessThanOrEqualTo(DemoResonanceDriver.replyDelayMax));
      driver.stop();
      e.dispose();
    });

    test('답이 늘 오지는 않는다', () async {
      // 매번 답하면 사람이 아니라 자동응답기다
      var replied = 0;
      for (var seed = 0; seed < 40; seed++) {
        final e = ResonanceEngine();
        var got = false;
        _only<SignalReceived>(e).listen((_) => got = true);
        final driver = DemoResonanceDriver(e,
            clock: _FakeClock(t0).now, random: Random(seed));
        driver.start();
        e.signalSent(SignalKind.cheer, at: t0);
        await pumpEventQueue();
        for (var i = 0; i < 200; i++) {
          driver.pump(); // 20초 — 답이 올 수 있는 구간을 다 지난다
        }
        await pumpEventQueue();
        if (got) replied++;
        driver.stop();
        e.dispose();
      }
      expect(replied, greaterThan(20), reason: '대체로는 답이 와야 한다');
      expect(replied, lessThan(40), reason: '늘 오면 기계다');
    });

    test('한 바퀴를 넘겨도 이어붙는 자리에서 값이 튀지 않는다', () {
      final before = DemoResonanceScript.closenessAt(
          DemoResonanceScript.period - _secs(0.1));
      final after = DemoResonanceScript.closenessAt(
          DemoResonanceScript.period + _secs(0.1));
      expect((after - before).abs(), lessThan(0.1));
    });
  });
}

Duration _secs(double s) =>
    Duration(microseconds: (s * Duration.microsecondsPerSecond).round());

/// 부를 때마다 [DemoResonanceDriver.tick]만큼 흐르는 가짜 시계 —
/// 실제 시간을 기다리지 않고 210초짜리 시나리오를 통과시키기 위한 것
class _FakeClock {
  _FakeClock(this._now);
  DateTime _now;
  var _first = true;

  DateTime now() {
    if (_first) {
      _first = false;
      return _now;
    }
    _now = _now.add(DemoResonanceDriver.tick);
    return _now;
  }
}

/// 관심 있는 종류의 이벤트만 골라 듣는다
Stream<T> _only<T extends ResonanceEvent>(ResonanceEngine e) =>
    e.events.where((ev) => ev is T).cast<T>();
