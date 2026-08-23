// 케이던스 엔진 — 합성 신호 검증 (M0-a의 실측 대역).
//
// **이 테스트는 실주행을 대신하지 않는다.** 여기서 통과한다는 것은
// "알고리즘이 깨끗한 발걸음 신호를 옳게 센다"는 뜻이지, "사람의 주머니
// 안에서 ±3spm"이라는 뜻이 아니다. 실제 가속도에는 팔 흔들림·노면
// 충격·옷 스침·폰 회전이 섞이고, 그건 CSV를 받아봐야만 안다.
//
// 그럼에도 이 층이 필요한 이유: 실측이 실패했을 때 "알고리즘이 틀렸나,
// 파라미터가 안 맞나, 신호가 더러운가"를 가르지 못하면 튜닝이 추측이 된다.
// 여기서 알고리즘을 못 박아두면 실측 실패는 곧 파라미터/신호 문제로 좁혀진다.
//
// 합성 모델: 한 걸음 = 짧은 가우시안 펄스(착지 충격) + 백색 노이즈.
// 진폭은 폰 위치를 흉내 낸다 — 손(크게 흔들림) > 암밴드 > 주머니(감쇠).
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:goingon/services/cadence/cadence_engine.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// 50Hz(gameInterval)로 발걸음 신호를 만들어 엔진에 밀어 넣는다.
/// 1초마다 [CadenceEngine.tickForTest]를 불러 요약을 만든다.
class _Rig {
  _Rig({this.seed = 7}) {
    engine = CadenceEngine(clock: () => _now);
  }

  static const _hz = 50;
  static const _dt = Duration(milliseconds: 1000 ~/ _hz);

  final int seed;
  late final CadenceEngine engine;
  final samples = <CadenceSample>[];
  int stepCount = 0;

  DateTime _now = DateTime.utc(2026, 8, 22, 6, 0, 0);
  late final _rnd = math.Random(seed);
  DateTime? _lastTick;

  /// [spm]으로 [seconds]초 달린다. [amplitude]는 착지 충격의 크기(m/s²),
  /// [noise]는 백색 노이즈의 표준편차. spm=0이면 서 있는 것(노이즈만).
  void run(double spm, int seconds,
      {double amplitude = 6.0, double noise = 0.4}) {
    final stepPeriodMs = spm > 0 ? 60000 / spm : double.infinity;
    // 펄스 폭은 접지 시간에 대응한다 — 빠를수록 짧다.
    final sigmaMs = spm > 0 ? math.max(25.0, stepPeriodMs * 0.12) : 1.0;
    final total = seconds * _hz;

    for (var i = 0; i < total; i++) {
      final tMs = _now.difference(_epoch).inMilliseconds.toDouble();
      var mag = _gauss() * noise;
      if (spm > 0) {
        // 가장 가까운 두 걸음의 펄스만 더하면 충분하다.
        final n = (tMs / stepPeriodMs).floor();
        for (var k = n; k <= n + 1; k++) {
          final d = tMs - k * stepPeriodMs;
          mag += amplitude * math.exp(-(d * d) / (2 * sigmaMs * sigmaMs));
        }
      }
      if (engine.feedForTest(UserAccelerometerEvent(mag, 0, 0, _now))) {
        stepCount++;
      }
      _now = _now.add(_dt);
      if (_lastTick == null ||
          _now.difference(_lastTick!) >= const Duration(seconds: 1)) {
        _lastTick = _now;
        samples.add(engine.tickForTest());
      }
    }
  }

  static final _epoch = DateTime.utc(2026, 8, 22, 6, 0, 0);

  double _gauss() {
    final u1 = 1 - _rnd.nextDouble();
    final u2 = _rnd.nextDouble();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }

  /// 마지막 [seconds]초 동안의 spm 평균 — 스무딩이 자리잡은 뒤를 본다.
  double settledSpm({int seconds = 10}) {
    final tail = samples.reversed.take(seconds).map((s) => s.spm).toList();
    return tail.reduce((a, b) => a + b) / tail.length;
  }

  GaitState get gait => samples.last.gait;
}

void main() {
  group('spm 정확도 — 기준 ±3spm', () {
    // 걷기 110 ~ 빠른 러닝 190. 각 값에서 60초 달리고 마지막 10초를 본다.
    for (final trueSpm in [110.0, 140.0, 155.0, 170.0, 180.0, 190.0]) {
      test('${trueSpm.toInt()}spm을 ±3spm 안에서 센다', () {
        final rig = _Rig()..run(trueSpm, 60);
        final measured = rig.settledSpm();
        expect((measured - trueSpm).abs(), lessThanOrEqualTo(3.0),
            reason: '측정 ${measured.toStringAsFixed(1)} vs 실제 $trueSpm');
      });
    }

    // 노이즈 시드 하나에서만 맞으면 운이 좋았던 것일 수 있다.
    test('노이즈 시드 8개 전부에서 170spm을 ±3spm', () {
      final errors = <double>[];
      for (var seed = 1; seed <= 8; seed++) {
        final rig = _Rig(seed: seed)..run(170, 60);
        errors.add((rig.settledSpm() - 170).abs());
      }
      expect(errors.every((e) => e <= 3.0), isTrue,
          reason: '시드별 오차: ${errors.map((e) => e.toStringAsFixed(1))}');
    });
  });

  group('폰 위치 — 진폭이 달라도 같은 값', () {
    // 고정 임계를 쓰면 여기서 무너진다. 적응 임계(평균+k·표준편차)의 존재 이유.
    for (final (name, amp, noise) in [
      ('주머니(감쇠)', 2.5, 0.35),
      ('암밴드', 6.0, 0.40),
      ('손(크게 흔듦)', 12.0, 0.90),
    ]) {
      test('$name에서도 170spm을 ±3spm', () {
        final rig = _Rig()..run(170, 60, amplitude: amp, noise: noise);
        final measured = rig.settledSpm();
        expect((measured - 170).abs(), lessThanOrEqualTo(3.0),
            reason: '$name: 측정 ${measured.toStringAsFixed(1)}');
      });
    }
  });

  group('gait 전환 — 기준 10초 내 추종', () {
    test('걷기 → 달리기', () {
      final rig = _Rig()..run(110, 40, amplitude: 3.0);
      expect(rig.gait, GaitState.walking, reason: '걷기 판정이 먼저 서야 한다');
      final before = rig.samples.length;
      rig.run(175, 30);
      final idx = rig.samples
          .indexWhere((s) => s.gait == GaitState.running, before);
      expect(idx, isNot(-1), reason: '달리기로 전환되지 않았다');
      // 샘플이 1초 간격이므로 인덱스 차이가 곧 초.
      expect(idx - before, lessThanOrEqualTo(10),
          reason: '전환에 ${idx - before}초 걸림 — M0-a 기준은 10초');
    });

    test('달리기 → 걷기', () {
      final rig = _Rig()..run(175, 40);
      expect(rig.gait, GaitState.running);
      final before = rig.samples.length;
      rig.run(105, 30, amplitude: 3.0);
      final idx = rig.samples
          .indexWhere((s) => s.gait == GaitState.walking, before);
      expect(idx, isNot(-1), reason: '걷기로 전환되지 않았다');
      expect(idx - before, lessThanOrEqualTo(10));
    });

    test('히스테리시스 구간(120~140)에서는 상태가 펄럭이지 않는다', () {
      final rig = _Rig()..run(175, 40);
      expect(rig.gait, GaitState.running);
      // 경계 안쪽으로만 내려간다 — running을 유지해야 한다.
      rig.run(132, 40, amplitude: 4.0);
      expect(rig.gait, GaitState.running,
          reason: '경계 구간에서 상태가 바뀌면 잔향 판정이 펄럭인다');
    });
  });

  group('정직함 — 모르는 것을 아는 척하지 않는다', () {
    test('멈추면 spm이 0으로 떨어진다 (굼뜬 감쇠 금지)', () {
      final rig = _Rig()..run(170, 40);
      expect(rig.settledSpm(), greaterThan(100));
      rig.run(0, 15); // 서 있기 — 노이즈만
      expect(rig.samples.last.spm, 0,
          reason: '멈췄는데 spm이 남아 있으면 잔향 판정이 거짓말을 한다');
    });

    test('시작 직후에는 값을 지어내지 않는다', () {
      final rig = _Rig()..run(170, 3);
      // 3초로는 스텝이 몇 개 없다 — 최종값이 실제보다 크게 나오면 안 된다.
      expect(rig.samples.last.spm, lessThan(170));
    });
  });

  group('안정도 — 음악 레이어 게이트의 입력', () {
    test('일정하게 달리면 안정도가 높다', () {
      final rig = _Rig()..run(170, 90);
      expect(rig.samples.last.stability, greaterThan(0.7));
    });

    test('페이스가 계속 흔들리면 안정도가 낮다', () {
      final rig = _Rig();
      for (var i = 0; i < 6; i++) {
        rig.run(i.isEven ? 150 : 185, 10);
      }
      expect(rig.samples.last.stability, lessThan(0.7));
    });
  });
}
