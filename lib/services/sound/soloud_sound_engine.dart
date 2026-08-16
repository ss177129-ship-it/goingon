import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import 'sound_engine.dart';

/// flutter_soloud 구현. **바깥에서는 이 파일을 import하지 않는다** —
/// 호출부는 [SoundEngine]만 알아야 교체가 가능하다.
class SoLoudSoundEngine implements SoundEngine {
  final _sources = <SoundId, AudioSource>{};
  final _loops = <SoundId, SoundHandle>{};
  final _paused = <SoundId, bool>{};
  bool _ready = false;

  /// 시뮬레이터에서는 소리를 들을 수 없어, 엔진이 실제로 무엇을 했는지는
  /// 이 로그가 유일한 증거다. 상태가 **바뀔 때만** 찍는다 — 볼륨은 초당
  /// 20번 바뀌므로 매번 찍으면 로그가 소리를 덮는다
  void _log(String message) {
    if (kDebugMode) debugPrint('[sound] $message');
  }

  @override
  Future<void> loadAssets() async {
    try {
      await SoLoud.instance.init();
      for (final id in SoundId.values) {
        _sources[id] = await SoLoud.instance.loadAsset(id.asset);
      }
      _ready = true;
      _log('준비됨 — 음원 ${_sources.length}개');
    } catch (e, stack) {
      // 소리가 안 나는 것은 러닝을 막을 이유가 아니다. 조용히 무음으로 남고
      // 원인만 남긴다 — 실기기에서만 재현되는 종류의 실패가 많다
      _ready = false;
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      debugPrint('[sound] 초기화 실패: $e');
    }
  }

  @override
  Future<void> playOneShot(SoundId id, {double volume = 1}) async {
    final source = _sources[id];
    if (!_ready || source == null) return;
    try {
      SoLoud.instance.play(source, volume: volume.clamp(0.0, 1.0));
      _log('▶ ${id.name} vol=${volume.toStringAsFixed(2)}');
    } catch (e) {
      debugPrint('[sound] $id 재생 실패: $e');
    }
  }

  @override
  Future<void> setLoopVolume(SoundId id, double volume) async {
    final source = _sources[id];
    if (!_ready || source == null) return;
    final v = volume.clamp(0.0, 1.0);
    try {
      final handle = _loops[id];
      if (handle == null) {
        // 들리기 전에는 목소리를 만들지 않는다 — 30~60분짜리 러닝에서
        // 무음 루프를 계속 돌리는 것은 그냥 배터리다
        if (v <= _kSilence) return;
        _loops[id] = SoLoud.instance.play(source, volume: v, looping: true);
        _paused[id] = false;
        _log('↻ ${id.name} 시작 vol=${v.toStringAsFixed(2)}');
        return;
      }
      SoLoud.instance.setVolume(handle, v);
      // 완전히 조용해지면 재생을 멈추되 목소리는 남긴다(다시 켤 때
      // 루프 위상이 이어져야 페이드인이 자연스럽다)
      final pause = v <= _kSilence;
      if (_paused[id] != pause) {
        _paused[id] = pause;
        SoLoud.instance.setPause(handle, pause);
        _log('↻ ${id.name} ${pause ? '멈춤' : '재개'}');
      }
    } catch (e) {
      debugPrint('[sound] $id 볼륨 조절 실패: $e');
    }
  }

  @override
  Future<void> dispose() async {
    if (!_ready) return;
    _ready = false;
    _loops.clear();
    _paused.clear();
    try {
      for (final source in _sources.values) {
        await SoLoud.instance.disposeSource(source);
      }
      SoLoud.instance.deinit();
    } catch (e) {
      debugPrint('[sound] 정리 실패: $e');
    }
    _sources.clear();
  }
}

/// 이 아래는 들리지 않는다고 본다. 0과 정확히 비교하면 부동소수점
/// 찌꺼기(1e-17) 때문에 경계에서 재생/정지가 번갈아 일어난다
const _kSilence = 0.001;
