// 케이던스 엔진 — sound_ux_v1.md가 '트랙 B(부록)'로 미뤄뒀던 그 코드.
//
// 새 제품 설계(제품설계도 v1.1)에서 케이던스는 확장이 아니라 심장이 됐다:
// 음악의 BPM이 이 값을 따라오고, 공명 판정의 입력이 페이스에서 이것으로
// 바뀐다. 그래서 정확도 기준이 명확하다 — **실주행에서 수동 카운트 대비
// ±3spm.** 이 기준을 통과하기 전에는 ResonanceEngine에 연결하지 않는다.
//
// GPS를 쓰지 않는다. 가속도계만으로 걸음을 세므로 폰이 주머니에 있어도,
// 실내 트레드밀에서도 동작한다 — "위치는 선택 부품"이라는 설계 결정의 구현.
//
// 파라미터 기본값은 초기 가설이다. main_cadence_probe.dart로 실측한 뒤
// 이 파일의 상수를 튜닝하는 것이 M0-a의 전부다.
import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

/// 걸음 상태. 세션 상태머신의 '잔향 판정'(발이 결정한다)이 이 값을 소비한다.
///
/// 셋을 넘기지 않는다 — 상태가 늘면 잔향 판정의 분기가 늘고, 분기가 늘면
/// 러너가 예측할 수 없는 앱이 된다.
enum GaitState { idle, walking, running }

/// 1Hz로 내보내는 요약. 소리(BPM)·화면(숫자)·판정(잔향)이 전부 이것만 본다.
class CadenceSample {
  const CadenceSample({
    required this.at,
    required this.spm,
    required this.stability,
    required this.gait,
  });

  final DateTime at;

  /// 분당 걸음수, 3초 시정수로 스무딩된 값. 스무딩 상수를 바꾸려면
  /// resonance.dart의 kSharedSmoothingTimeConstant와 함께 바꿀 것 —
  /// 소리와 화면이 다른 속도로 움직이면 두 개의 다른 일처럼 느껴진다.
  final double spm;

  /// 최근 60초 케이던스의 흔들림을 0(불안정)~1(안정)로. 음악 레이어
  /// 게이트(베이스·화성이 열리는 조건)가 소비한다.
  final double stability;

  final GaitState gait;
}

class CadenceEngine {
  CadenceEngine();

  // ── 튜닝 파라미터 (M0-a 실측 대상) ──────────────────────────────
  // 스텝 검출: 중력 제거 가속도의 크기가 임계를 상향 돌파하면 한 걸음.
  // 임계는 고정값이 아니라 최근 2초 신호의 평균+k·표준편차 — 사람마다,
  // 주머니 위치마다 진폭이 달라서 고정 임계는 반드시 틀린다.
  static const double kThresholdK = 1.2;
  static const Duration kEnvelopeWindow = Duration(seconds: 2);

  // 불응기: 240spm(초당 4걸음)보다 빠른 피크는 같은 걸음의 잔진동이다.
  static const Duration kRefractory = Duration(milliseconds: 250);

  // 이 간격보다 오래 걸음이 없으면 idle로 간주한다.
  static const Duration kStepTimeout = Duration(milliseconds: 1800);

  // 걷기/달리기 히스테리시스 (제품설계도 §3-1과 동일한 경계).
  static const double kRunEnterSpm = 140;
  static const double kWalkEnterSpm = 120;
  static const Duration kGaitHold = Duration(seconds: 10);

  static const Duration kSmoothing = Duration(seconds: 3);

  // ── 내부 상태 ──────────────────────────────────────────────────
  final _samples = StreamController<CadenceSample>.broadcast();
  final _stepTimes = Queue<DateTime>();
  final _envelope = Queue<({DateTime at, double mag})>();
  final _spmHistory = Queue<({DateTime at, double spm})>();

  StreamSubscription? _accSub;
  Timer? _ticker;
  double _smoothedSpm = 0;
  DateTime? _lastStepAt;
  GaitState _gait = GaitState.idle;
  DateTime _gaitCandidateSince = DateTime.now();
  GaitState _gaitCandidate = GaitState.idle;

  Stream<CadenceSample> get samples => _samples.stream;

  /// 스텝 하나가 검출될 때마다 발화. 프로브의 실측 카운트와,
  /// 나중에는 '내 발소리' 토글의 퍼커션 트리거가 이것을 쓴다.
  final _steps = StreamController<DateTime>.broadcast();
  Stream<DateTime> get steps => _steps.stream;

  void start() {
    // gameInterval(20ms)이면 240spm까지 나이키스트 여유가 충분하다.
    _accSub = userAccelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen(_onAccel);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _emit());
  }

  Future<void> stop() async {
    await _accSub?.cancel();
    _ticker?.cancel();
  }

  void dispose() {
    stop();
    _samples.close();
    _steps.close();
  }

  bool _above = false;

  void _onAccel(UserAccelerometerEvent e) {
    final now = DateTime.now();
    final mag = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);

    _envelope.addLast((at: now, mag: mag));
    while (_envelope.isNotEmpty &&
        now.difference(_envelope.first.at) > kEnvelopeWindow) {
      _envelope.removeFirst();
    }
    if (_envelope.length < 10) return;

    double mean = 0;
    for (final s in _envelope) mean += s.mag;
    mean /= _envelope.length;
    double variance = 0;
    for (final s in _envelope) variance += (s.mag - mean) * (s.mag - mean);
    final std = math.sqrt(variance / _envelope.length);
    final threshold = mean + kThresholdK * std;

    // 상향 돌파 + 불응기 = 한 걸음. 하향 복귀 전까지는 재무장하지 않는다 —
    // 임계 근처에서 떨리는 신호가 걸음 두 개로 세어지는 것을 막는다.
    if (!_above && mag > threshold) {
      _above = true;
      final last = _lastStepAt;
      if (last == null || now.difference(last) >= kRefractory) {
        _lastStepAt = now;
        _stepTimes.addLast(now);
        while (_stepTimes.isNotEmpty &&
            now.difference(_stepTimes.first) > const Duration(seconds: 5)) {
          _stepTimes.removeFirst();
        }
        _steps.add(now);
      }
    } else if (_above && mag < mean) {
      _above = false;
    }
  }

  void _emit() {
    final now = DateTime.now();

    // 순간 spm: 최근 5초 창의 평균 간격. 창이 짧으면 민첩하지만 떨리고,
    // 길면 안정적이지만 굼뜨다. 5초는 초기 가설 — 프로브로 검증할 것.
    double instantSpm = 0;
    if (_stepTimes.length >= 3 &&
        _lastStepAt != null &&
        now.difference(_lastStepAt!) < kStepTimeout) {
      final span = _stepTimes.last.difference(_stepTimes.first).inMilliseconds;
      if (span > 0) {
        instantSpm = (_stepTimes.length - 1) * 60000 / span;
      }
    }

    // EMA 스무딩 (시정수 3초 — 공유 상수 원칙).
    final dt = 1.0;
    final alpha = 1 - math.exp(-dt / kSmoothing.inSeconds);
    _smoothedSpm += alpha * (instantSpm - _smoothedSpm);
    if (instantSpm == 0 && now.difference(_lastStepAt ?? now) > kStepTimeout) {
      _smoothedSpm = 0; // 멈췄으면 굼뜨게 내려가지 말고 바로 0 — 잔향 판정의 정직함
    }

    _spmHistory.addLast((at: now, spm: _smoothedSpm));
    while (_spmHistory.isNotEmpty &&
        now.difference(_spmHistory.first.at) > const Duration(seconds: 60)) {
      _spmHistory.removeFirst();
    }
    double stability = 0;
    if (_spmHistory.length >= 10 && _smoothedSpm > 0) {
      double m = 0;
      for (final s in _spmHistory) m += s.spm;
      m /= _spmHistory.length;
      double v = 0;
      for (final s in _spmHistory) v += (s.spm - m) * (s.spm - m);
      final std = math.sqrt(v / _spmHistory.length);
      stability = (1 - (std / 15)).clamp(0.0, 1.0);
    }

    _updateGait(now);
    _samples.add(CadenceSample(
      at: now,
      spm: _smoothedSpm,
      stability: stability,
      gait: _gait,
    ));
  }

  void _updateGait(DateTime now) {
    // 경계값 하나로 오가면 139↔141에서 상태가 펄럭인다. 후보 상태가
    // kGaitHold만큼 유지되어야 확정 — 잔향 판정(10초)과 같은 리듬.
    final GaitState candidate;
    if (_smoothedSpm >= kRunEnterSpm) {
      candidate = GaitState.running;
    } else if (_smoothedSpm > 0 && _smoothedSpm <= kWalkEnterSpm) {
      candidate = GaitState.walking;
    } else if (_smoothedSpm == 0) {
      candidate = GaitState.idle;
    } else {
      candidate = _gait; // 히스테리시스 구간(120~140)에서는 현 상태 유지
    }
    if (candidate != _gaitCandidate) {
      _gaitCandidate = candidate;
      _gaitCandidateSince = now;
    }
    if (_gaitCandidate != _gait &&
        now.difference(_gaitCandidateSince) >= kGaitHold) {
      _gait = _gaitCandidate;
    }
  }
}
