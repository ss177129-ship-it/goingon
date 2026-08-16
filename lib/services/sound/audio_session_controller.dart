import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

/// 오디오 세션 — 우리가 소리를 낼 수 있는지, 지금 내도 되는지를 관리한다.
///
/// 원칙(`docs/sound_ux_v1.md` §1-3): **유저의 음악이 왕이다.** 우리는 그 위에
/// 얹는 손님이라 `mixWithOthers`로 붙고, 남의 재생을 멈추게 하지 않는다.
///
/// 세션은 **러닝 시작 시에만** 잡는다. 앱을 켜자마자 잡으면 러닝을 안 하는
/// 동안에도 오디오 세션을 붙들고 있게 된다.
class AudioSessionController {
  AudioSessionController({required this.onAudibleChanged});

  /// 지금 소리를 내도 되는지가 바뀌었을 때 불린다.
  /// false가 오면 **소리만** 멈춘다 — 러닝 기록은 계속된다
  final void Function(bool audible) onAudibleChanged;

  AudioSession? _session;
  final _subs = <StreamSubscription<dynamic>>[];
  bool _interrupted = false;

  /// 이어폰이 **빠져서** 소리를 접은 상태.
  ///
  /// "지금 스피커로 나가는가"가 아니라 "이어폰이 도중에 사라졌는가"다.
  /// 처음부터 스피커로 듣기로 한 사람까지 막으면 그냥 소리가 안 나는 앱이
  /// 된다(시뮬레이터에서 이 실수로 아무 소리도 안 났다 — 2026-08-16)
  bool _lostHeadphones = false;
  bool _hasExternalOutput = false;

  bool get isAudible => !_interrupted && !_lostHeadphones;

  /// 평상시 구성 — 유저 음악과 그냥 공존한다
  static const _mixing = AudioSessionConfiguration(
    avAudioSessionCategory: AVAudioSessionCategory.playback,
    // 이것 하나가 "손님" 규칙의 전부다. 빼면 유저 음악이 멈춘다
    avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.mixWithOthers,
    avAudioSessionMode: AVAudioSessionMode.defaultMode,
  );

  /// 브리핑 중 구성 — 음악을 멈추지 않고 낮추기만 한다.
  /// `|`가 상수식이 아니라 final로 둔다
  static final _ducking = AudioSessionConfiguration(
    avAudioSessionCategory: AVAudioSessionCategory.playback,
    avAudioSessionCategoryOptions:
        AVAudioSessionCategoryOptions.mixWithOthers |
            AVAudioSessionCategoryOptions.duckOthers,
    // 안내 음성이라고 알려주면 iOS가 알아서 적절히 눌러준다
    avAudioSessionMode: AVAudioSessionMode.voicePrompt,
  );

  Future<void> activate() async {
    final session = await AudioSession.instance;
    _session = session;
    await session.configure(_mixing);
    await session.setActive(true);

    // 전화가 오면 우리 소리는 죽어도 된다. 다만 통화가 끝나면 **알아서
    // 돌아와야** 한다 — 러너가 폰을 꺼내 다시 켜게 만들면 안 된다
    _subs.add(session.interruptionEventStream.listen((event) {
      _interrupted = event.begin;
      onAudibleChanged(isAudible);
    }));

    // 이어폰이 빠졌는데 스피커로 이어가면 주머니 속에서 소리가 새어나온다.
    // 그건 사고다 — 출력이 내장 스피커뿐이 되면 사운드만 접는다
    _subs.add(session.devicesChangedEventStream.listen((_) => _refreshRoute()));
    // 시작 시점의 경로는 '기준'일 뿐 판정 대상이 아니다
    await _refreshRoute(initial: true);
  }

  /// 출력 경로가 바뀔 때마다 "이어폰이 사라졌는가"만 판정한다.
  ///
  /// 처음부터 스피커면 그건 사용자의 선택이라 그대로 낸다. 듣고 있던
  /// 이어폰이 빠진 순간에만 접고, 다시 꽂으면 되돌린다
  Future<void> _refreshRoute({bool initial = false}) async {
    try {
      final devices = await _session?.getDevices(includeInputs: false);
      if (devices == null) return;
      // 이 판정을 대신할 안정 API가 audio_session에 아직 없다. 시그니처가
      // 바뀌면 컴파일이 깨지므로 조용히 틀리지는 않는다
      final hasExternal = devices.any((d) =>
          d.isOutput &&
          // ignore: experimental_member_use
          d.type != AudioDeviceType.builtInSpeaker &&
          // ignore: experimental_member_use
          d.type != AudioDeviceType.builtInEarpiece);
      final was = _hasExternalOutput;
      _hasExternalOutput = hasExternal;
      if (initial) return;

      final wasAudible = isAudible;
      if (was && !hasExternal) {
        // 주머니 속 스피커로 새어나가는 것은 사고다
        _lostHeadphones = true;
        debugPrint('[sound] 이어폰이 빠져 사운드를 접습니다 (기록은 계속)');
      } else if (hasExternal) {
        _lostHeadphones = false;
      }
      if (isAudible != wasAudible) onAudibleChanged(isAudible);
    } catch (e) {
      debugPrint('[sound] 출력 장치 확인 실패: $e');
    }
  }

  /// 브리핑이 말하는 **그 순간에만** 유저 음악을 낮춘다.
  ///
  /// 상시로 걸어두지 않는 이유: duckOthers가 켜져 있는 동안 유저의 음악은
  /// 계속 눌려 있다. 우리는 30분 내내 음악을 눌러놓을 자격이 없다
  Future<void> setDucking(bool ducking) async {
    final session = _session;
    if (session == null) return;
    try {
      await session.configure(ducking ? _ducking : _mixing);
    } catch (e) {
      debugPrint('[sound] 덕킹 전환 실패: $e');
    }
  }

  Future<void> deactivate() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    try {
      await _session?.setActive(false);
    } catch (e) {
      debugPrint('[sound] 세션 해제 실패: $e');
    }
    _session = null;
  }
}
