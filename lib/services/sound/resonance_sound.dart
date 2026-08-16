import 'dart:async';
import 'dart:math' as math;

import '../resonance.dart';
import 'audio_session_controller.dart';
import 'sound_engine.dart';

/// 공명을 소리로 옮기는 곳.
///
/// 설계 원칙(`docs/sound_ux_v1.md` §1) 중 이 파일이 지키는 것:
/// - **소리는 상태 언어의 번역이다.** 새 트리거를 만들지 않고 이벤트 레이어가
///   이미 판정한 것만 소비한다. 여기서 closeness를 다시 판정하지 않는다
/// - **실패음은 없다.** 멀어질 때 나는 소리는 하나도 없고, 패드가 잦아드는
///   것이 전부다
/// - **화면과 같은 시정수.** 아래 [_padVolume] 주석 참조
class ResonanceSound {
  ResonanceSound({
    required ResonanceEngine engine,
    required SoundEngine sound,
    AudioSessionController? session,
  })  : _engine = engine,
        _sound = sound {
    _session = session ??
        AudioSessionController(onAudibleChanged: setAudible);
  }

  /// 패드가 들리기 시작하는 지점. 설계서가 정한 값이고, 이벤트 레이어의
  /// `aligned` 진입 문턱과 같은 숫자다 — "나란히가 화면에 보이면 귀에도
  /// 들린다"가 되려면 두 값이 같아야 한다
  static const padFloor = ResonanceThresholds.alignedEnter;

  /// 패드 볼륨을 다시 계산하는 주기. 값 자체가 1초 시정수로 움직이므로
  /// 이보다 촘촘할 이유가 없다
  static const tick = Duration(milliseconds: 50);

  /// 패드 최대 볼륨. 유저 음악 위에 얹히는 손님이라 꽉 채우지 않는다
  static const padCeiling = 0.55;
  static const overtoneCeiling = 0.35;
  static const chimeVolume = 0.9;

  /// 송신 확인음은 작게, 수신음은 크게.
  /// **내 확인음이 상대의 존재보다 크면 안 된다**(설계서 §2)
  static const sentVolume = 0.4;
  static const receivedVolume = 0.8;

  final ResonanceEngine _engine;
  final SoundEngine _sound;
  late final AudioSessionController _session;

  StreamSubscription<ResonanceEvent>? _events;
  Timer? _timer;
  bool _audible = true;

  /// 브리핑이 말하는 중. 이때 도착한 이벤트 사운드는 **버린다** —
  /// 큐에 넣었다가 뒤늦게 울리는 chime은 무엇에 대한 소리인지 알 수 없다
  bool _speaking = false;
  bool _overtone = false;
  double _overtoneLevel = 0;
  bool _started = false;

  /// 러닝 시작 시 호출. 오디오 세션을 잡고 음원을 올린다.
  ///
  /// **사운드가 꺼져 있으면 이 함수 자체가 불리지 않는다** — 세션도 안 잡고
  /// 엔진도 안 만든다(호출부 참조)
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _session.activate();
    await _sound.loadAssets();
    _events = _engine.events.listen(_onEvent);
    _timer = Timer.periodic(tick, (_) => _applyPadVolume());
  }

  /// 러닝 종료 시. 세션을 놓지 않으면 러닝이 끝난 뒤에도 오디오 세션을
  /// 붙들고 있게 된다
  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    _timer?.cancel();
    _timer = null;
    await _events?.cancel();
    _events = null;
    await _sound.dispose();
    await _session.deactivate();
  }

  void _onEvent(ResonanceEvent e) {
    switch (e) {
      case ResonanceEntered():
        // 햅틱·골드 링과 같은 이벤트를 같은 순간에 받는다. 여기서 다시
        // 조건을 따지면 셋의 타이밍이 갈라진다
        _playEvent(SoundId.chimeMatch, chimeVolume);
      case ResonanceHeld(:final held):
        // 소리를 하나 더 얹는 게 아니라 같은 소리가 두꺼워지는 것
        if (held >= const Duration(seconds: 30)) _overtone = true;
      case ResonanceStateChanged(:final to):
        // 멀어질 때 나는 소리는 없다. 패드가 잦아드는 것이 전부다
        if (to != SyncState.resonant) _overtone = false;
      case SignalSent():
        _playEvent(SoundId.sigSend, sentVolume);
      case SignalReceived(:final kind):
        _playEvent(_receivedSound(kind), receivedVolume);
      default:
        break;
    }
  }

  static SoundId _receivedSound(SignalKind kind) => switch (kind) {
        SignalKind.here => SoundId.sigHere,
        SignalKind.cheer => SoundId.sigCheer,
        SignalKind.slow => SoundId.sigSlow,
      };

  /// 이벤트 사운드 한 발. 들리지 않는 상황이거나 브리핑 중이면 **버린다**
  void _playEvent(SoundId id, double volume) {
    if (!_audible || _speaking) return;
    _sound.playOneShot(id, volume: volume);
  }

  /// 브리핑이 시작/종료될 때 호출. 패드는 그대로 둔다 — 말 밑에 깔린 드론은
  /// 방해가 아니라 배경이고, 여기서 끊으면 브리핑마다 소리가 뚝 끊긴다
  void setSpeaking(bool speaking) => _speaking = speaking;

  /// 패드 볼륨 = closeness를 [padFloor]~1.0 구간에서 0~1로 편 값.
  ///
  /// **여기서 다시 스무딩하지 않는다.** [ResonanceEngine.smoothedCloseness]가
  /// 이미 [kSharedSmoothingTimeConstant](1초)로 스무딩된 값이라, 그대로 쓰면
  /// 소리가 화면의 원과 **같은 속도로** 붙었다 떨어진다. 여기에 스무딩을 한 겹
  /// 더 얹으면 소리만 뒤늦게 따라와 두 개의 다른 일처럼 느껴진다.
  double _padVolume() => _audible ? padVolumeFor(_engine.smoothedCloseness) : 0;

  /// closeness → 패드 볼륨. 문턱에서 **값이 0으로 이어지는 것**이 중요하다.
  /// 문턱에서 볼륨이 툭 튀면 경계에서 소리가 깜빡인다
  static double padVolumeFor(double closeness) {
    if (closeness <= padFloor) return 0;
    return ((closeness - padFloor) / (1 - padFloor)).clamp(0.0, 1.0);
  }

  void _applyPadVolume() {
    final v = _padVolume();
    _sound.setLoopVolume(SoundId.padResonance, v * padCeiling);
    _sound.setLoopVolume(SoundId.padOvertone, v * overtoneCeiling * _overtoneGain());
  }

  /// 배음 레이어가 들어오고 나가는 정도(0~1).
  ///
  /// 켜지는 순간 그냥 얹으면 없던 소리가 튀어나온 것처럼 들린다. 패드와 같은
  /// 시정수로 페이드해야 "같은 소리가 두꺼워졌다"로 읽힌다
  double _overtoneGain() {
    final target = _overtone ? 1.0 : 0.0;
    final dt = tick.inMicroseconds / Duration.microsecondsPerSecond;
    final tau = kSharedSmoothingTimeConstant.inMicroseconds /
        Duration.microsecondsPerSecond;
    _overtoneLevel += (target - _overtoneLevel) * (1 - math.exp(-dt / tau));
    return _overtoneLevel;
  }

  /// 전화가 왔거나 이어폰이 빠졌을 때. **소리만** 멈춘다 — 기록은 계속된다
  void setAudible(bool audible) {
    _audible = audible;
    _applyPadVolume();
  }
}
