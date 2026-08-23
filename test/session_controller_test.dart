// 세션 상태 머신 — 8분짜리 시나리오를 밀리초 단위로 굴린다.
//
// 여기서 지켜야 하는 것은 "전이가 맞는가"보다 **러너가 화면을 안 봐도 되는가**다.
// 잔향에서 아무것도 안 하면 발이 알아서 결정하고, 전화가 와도 기록이 안 망가지고,
// 중간에 그만둬도 4분을 넘겼으면 여정에 남는다. 이것들이 깨지면 §0 원칙 1이 깨진다.
import 'package:flutter_test/flutter_test.dart';
import 'package:goingon/services/cadence/cadence_engine.dart' show GaitState;
import 'package:goingon/services/session/chart.dart';
import 'package:goingon/services/session/session_controller.dart';

const _trainJson = '''
{
  "id": "ep_test", "title": "시험용", "durationSec": 480, "baseBPM": 165,
  "stems": { "drums": "audio/pad_resonance.wav" },
  "sections": [
    { "t": 0,   "phase": "intro",   "narration": "출발합니다." },
    { "t": 60,  "phase": "build",   "verb": "hold" },
    { "t": 240, "phase": "mission", "verb": "hold_low", "fx": "tunnel_filter" },
    { "t": 360, "phase": "climax",  "verb": "spurt", "durationSec": 30 },
    { "t": 450, "phase": "outro",   "fx": "arrival_bell" }
  ],
  "safety": { "maxSpurtSec": 30, "noStopCues": true }
}
''';

void main() {
  final chart = Chart.parse(_trainJson);

  /// 시계를 손으로 굴리는 장치. 1초씩 밀며 [update]를 부른다
  late DateTime now;
  late SessionController c;
  late List<SessionEvent> events;

  setUp(() {
    now = DateTime.utc(2026, 8, 23, 6);
    c = SessionController(chart: chart, clock: () => now);
    events = [];
    c.events.listen(events.add);
  });

  tearDown(() => c.dispose());

  /// [seconds]초를 1초 간격으로 흘린다
  void run(int seconds, {GaitState? gait}) {
    for (var i = 0; i < seconds; i++) {
      now = now.add(const Duration(seconds: 1));
      if (gait != null) {
        c.onGait(gait);
      } else {
        c.update();
      }
    }
  }

  group('채보 — 에피소드는 데이터다', () {
    test('구간이 시각 순서대로 열린다', () {
      c.start();
      expect(c.phase, SessionPhase.intro);
      run(70, gait: GaitState.running);
      expect(c.phase, SessionPhase.build);
      run(180, gait: GaitState.running);
      expect(c.phase, SessionPhase.mission);
      run(120, gait: GaitState.running);
      expect(c.phase, SessionPhase.climax);
      run(95, gait: GaitState.running);
      expect(c.phase, SessionPhase.outro);
    });

    test('화자 한 줄은 구간 진입에 한 번만 실려 온다', () async {
      c.start();
      run(120, gait: GaitState.running);
      await pumpEventQueue();
      final narrations = events
          .whereType<SectionEntered>()
          .where((e) => e.section.narration != null)
          .length;
      expect(narrations, 1, reason: '같은 구간에서 화자가 두 번 말하면 안 된다');
    });

    test('실을 수 없는 채보는 로딩에서 걸린다', () {
      // 화자 상한 초과 (§0 원칙 2)
      expect(
        () => Chart.parse('''
{ "id":"x","title":"x","durationSec":480,"baseBPM":165,"stems":{},
  "sections":[
    {"t":0,"phase":"intro","narration":"1"},{"t":10,"phase":"build","narration":"2"},
    {"t":20,"phase":"build","narration":"3"},{"t":30,"phase":"build","narration":"4"},
    {"t":40,"phase":"build","narration":"5"},{"t":50,"phase":"build","narration":"6"},
    {"t":60,"phase":"build","narration":"7"}]}'''),
        throwsFormatException,
      );
      // 스퍼트 상한 초과 (안전 규칙)
      expect(
        () => Chart.parse('''
{ "id":"x","title":"x","durationSec":480,"baseBPM":165,"stems":{},
  "sections":[{"t":0,"phase":"intro"},
    {"t":60,"phase":"climax","verb":"spurt","durationSec":90}],
  "safety":{"maxSpurtSec":30}}'''),
        throwsFormatException,
      );
    });
  });

  group('잔향 — 발이 결정한다 (§2-2)', () {
    /// 채보 끝까지 달려 잔향에 들어간다
    void toReverb() {
      c.start();
      run(481, gait: GaitState.running);
      expect(c.phase, SessionPhase.reverb, reason: '채보가 끝나면 잔향');
    }

    test('계속 달리면 멘트 없이 자유런으로', () async {
      toReverb();
      await pumpEventQueue();
      final before = events.length;
      run(31, gait: GaitState.running);
      await pumpEventQueue();
      expect(c.phase, SessionPhase.freeRun);
      // 전이 하나 말고는 아무 일도 없어야 한다 — 묻지 않는다
      final after = events.skip(before).toList();
      expect(after.whereType<PhaseChanged>(), hasLength(1));
      expect(after.length, 1, reason: '"계속할까요?"를 물으면 러너스 하이가 끊긴다');
    });

    test('걷기 10초면 종료 시퀀스로 — 30초를 기다리지 않는다', () {
      toReverb();
      run(11, gait: GaitState.walking);
      expect(c.phase, SessionPhase.cooldown);
    });

    test('걷다가 다시 달리면 10초 시계가 처음부터', () {
      toReverb();
      run(8, gait: GaitState.walking);
      expect(c.phase, SessionPhase.reverb, reason: '8초로는 아직 아니다');
      run(3, gait: GaitState.running); // 다시 달림 → 시계 초기화
      run(8, gait: GaitState.walking);
      expect(c.phase, SessionPhase.reverb, reason: '시계가 이어지면 여기서 종료됐을 것');
    });

    test('꼭지 1회는 다음 화로 잇기 — 완주로 끝난다', () async {
      toReverb();
      c.onTip();
      await pumpEventQueue();
      expect(events.whereType<ChainRequested>(), hasLength(1));
      final ended = events.whereType<SessionEnded>().single;
      expect(ended.completed, isTrue);
      expect(c.phase, SessionPhase.result);
    });

    test('잔향 30초를 서 있으면 종료 시퀀스로', () {
      toReverb();
      run(31, gait: GaitState.idle);
      expect(c.phase, SessionPhase.cooldown);
    });
  });

  group('전화 — 자동 일시정지, 꼭지로 재개 (§0 원칙 1)', () {
    test('통화 시간은 경과에서 빠진다', () {
      c.start();
      run(100, gait: GaitState.running);
      c.onInterruptionBegan();
      expect(c.isPaused, isTrue);

      now = now.add(const Duration(seconds: 200)); // 3분 20초 통화
      c.onInterruptionEnded();
      expect(c.isPaused, isTrue, reason: '통화가 끝났다고 달리고 있는 건 아니다');

      c.onTip(); // 꼭지 1회 = 재개
      expect(c.isPaused, isFalse);
      expect(c.elapsed.inSeconds, closeTo(100, 2),
          reason: '통화 200초가 8분에 포함되면 러닝이 아니라 통화를 잰 것이다');
    });

    test('일시정지 중에는 국면이 굴러가지 않는다', () {
      c.start();
      run(400, gait: GaitState.running);
      final phase = c.phase;
      c.onInterruptionBegan();
      now = now.add(const Duration(seconds: 300));
      c.update();
      expect(c.phase, phase, reason: '멈춰 있는 동안 채보가 지나가면 안 된다');
    });
  });

  group('부분 완주 (§2-1)', () {
    test('4분을 넘기면 여정에 남는다', () async {
      c.start();
      run(250, gait: GaitState.running);
      expect(c.isPartialCompletion, isTrue);
      c.stop();
      await pumpEventQueue();
      final ended = events.whereType<SessionEnded>().single;
      expect(ended.completed, isFalse);
      expect(ended.partial, isTrue, reason: '거리 인정 / 스트릭 미인정');
    });

    test('4분 미만은 기록만', () async {
      c.start();
      run(200, gait: GaitState.running);
      c.stop();
      await pumpEventQueue();
      final ended = events.whereType<SessionEnded>().single;
      expect(ended.partial, isFalse);
    });

    test('중단에 실패를 알리는 이벤트는 없다', () async {
      c.start();
      run(100, gait: GaitState.running);
      c.stop();
      await pumpEventQueue();
      // 종료는 SessionEnded 하나뿐 — 여기에 실패음이 붙을 자리를 만들지 않는다
      expect(events.whereType<SessionEnded>(), hasLength(1));
      expect(events.last, isA<SessionEnded>());
    });
  });

  group('화면 조작 제로', () {
    test('입력은 발·꼭지·전화 셋뿐이다', () {
      // 이 목록이 늘어나면 §0 원칙 1이 깨진 것이다. 늘릴 때는 설계를 먼저 고칠 것
      c.start();
      run(10, gait: GaitState.running); // 발
      c.onTip(); // 꼭지
      c.onInterruptionBegan(); // 전화
      c.onInterruptionEnded();
      c.onTip();
      expect(c.phase.isRunning, isTrue, reason: '세 입력만으로 러닝이 유지된다');
    });
  });
}
