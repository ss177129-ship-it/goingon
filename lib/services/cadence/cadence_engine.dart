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

import 'package:flutter/foundation.dart' show visibleForTesting;
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
  /// [clock]은 테스트에서만 넘긴다. 이 엔진의 판정은 전부 시간 간격이라
  /// 실시간에 묶어두면 "180spm을 3분간 달렸을 때"를 검증할 방법이 없다.
  CadenceEngine({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now {
    _gaitCandidateSince = _clock();
  }

  final DateTime Function() _clock;

  // ── 튜닝 파라미터 ─────────────────────────────────────────────
  //
  // **상태: 합성 검증 통과(2026-08-22) · 실측 미확정.**
  // test/cadence_engine_test.dart가 합성 발걸음 신호로 ±3spm과 gait 전환
  // 10초를 지킨다. 그건 "알고리즘이 깨끗한 신호를 옳게 센다"는 뜻이지
  // "사람의 주머니 안에서 ±3spm"이라는 뜻이 아니다. 실제 가속도에는 팔
  // 흔들림·노면 충격·옷 스침·폰 회전이 섞이고, 그건 실주행 CSV를 받아야만
  // 안다. CSV가 오면 tools/analyze-probe-csv.py가 구간별 오차를 낸다.
  // 실측을 통과하기 전까지 이 값들은 여전히 가설이다.
  // 스텝 검출: 중력 제거 가속도의 크기가 임계를 상향 돌파하면 한 걸음.
  // 임계는 고정값이 아니라 최근 2초 신호의 평균+k·표준편차 — 사람마다,
  // 주머니 위치마다 진폭이 달라서 고정 임계는 반드시 틀린다.
  static const double kThresholdK = 1.2;
  static const Duration kEnvelopeWindow = Duration(seconds: 2);

  // 불응기: 240spm(초당 4걸음)보다 빠른 피크는 같은 걸음의 잔진동이다.
  static const Duration kRefractory = Duration(milliseconds: 250);

  // 적응 임계의 절대 바닥. 이것이 없으면 **가만히 서 있을 때 임계가 노이즈
  // 크기까지 내려앉아 걸음을 만들어낸다** — 신호가 없으면 임계도 없어지므로
  // 노이즈 봉우리가 전부 걸음이 된다(합성 검증에서 실제로 재현됨: 15초간
  // 서 있었는데 139spm). 그러면 신호등 앞에 선 러너의 gait이 영영 running에
  // 머물고 §2-2의 잔향 판정("발이 결정한다")이 트리거되지 않는다.
  //
  // 착지 충격은 폰이 주머니에 깊이 들어가도 수 m/s² 단위의 임펄스인 반면
  // 정지 시 userAccelerometer 노이즈는 그보다 한 자릿수 작다. 합성 신호
  // 기준: 서 있기 peak 1.16 / 주머니 러닝 peak 3.00 — 그 사이를 가른다.
  static const double kMinStepMag = 1.5;

  // 이 간격보다 오래 걸음이 없으면 idle로 간주한다.
  static const Duration kStepTimeout = Duration(milliseconds: 1800);

  // 걷기/달리기 히스테리시스 (제품설계도 §3-1과 동일한 경계).
  static const double kRunEnterSpm = 140;
  static const double kWalkEnterSpm = 120;

  // 후보 상태가 이만큼 유지되어야 확정. **10초가 아니라 3초인 이유**:
  // 펄럭임을 막는 일차 방어는 120/140 경계 밴드(히스테리시스) 자체이고,
  // 이 hold는 이차 방어다. 여기에 10초를 두면 스무딩 지연(3초 시정수)과
  // 합쳐져 달리기→걷기 전환이 15초를 넘고(합성 검증에서 재현), 그 위에
  // §2-2의 잔향 판정이 다시 "걷기 10초 지속"을 세므로 쿨다운이 25초 뒤에
  // 온다. **"몇 초 지속되어야 국면을 바꾸는가"는 세션 상태머신(P3)의 몫**,
  // 이 엔진의 몫은 "지금 무슨 걸음인가"다. 둘을 겹쳐 세지 않는다.
  static const Duration kGaitHold = Duration(seconds: 3);

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
  late DateTime _gaitCandidateSince;
  GaitState _gaitCandidate = GaitState.idle;

  Stream<CadenceSample> get samples => _samples.stream;

  /// 스텝 하나가 검출될 때마다 발화. 프로브의 실측 카운트와,
  /// 나중에는 '내 발소리' 토글의 퍼커션 트리거가 이것을 쓴다.
  final _steps = StreamController<DateTime>.broadcast();
  Stream<DateTime> get steps => _steps.stream;

  /// 합성 신호 검증용 주입구. `start()`가 하는 일을 테스트가 직접 한다 —
  /// 센서 스트림 대신 가속도 샘플을 밀어 넣고([feedForTest]), 1초 티커 대신
  /// 직접 요약을 만들게([tickForTest]) 한다. 프로덕션 경로는 건드리지 않는다.
  /// 스텝이 검출됐으면 true. 스트림은 비동기로 전달되므로 동기 루프를
  /// 도는 테스트는 값을 돌려받아야 한다.
  @visibleForTesting
  bool feedForTest(UserAccelerometerEvent e) => _onAccel(e);

  @visibleForTesting
  CadenceSample tickForTest() => _emit();

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

  bool _onAccel(UserAccelerometerEvent e) {
    final now = _clock();
    final mag = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);

    _envelope.addLast((at: now, mag: mag));
    while (_envelope.isNotEmpty &&
        now.difference(_envelope.first.at) > kEnvelopeWindow) {
      _envelope.removeFirst();
    }
    if (_envelope.length < 10) return false;

    double mean = 0;
    for (final s in _envelope) {
      mean += s.mag;
    }
    mean /= _envelope.length;
    double variance = 0;
    for (final s in _envelope) {
      variance += (s.mag - mean) * (s.mag - mean);
    }
    final std = math.sqrt(variance / _envelope.length);
    final threshold = mean + kThresholdK * std;

    // 상향 돌파 + 불응기 = 한 걸음. 하향 복귀 전까지는 재무장하지 않는다 —
    // 임계 근처에서 떨리는 신호가 걸음 두 개로 세어지는 것을 막는다.
    if (!_above && mag > threshold && mag > kMinStepMag) {
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
        return true;
      }
    } else if (_above && mag < mean) {
      _above = false;
    }
    return false;
  }

  CadenceSample _emit() {
    final now = _clock();

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
    const dt = 1.0;
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
      for (final s in _spmHistory) {
        m += s.spm;
      }
      m /= _spmHistory.length;
      double v = 0;
      for (final s in _spmHistory) {
        v += (s.spm - m) * (s.spm - m);
      }
      final std = math.sqrt(v / _spmHistory.length);
      stability = (1 - (std / 15)).clamp(0.0, 1.0);
    }

    _updateGait(now);
    final sample = CadenceSample(
      at: now,
      spm: _smoothedSpm,
      stability: stability,
      gait: _gait,
    );
    _samples.add(sample);
    return sample;
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
