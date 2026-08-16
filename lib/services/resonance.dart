import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// 화면·소리·햅틱이 **함께** 쓰는 스무딩 시정수.
///
/// 이름에 `shared`가 붙은 이유가 전부다: 나중에 붙을 오디오(볼륨·필터 컷오프)도
/// 반드시 이 값으로 스무딩해야 한다. 값이 갈라지면 소리와 화면이 서로 다른
/// 속도로 붙었다 떨어져, 두 개의 다른 일이 벌어지는 것처럼 느껴진다.
/// **바꾸려면 오디오 쪽과 같이 바꿀 것.**
const kSharedSmoothingTimeConstant = Duration(seconds: 1);

/// 두 사람이 얼마나 발을 맞추고 있는지 — 연속값([ResonanceEngine.smoothedCloseness])
/// 과 별개로, "순간"을 만들기 위한 **이산 상태**.
///
/// 넷을 넘기지 않는다. 사운드 디자인 비용이 상태 수에 정비례하기 때문에,
/// 다섯 번째 상태를 넣고 싶어지면 먼저 그 상태의 소리부터 상상해볼 것.
enum SyncState {
  /// 각자의 리듬 — 아직 서로를 못 찾음
  drifting,

  /// 가까워지는 중
  approaching,

  /// 나란히
  aligned,

  /// 공명 — 발이 똑 맞은 순간
  resonant;

  bool operator >(SyncState other) => index > other.index;
  bool operator <(SyncState other) => index < other.index;
}

/// 상태 판정 문턱값. **진입과 이탈이 반드시 다르다(히스테리시스).**
///
/// 문턱이 하나면 경계에서 상태가 초당 수십 번 튄다. 화면만 있을 땐 미세한
/// 깜빡임이지만, 여기에 소리와 햅틱이 걸리면 진입음이 1초에 열 번 울린다.
/// 이 클래스가 존재하는 유일한 이유가 그것을 막는 것이다.
///
/// 폭(진입-이탈)은 위로 갈수록 넓게 잡았다. 위쪽 상태일수록 "그 상태에
/// 머물러 있다"는 감각 자체가 보상이라, 잠깐 흔들렸다고 깨지면 손해가 크다.
class ResonanceThresholds {
  const ResonanceThresholds._();

  /// 공명 진입 — 프로토타입(`prototype_v2.html`)의 `sync>.93`보다 낮게 잡았다.
  /// 프로토타입은 슬라이더로 케이던스를 직접 맞추지만 실제 러닝에서 .93은
  /// 거의 도달하지 않아, 가장 중요한 순간이 영영 안 오는 쪽이 더 큰 실패다
  static const resonantEnter = 0.88;

  /// 공명 이탈 — 폭 0.08. 한 걸음 어긋났다고 공명이 깨지면 안 된다
  static const resonantExit = 0.80;

  /// 나란히 진입
  static const alignedEnter = 0.70;

  /// 나란히 이탈 — 폭 0.10. 신호등·오르막에서 잠깐 벌어지는 정도는 견딘다
  static const alignedExit = 0.60;

  /// 다가옴 진입 — 이 아래는 "서로의 리듬을 찾는 중"
  static const approachingEnter = 0.30;

  /// 다가옴 이탈 — 폭 0.08
  static const approachingExit = 0.22;

  /// 공명을 유지했을 때 알려줄 지점. 자주 울리면 의미가 닳으므로
  /// 10초(우연이 아님) → 30초(맞추고 있음) → 60초(같이 달리고 있음)
  static const holdMilestones = <Duration>[
    Duration(seconds: 10),
    Duration(seconds: 30),
    Duration(seconds: 60),
  ];
}

/// 히스테리시스가 들어간 상태 판정 — 엔진과 분리해 두어 앱 없이 시험할 수 있다
class SyncStateMachine {
  const SyncStateMachine._();

  /// [current]에서 [closeness](스무딩된 값)를 보고 다음 상태를 고른다.
  ///
  /// 규칙 하나로 적으면: **올라갈 땐 진입 문턱, 내려올 땐 이탈 문턱.**
  /// 그래서 값이 두 문턱 사이에 있는 동안은 지금 상태가 그대로 유지된다.
  static SyncState resolve(SyncState current, double closeness) {
    final canRise = _byEnter(closeness);
    final canHold = _byExit(closeness); // 항상 canRise 이상
    if (current > canHold) return canHold; // 이탈 문턱 아래로 떨어짐
    if (current < canRise) return canRise; // 진입 문턱을 넘어섬
    return current; // 문턱 사이 — 유지
  }

  static SyncState _byEnter(double v) {
    if (v > ResonanceThresholds.resonantEnter) return SyncState.resonant;
    if (v > ResonanceThresholds.alignedEnter) return SyncState.aligned;
    if (v > ResonanceThresholds.approachingEnter) return SyncState.approaching;
    return SyncState.drifting;
  }

  static SyncState _byExit(double v) {
    if (v > ResonanceThresholds.resonantExit) return SyncState.resonant;
    if (v > ResonanceThresholds.alignedExit) return SyncState.aligned;
    if (v > ResonanceThresholds.approachingExit) return SyncState.approaching;
    return SyncState.drifting;
  }
}

/// 서로에게 보내는 신호 — 러닝 화면의 탭/스와이프/길게 누르기.
///
/// **셋을 넘지 않는다.** 달리면서 네 번째를 기억하지 못한다. 프로토타입
/// (`prototype_v2.html`)에는 넷이 있지만(파이팅·보고싶어·빨라지자·천천히)
/// 셋으로 줄이며 '같이 빨라지자'와 '보고싶어'를 뺐다.
///
/// 신호에는 **글자가 붙지 않는다.** 화면에 단어를 띄우면 달리는 사람이
/// 그걸 읽으려 하고, 신호는 언어가 아니라 감각이어야 한다. 여기 적힌 뜻은
/// 코드를 읽는 사람을 위한 것이지 화면에 나오는 문구가 아니다.
enum SignalKind {
  /// 짧게 탭 — "여기 있어" (가벼운 존재 확인)
  here('here'),

  /// 스와이프 — "힘내" (응원)
  cheer('enc'),

  /// 길게 누르기 — "천천히 가자" (페이스 조절 제안)
  slow('dn');

  const SignalKind(this.gestureType);

  /// Firestore `sessions/{id}.gesture.type`에 실려 가는 문자열.
  /// 뜻이 이어지는 것은 예전 값을 그대로 쓴다(응원 `enc`, 천천히 `dn`) —
  /// 구버전 클라이언트가 보낸 신호도 같은 뜻으로 도착한다
  final String gestureType;

  /// 모르는 값(빠진 신호 `up`·`heart`를 쓰는 구버전 등)은 응원으로 받는다.
  /// 러닝 중에 "알 수 없는 신호"를 띄우는 것보다 낫다
  static SignalKind fromGestureType(String type) => values.firstWhere(
        (k) => k.gestureType == type,
        orElse: () => SignalKind.cheer,
      );
}

/// 같은 신호를 연달아 보내는 것을 막는다.
///
/// 왜 조용히 막는가: 쿨다운 중이라고 화면에 알리면 그건 러닝 중에 뜨는
/// 에러 UI가 되고, 에러 UI는 죄책감 장치다. 상대에게 안 갔다는 사실보다
/// "내가 뭘 잘못했나"가 더 오래 남는다. 그래서 무시하되 아무 말도 안 한다.
class SignalCooldown {
  SignalCooldown({this.window = const Duration(seconds: 10)});

  /// 같은 신호를 다시 보낼 수 있게 되기까지
  final Duration window;

  final _lastSent = <SignalKind, DateTime>{};

  /// 지금 [kind]를 보낼 수 있으면 true, 그리고 보낸 것으로 기록한다.
  /// **다른 신호는 서로를 막지 않는다** — 탭 직후 길게 누르기는 스팸이
  /// 아니라 말을 바꾼 것이다
  bool allow(SignalKind kind, DateTime at) {
    final last = _lastSent[kind];
    if (last != null && at.difference(last) < window) return false;
    _lastSent[kind] = at;
    return true;
  }
}

/// 거리·시간 마일스톤의 종류
enum MilestoneKind { distanceKm, minutes }

/// UI·사운드·햅틱이 **함께 구독하는 단일 이벤트**.
///
/// 각자 상태를 들여다보며 "지금 바뀌었나?"를 판정하면 세 곳의 판정이 조금씩
/// 어긋난다(화면은 반짝였는데 소리는 안 나는 식). 판정은 여기 한 곳에서만 하고,
/// 나머지는 결과만 받는다.
sealed class ResonanceEvent {
  const ResonanceEvent(this.at);

  final DateTime at;

  /// 콘솔 로그 한 줄 — 사람이 시간순으로 훑어보기 위한 것
  String describe();
}

/// 상태 전이
class ResonanceStateChanged extends ResonanceEvent {
  const ResonanceStateChanged({
    required this.from,
    required this.to,
    required this.closeness,
    required DateTime at,
  }) : super(at);

  final SyncState from;
  final SyncState to;

  /// 전이가 일어난 시점의 스무딩된 값 — 문턱을 얼마나 넘겼는지 로그로 볼 용도
  final double closeness;

  @override
  String describe() =>
      'stateChanged ${from.name} → ${to.name} (${closeness.toStringAsFixed(3)})';
}

/// 공명 진입 — 이 앱에서 가장 중요한 순간.
/// [ResonanceStateChanged]와 중복이지만, 구독자가 "공명만" 듣고 싶을 때
/// 상태 비교를 다시 짜지 않도록 따로 낸다
class ResonanceEntered extends ResonanceEvent {
  const ResonanceEntered(super.at);

  @override
  String describe() => 'resonanceEntered ✦';
}

/// 공명을 [held]만큼 유지함 (10초/30초/60초)
class ResonanceHeld extends ResonanceEvent {
  const ResonanceHeld({required this.held, required DateTime at}) : super(at);

  final Duration held;

  @override
  String describe() => 'resonanceHeld ${held.inSeconds}s';
}

/// 내가 보낸 신호
class SignalSent extends ResonanceEvent {
  const SignalSent({required this.kind, required DateTime at}) : super(at);

  final SignalKind kind;

  @override
  String describe() => 'signalSent ${kind.name}';
}

/// 상대가 보낸 신호가 도착함
class SignalReceived extends ResonanceEvent {
  const SignalReceived({required this.kind, required DateTime at}) : super(at);

  final SignalKind kind;

  @override
  String describe() => 'signalReceived ${kind.name}';
}

/// 1km 통과, 10분 경과 같은 지점
class MilestoneReached extends ResonanceEvent {
  const MilestoneReached({
    required this.kind,
    required this.value,
    required DateTime at,
  }) : super(at);

  final MilestoneKind kind;

  /// 몇 번째인지 — distanceKm면 km 정수, minutes면 분
  final int value;

  @override
  String describe() => 'milestone ${kind.name} $value';
}

/// 연속값(closeness)을 받아 **순간**을 만들어내는 곳.
///
/// 하는 일은 셋뿐이다:
/// 1. raw closeness를 [kSharedSmoothingTimeConstant]로 스무딩한다
/// 2. 스무딩된 값을 히스테리시스로 이산 상태로 접는다
/// 3. 상태가 바뀐 순간·신호·마일스톤을 하나의 스트림으로 내보낸다
///
/// 이벤트 스트림은 broadcast라 **구독자가 0명이면 이벤트는 그냥 버려진다.**
/// 즉 이 엔진을 붙여도 아무도 듣지 않는 동안에는 앱 동작이 이전과 같다.
class ResonanceEngine {
  ResonanceEngine({this.smoothingTimeConstant = kSharedSmoothingTimeConstant});

  /// 테스트에서만 바꾼다. 실사용에서는 오디오와 같은 값이어야 한다
  final Duration smoothingTimeConstant;

  final _events = StreamController<ResonanceEvent>.broadcast();

  /// UI·사운드·햅틱이 함께 구독하는 스트림
  Stream<ResonanceEvent> get events => _events.stream;

  double _raw = 0;
  double? _smoothed;
  DateTime? _lastSampleAt;
  SyncState _state = SyncState.drifting;
  DateTime? _resonantSince;
  int _heldMilestoneIndex = 0;
  int _lastKmMilestone = 0;
  int _lastMinuteMilestone = 0;

  /// 마지막으로 들어온 원본 값 — 진단·테스트용. **UI는 쓰지 말 것**
  double get rawCloseness => _raw;

  /// UI가 소비해야 하는 값. raw를 그대로 그리면 GPS·케이던스 잡음이 그대로
  /// 화면 떨림이 된다
  double get smoothedCloseness => _smoothed ?? 0;

  SyncState get state => _state;

  /// 발맞춤 값이 실제로 들어오고 있는가.
  ///
  /// 실제 세션에는 아직 이 값을 만들 방법이 없다(러닝 중 실시간 동기화 없음).
  /// 그때 [state]는 `drifting`으로 남는데, 그걸 화면에 "각자의 리듬"이라고
  /// 쓰면 **모르는 것을 아는 것처럼 말하는 셈**이다. 화면은 이 값이 false면
  /// 상태어 대신 중립적인 문구를 보여야 한다
  bool get hasCloseness => _smoothed != null;

  /// 지금 공명을 얼마나 유지하고 있는지 (공명이 아니면 [Duration.zero])
  Duration get resonanceHeldFor {
    final since = _resonantSince;
    final at = _lastSampleAt;
    if (since == null || at == null) return Duration.zero;
    return at.difference(since);
  }

  /// 발맞춤 원본값을 넣는다. [at]은 샘플이 만들어진 시각 —
  /// 스무딩 계수를 **경과 시간으로** 계산하므로 호출 주기가 흔들려도(배경에서
  /// 타이머가 밀리는 건 흔하다) 스무딩 속도는 항상 시정수대로 유지된다.
  void addSample(double raw, {required DateTime at}) {
    final v = raw.clamp(0.0, 1.0).toDouble();
    _raw = v;

    final last = _lastSampleAt;
    if (_smoothed == null || last == null) {
      // 첫 샘플은 그대로 받는다 — 0에서 램프업시키면 세션 시작 직후
      // 있지도 않았던 "다가옴" 전이가 한 번 만들어진다
      _smoothed = v;
    } else {
      final dt = at.difference(last).inMicroseconds / Duration.microsecondsPerSecond;
      if (dt > 0) {
        final tau = smoothingTimeConstant.inMicroseconds /
            Duration.microsecondsPerSecond;
        // 지수 스무딩. dt가 크면(배경에 오래 있었으면) alpha가 1에 붙어
        // 현재 값으로 스냅되는데, 그게 맞다 — 그 사이의 값은 모르기 때문
        final alpha = 1 - math.exp(-dt / tau);
        _smoothed = _smoothed! + (v - _smoothed!) * alpha;
      }
    }
    _lastSampleAt = at;
    _evaluate(at);
  }

  void _evaluate(DateTime at) {
    final next = SyncStateMachine.resolve(_state, smoothedCloseness);
    if (next != _state) {
      final from = _state;
      _state = next;
      _emit(ResonanceStateChanged(
          from: from, to: next, closeness: smoothedCloseness, at: at));
      if (next == SyncState.resonant) {
        _resonantSince = at;
        _heldMilestoneIndex = 0;
        _emit(ResonanceEntered(at));
      } else {
        _resonantSince = null;
        _heldMilestoneIndex = 0;
      }
    }
    _checkHold(at);
  }

  void _checkHold(DateTime at) {
    final since = _resonantSince;
    if (since == null) return;
    final held = at.difference(since);
    while (_heldMilestoneIndex < ResonanceThresholds.holdMilestones.length &&
        held >= ResonanceThresholds.holdMilestones[_heldMilestoneIndex]) {
      final mark = ResonanceThresholds.holdMilestones[_heldMilestoneIndex];
      _heldMilestoneIndex++;
      _emit(ResonanceHeld(held: mark, at: at));
    }
  }

  /// 거리·시간 마일스톤. 러닝 화면의 1초 틱에서 부르면 된다.
  /// 같은 지점을 두 번 내지 않고, 값이 뒤로 가도(복구 후 재계산 등) 무시한다
  void updateProgress({
    required double km,
    required Duration elapsed,
    required DateTime at,
  }) {
    final kmMark = km.floor();
    if (kmMark > _lastKmMilestone) {
      _lastKmMilestone = kmMark;
      _emit(MilestoneReached(
          kind: MilestoneKind.distanceKm, value: kmMark, at: at));
    }
    // 10분 간격 — 더 잦으면 소리가 붙었을 때 의미가 닳는다
    final minuteMark = (elapsed.inMinutes ~/ 10) * 10;
    if (minuteMark > _lastMinuteMilestone) {
      _lastMinuteMilestone = minuteMark;
      _emit(MilestoneReached(
          kind: MilestoneKind.minutes, value: minuteMark, at: at));
    }
  }

  /// 내가 신호를 보냄
  void signalSent(SignalKind kind, {required DateTime at}) =>
      _emit(SignalSent(kind: kind, at: at));

  /// 상대 신호가 도착함
  void signalReceived(SignalKind kind, {required DateTime at}) =>
      _emit(SignalReceived(kind: kind, at: at));

  void _emit(ResonanceEvent e) {
    if (_events.isClosed) return;
    _events.add(e);
  }

  void dispose() {
    _events.close();
  }
}

/// 이벤트를 콘솔에 시간순으로 찍는 구독자 — 디버그 전용.
///
/// 사운드·햅틱이 붙기 전까지는 이게 유일한 구독자다. 데모 모드를 돌려
/// 순서와 간격이 사람이 느끼기에 말이 되는지 눈으로 확인하는 용도
class ResonanceEventLog {
  ResonanceEventLog._();

  StreamSubscription<ResonanceEvent>? _subscription;
  DateTime? _origin;

  /// [engine]의 이벤트를 `[resonance] +12.3s ...` 형태로 찍기 시작한다.
  /// 기준 시각은 첫 이벤트 — 세션이 시작하고 얼마 만에 무엇이 일어났는지
  /// 그대로 읽히게 하기 위함
  static ResonanceEventLog attach(ResonanceEngine engine, {String tag = ''}) {
    final log = ResonanceEventLog._();
    log._subscription = engine.events.listen((e) {
      final origin = log._origin ??= e.at;
      final t = e.at.difference(origin).inMilliseconds / 1000;
      debugPrint('[resonance]$tag +${t.toStringAsFixed(1)}s ${e.describe()}');
    });
    return log;
  }

  Future<void> cancel() async => _subscription?.cancel();
}
