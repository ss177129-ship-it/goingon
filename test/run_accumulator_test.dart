import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:goingon/services/run_accumulator.dart';

import 'fixtures/run_fixtures.dart';

/// GPS 필터·누적 로직의 회귀 테스트. 전부 통과해야 한다.
///
/// `legacy` 설정으로 도는 테스트들은 **추출이 여전히 충실한지** 확인하는
/// 기준선이고, `current`로 도는 테스트들은 감사 수정이 살아 있는지 지킨다.

/// fix가 **배달되는 시각**을 흉내내며 넣어주는 도우미.
///
/// 나이 검사(AUDIT #1)는 "지금"과 fix의 timestamp를 비교하는데, 테스트가
/// 실제 벽시계를 쓰면 **언제 돌리느냐에 따라 결과가 달라진다** — 오후에 돌리면
/// 픽스처의 모든 fix가 오래된 것으로 판정돼 전부 버려진다. 그래서 시계를 주입한다.
///
/// 배달 시각 규칙은 실기기와 같다: 세션은 [kRunStart]에 시작하고, 그 뒤의 fix는
/// 자기 timestamp 시점에 배달된다. **캐시 fix만 timestamp가 세션 시작보다
/// 이른데, 배달은 세션이 시작된 뒤에 되므로 그 차이가 곧 나이가 된다.**
class Replay {
  late final RunAccumulator _acc;
  DateTime _now = kRunStart;

  Replay({RunFilterConfig? config}) {
    _acc = RunAccumulator(
      config: config ?? RunFilterConfig.current,
      now: () => _now,
    );
  }

  RunSample? add(Position p) {
    _now = p.timestamp.isAfter(kRunStart) ? p.timestamp : kRunStart;
    return _acc.add(p);
  }

  void addAll(Iterable<Position> positions) {
    for (final p in positions) {
      add(p);
    }
  }

  double get totalKm => _acc.totalKm;
  RunStats get stats => _acc.stats;
  void pause() => _acc.pause();
  void resume() => _acc.resume();
  void reset() => _acc.reset();
}

void main() {
  // ── 추출 동치성 ────────────────────────────────────────────────────
  //
  // RunAccumulator는 location_service.dart의 start() 안에 인라인으로 있던
  // 로직을 옮긴 것이다. 아래 참조 구현은 **옮기기 전 코드를 그대로 베낀 것**이고,
  // 모든 픽스처에서 두 결과가 같아야 "동작을 바꾸지 않았다"가 증명된다.
  // 필터 로직을 고칠 때 이 테스트는 함께 갱신해야 한다 — 그때는 의도적으로
  // 달라지는 것이므로.
  double referenceTotalKm(List<Position> positions) {
    Position? last;
    var totalKm = 0.0;
    for (final pos in positions) {
      if (pos.accuracy > 30) continue; // 원본의 이른 return
      if (last != null) {
        final meters = Geolocator.distanceBetween(
            last.latitude, last.longitude, pos.latitude, pos.longitude);
        final dtSeconds =
            pos.timestamp.difference(last.timestamp).inMilliseconds / 1000;
        final isOutlier =
            dtSeconds > 0 ? (meters / dtSeconds) > 10 : meters >= 50;
        if (!isOutlier) totalKm += meters / 1000;
      }
      last = pos;
    }
    return totalKm;
  }

  double runAll(List<Position> positions, {RunFilterConfig? config}) {
    final acc = Replay(config: config);
    acc.addAll(positions);
    return acc.totalKm;
  }

  group('추출 동치성 — legacy 설정은 옮기기 전과 결과가 같다', () {
    final fixtures = <String, List<Position>>{
      'cleanRun5k': cleanRun5k(),
      'stationaryJitter(10분)': stationaryJitter(const Duration(minutes: 10)),
      'tunnelGap': tunnelGap(),
      'accuracyBurst': accuracyBurst(),
      'staleFirstFix': staleFirstFix(),
      'speedSpike': speedSpike(),
      'pausedSegment(정지 무시)': pausedSegment().positions,
    };

    fixtures.forEach((name, positions) {
      test(name, () {
        expect(runAll(positions, config: RunFilterConfig.legacy),
            closeTo(referenceTotalKm(positions), 1e-9));
      });
    });
  });

  // ── 현행 동작 ──────────────────────────────────────────────────────

  group('cleanRun5k', () {
    final positions = cleanRun5k();

    test('총거리 오차 1% 이내', () {
      expect(runAll(positions) * 1000, closeTo(5000, 50));
    });

    test('평균 페이스가 5\'00"/km 근처', () {
      final acc = Replay();
      for (final p in positions) {
        acc.add(p);
      }
      // 3.3333 m/s = 300초/km
      expect(acc.stats.averageSecPerKm, closeTo(300, 5));
    });

    test('1km 스플릿이 5개, 각 구간이 300초 근처', () {
      final acc = Replay();
      for (final p in positions) {
        acc.add(p);
      }
      final splits = acc.stats.splits;
      expect(splits.length, 5);
      for (final s in splits) {
        expect(s.secondsPerKm, closeTo(300, 10),
            reason: '${s.index}번째 구간');
      }
    });
  });

  group('speedSpike — 튄 fix는 거리에 반영되지 않는다', () {
    test('30 m/s로 튄 지점이 누적되지 않음', () {
      final positions = speedSpike();
      // 튐이 그대로 더해졌다면 90m가 얹혀 380m 근처가 된다
      expect(runAll(positions) * 1000, lessThan(320));
    });

    test('튄 fix는 accepted가 아니라 rejectedSpeed로 판정된다', () {
      final acc = Replay();
      final positions = speedSpike();
      final verdicts = <RunFixVerdict>[];
      for (final p in positions) {
        final s = acc.add(p);
        if (s != null) verdicts.add(s.verdict);
      }
      expect(verdicts.where((v) => v == RunFixVerdict.rejectedSpeed).length,
          greaterThanOrEqualTo(1));
    });
  });

  group('accuracyBurst — 정확도가 나쁜 구간은 버려진다', () {
    test('100m 정확도 구간이 거리에 반영되지 않음', () {
      final positions = accuracyBurst();
      // 정상 구간만 40개 fix × 10m = 390m 근처. 정확도 필터가 제 몫을 하면
      // 구간을 건너뛰어도 앞뒤가 이어져 총거리는 거의 그대로다
      expect(runAll(positions) * 1000, closeTo(390, 20));
    });

    test('버려진 fix는 콜백까지 도달하지 않는다 (add가 null)', () {
      final acc = Replay();
      var delivered = 0;
      for (final p in accuracyBurst()) {
        if (acc.add(p) != null) delivered++;
      }
      // 버스트 5개는 배달되지 않아야 함
      expect(delivered, 35);
    });
  });

  group('tunnelGap — 현재는 공백을 직선으로 잇는다', () {
    test('90초 공백 구간의 거리가 직선으로 더해짐', () {
      final positions = tunnelGap();
      // 전 구간 60초 + 터널 90초 + 후 구간 60초 = 210초를 3.333 m/s로
      // 달린 700m. 직선 코스라 보간 오차가 없어 거의 정확히 맞는다
      expect(runAll(positions) * 1000, closeTo(700, 25));
    });
  });

  group('pause / resume', () {
    // 이 API는 추출된 것이 아니라 새로 추가된 것이다. 앱은 아직 호출하지
    // 않으므로 앱 동작에는 영향이 없고, 여기서 계약만 못 박아 둔다
    test('일시정지 구간의 거리는 0', () {
      final run = pausedSegment();
      final acc = Replay();
      var pausedDistance = 0.0;

      for (var i = 0; i < run.positions.length; i++) {
        if (i == run.pauseIndex) acc.pause();
        if (i == run.resumeIndex) acc.resume();
        final before = acc.totalKm;
        acc.add(run.positions[i]);
        if (i >= run.pauseIndex && i < run.resumeIndex) {
          pausedDistance += (acc.totalKm - before) * 1000;
        }
      }
      expect(pausedDistance, 0);
    });

    test('재개 직후 첫 fix는 기준점만 잡고 거리를 만들지 않는다', () {
      final run = pausedSegment();
      final acc = Replay();
      for (var i = 0; i < run.resumeIndex; i++) {
        if (i == run.pauseIndex) acc.pause();
        acc.add(run.positions[i]);
      }
      acc.resume();
      final before = acc.totalKm;
      final sample = acc.add(run.positions[run.resumeIndex]);
      expect(sample?.verdict, RunFixVerdict.anchor);
      expect(acc.totalKm, before);
    });

    test('reset하면 처음 상태로 돌아간다', () {
      final acc = Replay();
      for (final p in cleanRun5k()) {
        acc.add(p);
      }
      expect(acc.totalKm, greaterThan(1));
      acc.reset();
      expect(acc.totalKm, 0);
      expect(acc.stats.splits, isEmpty);
    });
  });

  group('페이스 방어', () {
    test('거리가 20m 미만이면 평균 페이스를 내지 않는다', () {
      final acc = Replay();
      acc.add(fix(lat: latAfter(0), at: kRunStart));
      acc.add(fix(
          lat: latAfter(10), at: kRunStart.add(const Duration(seconds: 3))));
      expect(acc.stats.averageSecPerKm, isNull);
    });

    test('fix가 하나뿐이면 스플릿도 페이스도 없다', () {
      final acc = Replay();
      acc.add(fix(lat: latAfter(0), at: kRunStart));
      expect(acc.stats.splits, isEmpty);
      expect(acc.stats.averageSecPerKm, isNull);
      expect(acc.totalKm, 0);
    });
  });

  group('RunFilterConfig', () {
    // CLAUDE.md가 "검증된 값이므로 유저 승인 없이 변경 금지"로 지정한 값들.
    // 감사 수정은 없던 필터를 켠 것이지 이 값을 바꾼 것이 아니므로,
    // legacy와 current가 여기서만큼은 반드시 같아야 한다
    test('보호된 GPS 값은 legacy와 current가 동일하다', () {
      const now = RunFilterConfig.current;
      const before = RunFilterConfig.legacy;
      expect(now.maxHorizontalAccuracy, before.maxHorizontalAccuracy);
      expect(now.maxPlausibleSpeed, before.maxPlausibleSpeed);
      expect(now.outlierDistanceWithoutDt, before.outlierDistanceWithoutDt);
      expect(now.locationDistanceFilter, before.locationDistanceFilter);

      expect(now.maxHorizontalAccuracy, 30);
      expect(now.maxPlausibleSpeed, 10);
      expect(now.outlierDistanceWithoutDt, 50);
      expect(now.locationDistanceFilter, 5);
      expect(now.minPaceDistanceKm, 0.02);
    });

    test('감사 수정으로 켜진 필터가 실제로 켜져 있다', () {
      const c = RunFilterConfig.current;
      expect(c.maxFixAge, isNotNull, reason: 'AUDIT #1');
      expect(c.minHorizontalAccuracy, 0, reason: 'AUDIT #2');
      expect(c.keepAnchorOnRejectedFix, isTrue, reason: 'AUDIT #3');
      expect(c.maxConsecutiveOutliers, greaterThan(0), reason: '교착 탈출구');
      expect(c.minMovementAccuracyFactor, greaterThan(0), reason: 'AUDIT #4');
      expect(c.paceSmoothingWindow, isNotNull, reason: 'AUDIT #9');
    });

    test('legacy는 수정 이전 상태를 그대로 보존한다', () {
      const c = RunFilterConfig.legacy;
      expect(c.maxFixAge, isNull);
      expect(c.minHorizontalAccuracy, double.negativeInfinity);
      expect(c.keepAnchorOnRejectedFix, isFalse);
      expect(c.minMovementAccuracyFactor, 0);
      expect(c.paceSmoothingWindow, isNull);
    });
  });

  // ── 감사 항목 회귀 방지 ─────────────────────────────────────────────
  //
  // 원래 run_accumulator_known_issues_test.dart에 있던 것들. 고쳐졌으므로
  // 여기로 옮겨 영구 회귀 방지선으로 남긴다. 이게 다시 빨개지면 필터가
  // 꺼졌거나 기준점 규칙이 되돌아간 것이다.

  group('AUDIT #1 — 오래된 캐시 fix를 거른다', () {
    test('30초 전 캐시 fix(200m 밖)가 거리에 반영되지 않는다', () {
      // 200m/30s = 6.7 m/s라 속도 필터(10 m/s)로는 절대 못 잡는다.
      // 나이 검사가 있어야만 걸린다
      expect(runAll(staleFirstFix()) * 1000, closeTo(190, 20));
    });

    test('1시간 전 캐시 fix(5km 밖)도 거른다', () {
      final positions = staleFirstFix(
        staleBy: const Duration(hours: 1),
        staleDistanceMeters: 5000,
      );
      expect(runAll(positions) * 1000, lessThan(250));
    });

    test('legacy에서는 여전히 허위 거리가 더해진다 (수정 전 동작 보존)', () {
      final positions = staleFirstFix(
        staleBy: const Duration(hours: 1),
        staleDistanceMeters: 5000,
      );
      expect(runAll(positions, config: RunFilterConfig.legacy) * 1000,
          greaterThan(5000));
    });
  });

  group('AUDIT #2 — 음수 정확도 fix를 거른다', () {
    test('accuracy가 음수면 버려진다', () {
      final acc = Replay();
      acc.add(fix(lat: latAfter(0), at: kRunStart));
      final sample = acc.add(fix(
        lat: latAfter(50),
        at: kRunStart.add(const Duration(seconds: 30)),
        accuracy: -1, // iOS가 "위치를 못 구했다"는 뜻으로 보내는 값
      ));
      expect(sample, isNull);
      expect(acc.totalKm, 0);
    });

    test('accuracy 0은 버리지 않는다', () {
      // 일부 기기·시뮬레이터가 0을 보고한다. 0은 무효가 아니므로 통과해야 함
      final acc = Replay();
      acc.add(fix(lat: latAfter(0), at: kRunStart, accuracy: 0));
      final sample = acc.add(fix(
        lat: latAfter(30),
        at: kRunStart.add(const Duration(seconds: 10)),
        accuracy: 0,
      ));
      expect(sample?.verdict, RunFixVerdict.accepted);
    });
  });

  group('AUDIT #3 — 이상치가 기준점을 오염시키지 않는다', () {
    test('튄 fix가 있어도 실제 달린 거리가 사라지지 않는다', () {
      final withSpike = runAll(speedSpike()) * 1000;
      final clean = runAll(speedSpike(spikeAt: -1)) * 1000;
      expect(withSpike, closeTo(clean, clean * 0.01));
    });

    test('legacy에서는 거리가 손실된다 (수정 전 동작 보존)', () {
      final withSpike =
          runAll(speedSpike(), config: RunFilterConfig.legacy) * 1000;
      final clean =
          runAll(speedSpike(spikeAt: -1), config: RunFilterConfig.legacy) * 1000;
      expect(withSpike, lessThan(clean * 0.98));
    });

    test('연속 이상치가 이어지면 기준점을 강제로 옮겨 교착을 푼다', () {
      // 차를 타는 등 실제로 멀리 이동해 버린 상황. 탈출구가 없으면
      // 이후 모든 fix가 이상치로 걸려 트래킹이 영영 멈춘다
      final acc = Replay();
      acc.add(fix(lat: latAfter(0), at: kRunStart));
      var at = kRunStart;
      // 5km 밖으로 순간이동한 뒤 그 자리에서 정상 러닝
      for (var i = 0; i < 10; i++) {
        at = at.add(const Duration(seconds: 3));
        acc.add(fix(lat: latAfter(5000 + i * 10), at: at));
      }
      // 교착이 풀렸다면 이동분이 다시 잡히기 시작한다
      expect(acc.totalKm * 1000, greaterThan(0));
      expect(acc.totalKm * 1000, lessThan(200), reason: '5km 순간이동 자체는 안 더해져야 함');
    });
  });

  group('AUDIT #4 — 정지 상태 드리프트를 막는다', () {
    test('제자리에 10분 서 있으면 누적 거리가 50m 미만', () {
      expect(runAll(stationaryJitter(const Duration(minutes: 10))) * 1000,
          lessThan(50));
    });

    test('제자리에 1분 서 있으면 거의 0', () {
      expect(runAll(stationaryJitter(const Duration(minutes: 1))) * 1000,
          lessThan(10));
    });

    test('legacy에서는 10분에 1km 가까이 쌓인다 (수정 전 동작 보존)', () {
      expect(
          runAll(stationaryJitter(const Duration(minutes: 10)),
                  config: RunFilterConfig.legacy) *
              1000,
          greaterThan(500));
    });

    test('천천히 걸어도 거리가 사라지지 않는다', () {
      // 기준점을 붙들기만 하고 버리지 않으므로, 걸음이 느려 한 번에
      // 임계값을 못 넘어도 누적되면 반영된다. 이게 안 되면 걷기가 통째로
      // 기록되지 않는 심각한 회귀가 된다
      final walk = cleanRun5k(
        totalMeters: 600,
        metersPerSecond: 1.2, // 느린 걷기
        accuracy: 10, // 도심 수준 정확도
        interval: const Duration(seconds: 4),
      );
      expect(runAll(walk) * 1000, closeTo(600, 60));
    });
  });

  group('AUDIT #9 — 즉시 페이스를 낼 수 있다', () {
    test('누적 평균과 별개로 최근 구간 페이스가 나온다', () {
      final acc = Replay();
      for (final p in cleanRun5k()) {
        acc.add(p);
      }
      expect(acc.stats.instantSecPerKm, isNotNull);
      expect(acc.stats.instantSecPerKm, closeTo(300, 20));
    });

    test('후반에 속도를 올리면 즉시 페이스가 따라온다', () {
      // 앞 2km는 6'00"/km, 이어서 4'00"/km로 가속
      final slow = cleanRun5k(totalMeters: 2000, metersPerSecond: 1000 / 360);
      final acc = Replay();
      for (final p in slow) {
        acc.add(p);
      }
      expect(acc.stats.averageSecPerKm, closeTo(360, 15));

      var at = slow.last.timestamp;
      var travelled = 2000.0;
      for (var i = 0; i < 100; i++) {
        at = at.add(const Duration(seconds: 3));
        travelled += (1000 / 240) * 3;
        acc.add(fix(lat: latAfter(travelled), at: at));
      }
      expect(acc.stats.instantSecPerKm, closeTo(240, 20),
          reason: '즉시 페이스는 최근 구간만 본다');
      expect(acc.stats.averageSecPerKm, greaterThan(260),
          reason: '누적 평균은 앞의 느린 구간에 눌려 천천히 움직인다');
    });
  });
}
