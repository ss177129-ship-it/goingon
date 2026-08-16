import 'package:flutter_test/flutter_test.dart';
import 'package:goingon/services/resonance.dart';
import 'package:goingon/services/sound/audio_session_controller.dart';
import 'package:goingon/services/sound/resonance_sound.dart';
import 'package:goingon/services/sound/sound_engine.dart';

/// 공명 사운드 — 무엇이 언제 울리는가(`docs/sound_ux_v1.md` §2).
///
/// 소리는 귀로만 확인되는 것 같지만, 이 설계에서 틀릴 수 있는 것들은 대부분
/// 숫자다: 문턱에서 볼륨이 튀는가, 멀어질 때 소리를 내는가, chime이 두 번
/// 울리는가. 그건 여기서 잡는다.
void main() {
  final t0 = DateTime.utc(2026, 8, 16, 7);

  group('패드 볼륨 곡선', () {
    test('나란히(0.70) 미만은 무음', () {
      expect(ResonanceSound.padVolumeFor(0.0), 0);
      expect(ResonanceSound.padVolumeFor(0.5), 0);
      expect(ResonanceSound.padVolumeFor(0.70), 0);
    });

    test('0.70~1.00에서 0→1로 편다', () {
      expect(ResonanceSound.padVolumeFor(0.85), closeTo(0.5, 0.001));
      expect(ResonanceSound.padVolumeFor(1.0), 1.0);
    });

    test('문턱에서 값이 이어진다', () {
      // 여기서 툭 튀면 경계에 머무는 동안 소리가 깜빡인다.
      // 문턱 바로 위의 볼륨이 0에 붙어 있어야 한다
      expect(ResonanceSound.padVolumeFor(0.7001), lessThan(0.001));
    });

    test('패드가 열리는 지점이 화면의 "나란히"와 같은 숫자다', () {
      // 화면에 나란히가 뜨는데 소리는 안 나면 둘이 다른 말을 하는 것이다
      expect(ResonanceSound.padFloor, ResonanceThresholds.alignedEnter);
    });
  });

  group('무엇이 울리는가', () {
    late ResonanceEngine engine;
    late _FakeSoundEngine sound;
    late ResonanceSound resonanceSound;

    setUp(() async {
      engine = ResonanceEngine();
      sound = _FakeSoundEngine();
      resonanceSound = ResonanceSound(
        engine: engine,
        sound: sound,
        session: _NoAudioSession(),
      );
      await resonanceSound.start();
    });

    tearDown(() async {
      await resonanceSound.stop();
      engine.dispose();
    });

    /// [seconds] 동안 [raw]를 흘려 넣는다
    DateTime feed(DateTime from, double raw, {required double seconds}) {
      var at = from;
      final until = from.add(_secs(seconds));
      while (at.isBefore(until)) {
        at = at.add(_secs(0.1));
        engine.addSample(raw, at: at);
      }
      return at;
    }

    test('공명 진입에 chime이 한 번', () async {
      engine.addSample(0.05, at: t0);
      feed(t0, 0.95, seconds: 6);
      await pumpEventQueue();

      expect(sound.oneShots, [SoundId.chimeMatch]);
    });

    test('멀어질 때는 아무 소리도 내지 않는다', () async {
      // 실패음은 없다 — 패드가 잦아드는 것이 전부다
      engine.addSample(0.95, at: t0);
      final at = feed(t0, 0.95, seconds: 4);
      await pumpEventQueue(); // 진입 chime이 도착한 뒤에 지운다
      sound.oneShots.clear();
      feed(at, 0.05, seconds: 6);
      await pumpEventQueue();

      expect(sound.oneShots, isEmpty);
    });

    test('공명을 30초 이상 유지하면 배음이 얹힌다', () async {
      engine.addSample(0.95, at: t0);
      feed(t0, 0.95, seconds: 4);
      await pumpEventQueue();
      // 유지 30초 전에는 배음이 없다
      await _pumpTicks();
      expect(sound.loopVolumes[SoundId.padOvertone] ?? 0, 0);

      feed(t0.add(_secs(4)), 0.95, seconds: 32);
      await pumpEventQueue();
      await _pumpTicks(count: 40);
      expect(sound.loopVolumes[SoundId.padOvertone], greaterThan(0));
    });

    test('세션을 끝내면 엔진도 정리된다', () async {
      await resonanceSound.stop();
      expect(sound.disposed, isTrue);
      // tearDown의 두 번째 stop이 터지지 않아야 한다
    });
  });
}

/// 실제 타이머를 기다리지 않고 볼륨 적용 틱만 여러 번 굴린다
Future<void> _pumpTicks({int count = 5}) async {
  for (var i = 0; i < count; i++) {
    await Future<void>.delayed(ResonanceSound.tick);
  }
}

Duration _secs(double s) =>
    Duration(microseconds: (s * Duration.microsecondsPerSecond).round());

/// 소리를 내는 대신 무엇을 시켰는지만 적어둔다
class _FakeSoundEngine implements SoundEngine {
  final oneShots = <SoundId>[];
  final loopVolumes = <SoundId, double>{};
  bool loaded = false;
  bool disposed = false;

  @override
  Future<void> loadAssets() async => loaded = true;

  @override
  Future<void> playOneShot(SoundId id, {double volume = 1}) async =>
      oneShots.add(id);

  @override
  Future<void> setLoopVolume(SoundId id, double volume) async =>
      loopVolumes[id] = volume;

  @override
  Future<void> dispose() async => disposed = true;
}

/// 테스트에서는 진짜 오디오 세션을 잡지 않는다
class _NoAudioSession extends AudioSessionController {
  _NoAudioSession() : super(onAudibleChanged: _ignore);

  static void _ignore(bool _) {}

  @override
  Future<void> activate() async {}

  @override
  Future<void> deactivate() async {}
}
