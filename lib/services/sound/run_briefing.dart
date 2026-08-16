import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../resonance.dart';
import 'audio_session_controller.dart';
import 'briefing_script.dart';

/// 1km마다 한 문장. 설계서 §3.
///
/// 이 기능이 조심해야 하는 것은 "말이 나오는가"가 아니라 **말이 다른 것을
/// 망가뜨리지 않는가**다:
/// - 유저 음악은 멈추지 않고 잠깐 낮아졌다 돌아온다(duck)
/// - 말하는 동안 도착한 이벤트 사운드는 큐에 쌓지 않고 버린다
/// - 말이 끝난 뒤 오디오 세션이 살아 있어야 패드가 이어진다
class RunBriefing {
  RunBriefing({
    required ResonanceEngine engine,
    required this.partnerName,
    required AudioSessionController session,
    required this.onSpeaking,
    FlutterTts? tts,
    DateTime Function()? clock,
    this.partnerKm,
  })  : _engine = engine,
        _session = session,
        _tts = tts ?? FlutterTts(),
        _clock = clock ?? DateTime.now;

  /// 발화가 끝나고 음악이 돌아오기까지. 곧바로 풀면 음악이 튀어 올라온다
  static const duckRelease = Duration(seconds: 1);

  /// 이보다 오래된 신호는 "방금"이 아니다. 1km를 뛰는 5~6분 내내 같은
  /// 신호를 우려먹으면 거짓말처럼 들린다
  static const recentSignalWindow = Duration(seconds: 60);

  /// 설계서가 정한 상한. 넘으면 요소를 줄여야 한다
  static const maxUtterance = Duration(seconds: 4);

  final String partnerName;
  final ResonanceEngine _engine;
  final AudioSessionController _session;
  final FlutterTts _tts;
  final DateTime Function() _clock;

  /// 상대의 누적 거리를 알 수 있게 되면(라이브 동기화, v1.1) 여기에 꽂는다.
  /// 지금은 항상 null이고 문장은 마지막 갈래로 떨어진다
  final double? Function()? partnerKm;

  final void Function(bool speaking) onSpeaking;

  StreamSubscription<ResonanceEvent>? _events;
  DateTime? _lastMilestoneAt;
  SignalKind? _lastSignal;
  DateTime? _lastSignalAt;
  bool _speaking = false;
  Timer? _duckRelease;

  Future<void> start() async {
    _lastMilestoneAt = _clock();
    try {
      await _tts.setLanguage('ko-KR');
      // 기본 속도로는 3요소 문장이 4초를 넘긴다(실측: "1킬로미터. 6초.
      // 지금 나란히예요."가 4.2초). 달리면서 듣는 안내라 조금 빠른 편이
      // 낫고, 요소를 줄이기 전에 여기부터 손본다
      await _tts.setSpeechRate(0.55);
      // 발화가 끝나는 시점을 알아야 덕킹을 풀 수 있다
      await _tts.awaitSpeakCompletion(true);
      // **함정**: 이걸 끄지 않으면 flutter_tts가 발화 종료 시 duckOthers가
      // 켜진 세션을 통째로 setActive(false) 한다. 그러면 우리 패드도 같이
      // 죽는다 (flutter_tts 4.2.5 SwiftFlutterTtsPlugin.swift 참조)
      await _tts.autoStopSharedSession(false);
    } catch (e) {
      debugPrint('[briefing] TTS 설정 실패: $e');
    }
    _events = _engine.events.listen(_onEvent);
  }

  Future<void> stop() async {
    await _events?.cancel();
    _events = null;
    _duckRelease?.cancel();
    _duckRelease = null;
    try {
      await _tts.stop();
    } catch (_) {}
    if (_speaking) {
      _speaking = false;
      onSpeaking(false);
    }
    await _session.setDucking(false);
  }

  void _onEvent(ResonanceEvent e) {
    switch (e) {
      case SignalReceived(:final kind, :final at):
        _lastSignal = kind;
        _lastSignalAt = at;
      case MilestoneReached(kind: MilestoneKind.distanceKm, :final value):
        _brief(value);
      default:
        break;
    }
  }

  Future<void> _brief(int km) async {
    // 이미 말하는 중이면 **버린다**. 큐에 넣으면 2km 안내가 3km 지점에서
    // 나오는 일이 생긴다
    if (_speaking) return;
    final now = _clock();
    final split = now.difference(_lastMilestoneAt ?? now);
    _lastMilestoneAt = now;

    final text = BriefingScript.sentence(
      km: km,
      split: split,
      partnerNote: BriefingScript.partnerNote(
        name: partnerName,
        recentSignal: _recentSignal(now),
        resonating: _engine.hasCloseness && _engine.state == SyncState.resonant,
        partnerKm: partnerKm?.call(),
      ),
    );

    _speaking = true;
    onSpeaking(true);
    _duckRelease?.cancel();
    await _session.setDucking(true);
    final startedAt = _clock();
    try {
      await _tts.speak(text);
    } catch (e) {
      debugPrint('[briefing] 발화 실패: $e');
    }
    final spoken = _clock().difference(startedAt);
    _speaking = false;
    onSpeaking(false);
    // 발화 길이는 귀 없이 확인할 수 있는 유일한 숫자다. 4초를 넘으면
    // 문장에서 요소를 덜어내야 한다는 뜻
    debugPrint('[briefing] "$text" — ${(spoken.inMilliseconds / 1000)
        .toStringAsFixed(1)}초${spoken > maxUtterance ? ' ⚠ 4초 초과' : ''}');

    _duckRelease = Timer(duckRelease, () => _session.setDucking(false));
  }

  SignalKind? _recentSignal(DateTime now) {
    final at = _lastSignalAt;
    if (at == null) return null;
    return now.difference(at) <= recentSignalWindow ? _lastSignal : null;
  }
}
