import 'dart:async';
import 'dart:math' as math;
import 'dart:math' show Random;

import 'resonance.dart';

/// 데모 모드('혼자 미리 체험하기')의 가상 파트너 지수가 만들어내는 발맞춤.
///
/// 왜 스크립트인가: 데모는 심사관과 처음 온 사람이 이 앱을 이해하는 **유일한**
/// 통로다. 난수로 흔들면 어떤 실행에서는 공명이 한 번도 안 오고, 그러면
/// "함께 달린다"는 이 앱의 주장이 전달되지 않는다. 그래서 언제 무슨 일이
/// 일어날지 여기 못 박아 둔다.
///
/// 앞으로 붙을 사운드 테스트도 이 데모로 한다 — 아래 시나리오가
/// 공명 진입·유지·이탈·신호 수신을 모두 한 번씩은 지나가도록 짜여 있다.
class DemoResonanceScript {
  const DemoResonanceScript._();

  /// 한 바퀴 길이. 데모 러닝이 이보다 길어지면 처음부터 다시 돈다
  static const period = Duration(seconds: 210);

  /// (경과 초, 발맞춤) 꼭짓점. 사이는 선형 보간.
  ///
  /// 설계 의도:
  /// - **~19초에 첫 공명.** 심사관이 30초 만에 나가도 이 앱의 핵심 순간은 봤다
  /// - **~62초에 두 번째 공명.** 우연이 아니라 반복되는 것임을 보여준다
  /// - **~137초부터 60초 넘게 유지** — 10·30·60초 유지 마일스톤이 모두 울린다
  /// - 공명 사이에는 반드시 이탈 문턱(0.80) 아래로 충분히 내려간다.
  ///   붙었다 떨어졌다 해야 붙는 것이 사건이 된다
  static const _keyframes = <(double, double)>[
    (0.0, 0.06), // 각자의 리듬으로 출발
    (6.0, 0.28),
    (12.0, 0.60),
    (17.0, 0.93), // ── 공명 1
    (33.0, 0.96),
    (39.0, 0.55), // 흐트러짐
    (47.0, 0.36),
    (55.0, 0.72),
    (61.0, 0.94), // ── 공명 2
    (94.0, 0.97),
    (103.0, 0.58),
    (114.0, 0.42),
    (124.0, 0.78),
    (136.0, 0.95), // ── 공명 3 (길게 유지)
    (200.0, 0.96),
    (206.0, 0.45),
    (210.0, 0.08), // 루프 지점 — 0초 값과 가깝게 두어 이어붙는 자리가 안 보이게
  ];

  /// 지수가 먼저 보내는 신호. 한 바퀴 안에 **세 종류가 모두 한 번씩** 온다 —
  /// 데모의 목적이 "이런 게 온다"를 겪게 하는 것이라 하나라도 빠지면 안 된다.
  ///
  /// 공명 구간과 겹치지 않게 흩어 두었다: 나중에 소리가 붙으면 공명음과
  /// 신호음이 같은 순간에 겹쳐 서로를 먹는다
  static const _signals = <(double, SignalKind)>[
    (24.0, SignalKind.here),
    (48.0, SignalKind.cheer),
    (108.0, SignalKind.slow),
    (150.0, SignalKind.here),
  ];

  /// [since] 시점의 발맞춤 원본값(0~1).
  ///
  /// 꼭짓점 사이를 선형 보간한 뒤 미세한 흔들림을 얹는다. 흔들림은 살아 있는
  /// 느낌 때문이기도 하지만, **문턱 근처에서 히스테리시스가 실제로 일하는지**
  /// 데모에서 눈으로 보기 위한 것이기도 하다
  static double closenessAt(Duration since) {
    final t = _wrap(since);
    var v = _interpolate(t);
    v += 0.018 * math.sin(t * 2.3) + 0.010 * math.sin(t * 0.7);
    return v.clamp(0.0, 1.0);
  }

  /// ([from], [to]] 구간에 지수가 보낸 신호들. 루프를 넘어가도 빠뜨리지 않는다
  static List<SignalKind> signalsBetween(Duration from, Duration to) {
    if (to <= from) return const [];
    final periodSec = period.inSeconds.toDouble();
    final a = from.inMicroseconds / Duration.microsecondsPerSecond;
    final b = to.inMicroseconds / Duration.microsecondsPerSecond;
    final out = <SignalKind>[];
    for (var cycle = (a ~/ periodSec); cycle <= (b ~/ periodSec); cycle++) {
      for (final (at, kind) in _signals) {
        final abs = cycle * periodSec + at;
        if (abs > a && abs <= b) out.add(kind);
      }
    }
    return out;
  }

  static double _wrap(Duration since) {
    final periodSec = period.inSeconds.toDouble();
    final t = since.inMicroseconds / Duration.microsecondsPerSecond;
    return t <= 0 ? 0.0 : t % periodSec;
  }

  static double _interpolate(double t) {
    for (var i = 0; i < _keyframes.length - 1; i++) {
      final (t0, v0) = _keyframes[i];
      final (t1, v1) = _keyframes[i + 1];
      if (t >= t0 && t <= t1) {
        final span = t1 - t0;
        return span <= 0 ? v1 : v0 + (v1 - v0) * ((t - t0) / span);
      }
    }
    return _keyframes.last.$2;
  }
}

/// [DemoResonanceScript]를 실제 시계에 물려 [ResonanceEngine]에 흘려 넣는다.
///
/// 실제 세션에는 이런 게 없다 — 러닝 중 실시간 동기화가 없어서 상대의
/// 발맞춤을 알 방법이 지금은 없기 때문이다(라이브 합산은 v1.1). 그래서 지금
/// 공명이 실제로 일어나는 곳은 데모뿐이고, 실제 세션에서는 신호·마일스톤
/// 이벤트만 흐른다.
class DemoResonanceDriver {
  DemoResonanceDriver(this._engine, {DateTime Function()? clock, Random? random})
      : _clock = clock ?? DateTime.now,
        _random = random ?? Random();

  /// 스무딩 시정수(1초)에 비해 충분히 촘촘하면서, 배터리를 축내지 않는 주기
  static const tick = Duration(milliseconds: 100);

  /// 내가 신호를 보냈을 때 지수가 답할 확률.
  ///
  /// 1.0이 아닌 이유: 매번 답이 오면 사람이 아니라 자동응답기다.
  /// 그렇다고 낮으면 안 된다 — **신호를 보냈는데 아무 일도 없으면 다시는
  /// 안 보낸다.** 그래서 대체로 오되 가끔 안 오는 쪽으로 잡았다
  static const replyChance = 0.75;

  /// 답이 오기까지의 간격. 즉답은 기계처럼 느껴지고, 너무 늦으면 내가 보낸
  /// 것과 이어지지 않는다
  static const replyDelayMin = Duration(seconds: 5);
  static const replyDelayMax = Duration(seconds: 15);

  final ResonanceEngine _engine;
  final DateTime Function() _clock;
  final Random _random;
  Timer? _timer;
  DateTime? _startedAt;
  Duration _lastElapsed = Duration.zero;
  StreamSubscription<ResonanceEvent>? _sentSub;

  /// 내가 보낸 신호에 대한 지수의 답 — (보낼 시각, 종류)
  final _pendingReplies = <(Duration, SignalKind)>[];

  void start() {
    if (_timer != null) return;
    _startedAt = _clock();
    _lastElapsed = Duration.zero;
    _pendingReplies.clear();
    _sentSub = _engine.events.listen((e) {
      if (e is SignalSent) _scheduleReply(e.kind);
    });
    _engine.addSample(DemoResonanceScript.closenessAt(Duration.zero),
        at: _startedAt!);
    _timer = Timer.periodic(tick, (_) => pump());
  }

  /// 내가 보낸 신호에 지수가 답할지, 답한다면 언제 무엇으로 답할지 정한다.
  ///
  /// 답의 종류: 절반은 같은 신호(받았다는 뜻이 가장 분명하다), 나머지는
  /// 다른 신호. 늘 똑같이 되받으면 메아리처럼 느껴진다
  void _scheduleReply(SignalKind mine) {
    if (_random.nextDouble() > replyChance) return;
    final span = replyDelayMax - replyDelayMin;
    final delay = replyDelayMin +
        Duration(milliseconds: _random.nextInt(span.inMilliseconds + 1));
    final kind = _random.nextBool()
        ? mine
        : SignalKind.values[_random.nextInt(SignalKind.values.length)];
    _pendingReplies.add((_lastElapsed + delay, kind));
  }

  /// 한 틱 진행 — 타이머가 부르지만, 테스트에서는 직접 부른다
  void pump() {
    final start = _startedAt;
    if (start == null) return;
    final now = _clock();
    final elapsed = now.difference(start);
    _engine.addSample(DemoResonanceScript.closenessAt(elapsed), at: now);
    for (final kind in DemoResonanceScript.signalsBetween(_lastElapsed, elapsed)) {
      _engine.signalReceived(kind, at: now);
    }
    _pendingReplies.removeWhere((reply) {
      final (at, kind) = reply;
      if (at > elapsed) return false;
      _engine.signalReceived(kind, at: now);
      return true;
    });
    _lastElapsed = elapsed;
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _startedAt = null;
    _sentSub?.cancel();
    _sentSub = null;
    _pendingReplies.clear();
  }
}
