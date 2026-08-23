// 세션 상태 머신 — 8분 에피소드의 국면을 굴리는 곳.
//
// **입력이 셋뿐인 것이 이 파일의 전부다**(§0 원칙 1: 러닝 중 화면 조작 제로):
//   · 발  — CadenceEngine의 GaitState. 잔향에서 다음 행선지를 결정한다
//   · 꼭지 — 이어폰 1회 누름. 문맥에 따라 '이어가기' 또는 '재개'
//   · 전화 — 시스템 인터럽션. 자동 일시정지, 통화가 끝나면 꼭지로 재개
// 화면은 입력 목록에 없다. 여기에 `onButtonPressed`가 생기면 설계가 틀린 것이다.
//
// 시간은 전부 타임스탬프 차이로 잰다(CLAUDE.md 기술 원칙). 틱 누적은 iOS가
// 백그라운드에서 타이머를 멈추는 순간 반드시 틀린다. 일시정지 구간은 경과에서
// 빠지므로 "8분"이 통화 시간을 포함하지 않는다.
import 'dart:async';

import '../cadence/cadence_engine.dart' show GaitState;
import 'chart.dart';

/// 세션이 남기는 순간들. UI·소리·화자가 **함께 구독하는 단일 스트림**이다 —
/// 판정을 세 곳에서 따로 하면 화면과 소리가 어긋난다(resonance.dart와 같은 이유).
sealed class SessionEvent {
  const SessionEvent(this.at, this.elapsed);
  final DateTime at;
  final Duration elapsed;
  String describe();
}

class PhaseChanged extends SessionEvent {
  const PhaseChanged({
    required this.from,
    required this.to,
    required DateTime at,
    required Duration elapsed,
  }) : super(at, elapsed);

  final SessionPhase from;
  final SessionPhase to;

  @override
  String describe() => 'phase ${from.name} → ${to.name}';
}

/// 채보의 구간에 들어섰다 — 화자 한 줄·효과·동사가 여기 실려 온다
class SectionEntered extends SessionEvent {
  const SectionEntered({
    required this.section,
    required DateTime at,
    required Duration elapsed,
  }) : super(at, elapsed);

  final ChartSection section;

  @override
  String describe() =>
      'section ${section.phase.name}'
      '${section.verb == null ? '' : ' verb=${section.verb!.name}'}'
      '${section.narration == null ? '' : ' 화자="${section.narration}"'}';
}

/// 다음 화로 이어달라는 요청(꼭지 1회). 이 세션은 완주로 끝나고
/// 다음 에피소드가 새 세션의 intro로 시작한다 — chain은 상태가 아니라 사건이다
class ChainRequested extends SessionEvent {
  const ChainRequested({required DateTime at, required Duration elapsed})
      : super(at, elapsed);

  @override
  String describe() => 'chain 요청 ▶';
}

/// 세션이 끝났다
class SessionEnded extends SessionEvent {
  const SessionEnded({
    required this.completed,
    required this.partial,
    required DateTime at,
    required Duration elapsed,
  }) : super(at, elapsed);

  /// 8분을 채웠는가
  final bool completed;

  /// 부분 완주(4분 이상)인가 — 여정 거리는 인정, 스트릭은 미인정(§2-1)
  final bool partial;

  @override
  String describe() =>
      'ended completed=$completed partial=$partial ${elapsed.inSeconds}s';
}

/// 8분 에피소드의 국면 전이를 굴린다.
///
/// 이 클래스는 **타이머를 갖지 않는다.** 호출부가 1초 틱에서 [update]를 부르고,
/// 사건(꼭지·전화)은 별도 메서드로 들어온다. 그래야 8분짜리 시나리오를 밀리초
/// 단위로 시험할 수 있고, 백그라운드에서 틱이 밀려도 결과가 같다.
class SessionController {
  SessionController({
    required this.chart,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Chart chart;
  final DateTime Function() _clock;

  // ── 판정 상수 (§2-2) ────────────────────────────────────────────
  /// 잔향 — 발이 결정하는 30초. 음악은 낮게 유지되고 완전히 멈추지 않는다
  static const kReverb = Duration(seconds: 30);

  /// 잔향에서 걷기가 이만큼 지속되면 종료 시퀀스로
  static const kWalkToCooldown = Duration(seconds: 10);

  /// 이보다 짧은 정지는 일시정지가 아니다 — 신호등에서 세션이 끊기면 안 된다.
  /// 레이어만 얇아지는 것은 사운드 쪽 몫이고, 여기서는 아무 일도 하지 않는다
  static const kIgnoreStopUnder = Duration(seconds: 30);

  /// 4분 이상이면 부분 완주 — 여정 거리 인정, 스트릭 미인정(§2-1)
  static const kPartialAfter = Duration(minutes: 4);

  final _events = StreamController<SessionEvent>.broadcast();
  Stream<SessionEvent> get events => _events.stream;

  SessionPhase _phase = SessionPhase.idle;
  SessionPhase get phase => _phase;

  DateTime? _startedAt;
  Duration _pausedTotal = Duration.zero;
  DateTime? _pausedSince;
  bool get isPaused => _pausedSince != null;

  ChartSection? _currentSection;

  DateTime? _reverbSince;
  DateTime? _walkingSince;
  GaitState _gait = GaitState.idle;

  /// 시작 시각과의 차이에서 일시정지 구간을 뺀 값. **틱 누적이 아니다**
  Duration get elapsed {
    final start = _startedAt;
    if (start == null) return Duration.zero;
    final paused = _pausedTotal +
        (_pausedSince == null ? Duration.zero : _clock().difference(_pausedSince!));
    return _clock().difference(start) - paused;
  }

  /// 4분을 넘겼는가 — 중단해도 여정에 남는다
  bool get isPartialCompletion => elapsed >= kPartialAfter;

  void start() {
    if (_phase != SessionPhase.idle) return;
    _startedAt = _clock();
    _to(SessionPhase.intro);
    update();
  }

  /// 호출부의 1초 틱. 채보 구간과 잔향 판정을 여기서 굴린다
  void update() {
    if (_startedAt == null || isPaused) return;
    final now = _clock();
    final e = elapsed;

    if (_phase.isCharted) {
      final section = chart.sectionAt(e);
      if (section == null) {
        // 채보가 끝났다 → 잔향. 여기서 음악을 끄지 않는다(§2-2)
        _reverbSince = now;
        _walkingSince = null;
        _to(SessionPhase.reverb);
        return;
      }
      if (!identical(section, _currentSection)) {
        _currentSection = section;
        if (section.phase != _phase) _to(section.phase);
        _emit(SectionEntered(section: section, at: now, elapsed: e));
      }
      return;
    }

    if (_phase == SessionPhase.reverb) {
      _judgeReverb(now, e);
    }
  }

  /// 잔향 판정 — **발이 결정한다**(§2-2).
  ///
  /// 걷기가 10초 지속되면 즉시 종료 시퀀스로. 그렇지 않고 30초를 버티면
  /// 자유런으로 이음새 없이 넘어간다 — 멘트 없이. 여기서 "계속할까요?"를
  /// 물으면 러너스 하이가 그 질문에서 끊긴다.
  void _judgeReverb(DateTime now, Duration e) {
    if (_gait == GaitState.walking) {
      _walkingSince ??= now;
      if (now.difference(_walkingSince!) >= kWalkToCooldown) {
        _to(SessionPhase.cooldown);
        return;
      }
    } else {
      _walkingSince = null;
    }

    final since = _reverbSince;
    if (since != null && now.difference(since) >= kReverb) {
      // 30초를 달린 채로 통과 = 계속 달리겠다는 뜻. 묻지 않는다
      if (_gait == GaitState.running) {
        _to(SessionPhase.freeRun);
      } else {
        _to(SessionPhase.cooldown);
      }
    }
  }

  /// 발에서 오는 입력
  void onGait(GaitState gait) {
    _gait = gait;
    update();
  }

  /// 이어폰 꼭지 1회 누름. **문맥이 뜻을 정한다** — 러너는 뜻을 고르지 않는다.
  /// 일시정지 중이면 재개, 잔향이면 다음 화로 잇기, 그 외에는 아무 일도 없다.
  void onTip() {
    if (isPaused) {
      resume();
      return;
    }
    if (_phase == SessionPhase.reverb) {
      _emit(ChainRequested(at: _clock(), elapsed: elapsed));
      _end(completed: true);
    }
  }

  /// 전화 수신 등 시스템 인터럽션 시작 — 자동 일시정지
  void onInterruptionBegan() {
    if (_pausedSince != null || !_phase.isRunning) return;
    _pausedSince = _clock();
  }

  /// 인터럽션 종료. **자동으로 재개하지 않는다** — 통화가 끝났다고 바로
  /// 달리고 있다는 보장이 없다. 화자가 한 번 묻고 꼭지 1회로 재개한다(§0 원칙 1)
  void onInterruptionEnded() {}

  void resume() {
    final since = _pausedSince;
    if (since == null) return;
    _pausedTotal += _clock().difference(since);
    _pausedSince = null;
    update();
  }

  /// 러너가 멈춤 버튼을 길게 눌러 끝냈을 때
  void stop() => _end(completed: elapsed >= chart.duration);

  void _end({required bool completed}) {
    if (_phase == SessionPhase.result) return;
    final e = elapsed;
    _to(SessionPhase.result);
    _emit(SessionEnded(
      completed: completed,
      partial: !completed && e >= kPartialAfter,
      at: _clock(),
      elapsed: e,
    ));
  }

  void _to(SessionPhase next) {
    if (next == _phase) return;
    final from = _phase;
    _phase = next;
    _emit(PhaseChanged(from: from, to: next, at: _clock(), elapsed: elapsed));
  }

  void _emit(SessionEvent e) {
    if (!_events.isClosed) _events.add(e);
  }

  void dispose() => _events.close();
}
