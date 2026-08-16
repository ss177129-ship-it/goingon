import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

/// 회귀 테스트용 합성 GPS 데이터 생성기.
///
/// 실제 러닝을 기록해 둔 파일이 아직 없어서(감사 #6 — 좌표열을 저장하지 않음)
/// 우선 합성 데이터로 시작한다. 좌표 저장이 들어오면 같은 `List<Position>`
/// 형태로 실측을 읽어 넣으면 되므로 테스트는 그대로 재사용된다.
///
/// 모든 좌표는 서울 시청 근처의 평지를 기준으로 하고, 위도만 움직여
/// 거리 계산을 예측 가능하게 만든다(경도는 위도에 따라 미터/도가 달라짐).

/// 기준점 — 서울시청
const double kBaseLat = 37.5665;
const double kBaseLng = 126.9780;

/// 위도 1도 ≈ 111,320 m. 위도만 움직이면 경도와 달리 위치에 무관하게 일정하다
const double kMetersPerLatDegree = 111320.0;

/// 시작 시각 — 고정값이라 테스트가 매번 같은 결과를 낸다
final DateTime kRunStart = DateTime.utc(2026, 8, 15, 7, 0, 0);

/// 북쪽으로 [meters] 만큼 이동한 위도
double latAfter(double meters) => kBaseLat + meters / kMetersPerLatDegree;

/// 테스트용 [Position] 하나. 필요한 값만 받고 나머지는 기본값으로 채운다
Position fix({
  required double lat,
  required DateTime at,
  double lng = kBaseLng,
  double accuracy = 5,
  double speed = 3,
  double speedAccuracy = 1,
}) {
  return Position(
    latitude: lat,
    longitude: lng,
    timestamp: at,
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: speed,
    speedAccuracy: speedAccuracy,
  );
}

/// 정확도 5m 이하로 일정하게 달리는 러닝.
///
/// 기본값은 5km를 5'00"/km(= 3.333 m/s)로 달린 25분짜리. fix는 [interval]마다
/// 하나씩 들어오고, 실제 앱처럼 아주 작은 지터를 섞는다(결과에 영향을 주지
/// 않을 정도인 ±0.5m).
List<Position> cleanRun5k({
  double totalMeters = 5000,
  double metersPerSecond = 3.3333333,
  Duration interval = const Duration(seconds: 3),
  double accuracy = 5,
  double jitterMeters = 0.5,
}) {
  final rng = math.Random(20260815); // 고정 시드 — 매번 같은 데이터
  final out = <Position>[];
  final step = metersPerSecond * (interval.inMilliseconds / 1000);
  var travelled = 0.0;
  var at = kRunStart;

  // `<=`만 쓰면 마지막 지점이 목표에 살짝 못 미쳐(예: 4999.99m) 마지막 스플릿이
  // 완성되지 않는다. 한 걸음 더 가서 목표를 확실히 넘긴다
  while (travelled <= totalMeters + step) {
    // 지터는 진행 방향과 무관한 흔들림이라, 앞뒤로만 살짝 흔든다
    final jitter = (rng.nextDouble() - 0.5) * 2 * jitterMeters;
    out.add(fix(
      lat: latAfter(travelled + jitter),
      at: at,
      accuracy: accuracy,
      speed: metersPerSecond,
    ));
    travelled += step;
    at = at.add(interval);
  }
  return out;
}

/// 제자리에 서 있는데 GPS만 흔들리는 구간.
///
/// 이게 이 하네스의 핵심 픽스처다. 실제 아이폰은 정지 상태에서도
/// 5~15m 범위로 좌표가 떠다니고, `distanceFilter: 5m` 때문에 **그 흔들림이
/// 5m를 넘을 때만** fix가 배달된다 — 즉 노이즈만 골라 들어온다.
///
/// [driftRadius]는 흔들림의 크기(m), [accuracy]는 그때의 보고 정확도.
/// 둘 다 도심에서 흔한 값으로 잡았다.
List<Position> stationaryJitter(
  Duration duration, {
  double driftRadius = 8,
  double accuracy = 20,
  Duration interval = const Duration(seconds: 3),
}) {
  final rng = math.Random(7);
  final out = <Position>[];
  var at = kRunStart;
  final end = kRunStart.add(duration);

  while (!at.isAfter(end)) {
    // 진짜 위치는 그대로인데 보고되는 좌표만 반경 안에서 떠다님
    final offset = (rng.nextDouble() - 0.5) * 2 * driftRadius;
    out.add(fix(
      lat: latAfter(offset),
      at: at,
      accuracy: accuracy,
      speed: 0,
    ));
    at = at.add(interval);
  }
  return out;
}

/// 중간에 [gap] 동안 fix가 끊기는 러닝 (터널·지하도).
///
/// 끊긴 동안에도 실제로는 계속 달렸으므로, 재개 지점은 그만큼 앞으로 나가 있다.
List<Position> tunnelGap({
  Duration gap = const Duration(seconds: 90),
  double metersPerSecond = 3.3333333,
  Duration interval = const Duration(seconds: 3),
  Duration beforeGap = const Duration(seconds: 60),
  Duration afterGap = const Duration(seconds: 60),
}) {
  final out = <Position>[];
  var travelled = 0.0;
  var at = kRunStart;
  final step = metersPerSecond * (interval.inMilliseconds / 1000);

  void run(Duration span) {
    final end = at.add(span);
    while (at.isBefore(end)) {
      out.add(fix(lat: latAfter(travelled), at: at, speed: metersPerSecond));
      travelled += step;
      at = at.add(interval);
    }
  }

  run(beforeGap);
  // 터널 통과 — fix는 없지만 몸은 계속 나아간다
  travelled += metersPerSecond * (gap.inMilliseconds / 1000);
  at = at.add(gap);
  run(afterGap);
  return out;
}

/// 달리는 도중 정확도가 일시적으로 [burstAccuracy]까지 치솟는 구간.
///
/// 좌표 자체도 그만큼 어긋난다 — 정확도가 나쁘다는 건 위치가 틀렸다는 뜻이므로,
/// 정확도만 올리고 좌표는 정확한 데이터는 현실을 반영하지 못한다.
List<Position> accuracyBurst({
  double metersPerSecond = 3.3333333,
  Duration interval = const Duration(seconds: 3),
  int totalFixes = 40,
  int burstStart = 15,
  int burstLength = 5,
  double burstAccuracy = 100,
}) {
  final rng = math.Random(99);
  final out = <Position>[];
  var travelled = 0.0;
  var at = kRunStart;
  final step = metersPerSecond * (interval.inMilliseconds / 1000);

  for (var i = 0; i < totalFixes; i++) {
    final inBurst = i >= burstStart && i < burstStart + burstLength;
    final error =
        inBurst ? (rng.nextDouble() - 0.5) * 2 * burstAccuracy : 0.0;
    out.add(fix(
      lat: latAfter(travelled + error),
      at: at,
      accuracy: inBurst ? burstAccuracy : 5,
      speed: metersPerSecond,
    ));
    travelled += step;
    at = at.add(interval);
  }
  return out;
}

/// 세션 시작 직후 iOS가 캐시된 옛 위치를 먼저 배달하는 경우.
///
/// 감사 #1이 지목한 시나리오다. 첫 fix는 [staleBy] 전의 것이고 좌표도
/// [staleDistanceMeters]만큼 떨어진 엉뚱한 곳(예: 집)이다. 그 뒤로는 정상적인
/// 러닝 fix가 이어진다.
///
/// 캐시 fix의 정확도는 일부러 좋게 준다 — 오래됐다는 것과 부정확하다는 것은
/// 다른 문제이고, 정확도 필터로는 이걸 못 거른다는 게 요점이기 때문이다.
///
/// 기본값(30초 전 · 200m)은 속도 필터의 사각지대에 정확히 들어간다:
/// 200m / 30s = 6.7 m/s 라 10 m/s 상한을 통과한다. 집 앞에서 앱을 켜고
/// 200m 걸어 나가 러닝을 시작하면 그대로 재현되는 상황이다.
List<Position> staleFirstFix({
  Duration staleBy = const Duration(seconds: 30),
  double staleDistanceMeters = 200,
  double metersPerSecond = 3.3333333,
  Duration interval = const Duration(seconds: 3),
  int followingFixes = 20,
}) {
  final out = <Position>[
    fix(
      lat: latAfter(-staleDistanceMeters),
      at: kRunStart.subtract(staleBy),
      accuracy: 5,
      speed: 0,
    ),
  ];

  var travelled = 0.0;
  var at = kRunStart;
  final step = metersPerSecond * (interval.inMilliseconds / 1000);
  for (var i = 0; i < followingFixes; i++) {
    out.add(fix(lat: latAfter(travelled), at: at, speed: metersPerSecond));
    travelled += step;
    at = at.add(interval);
  }
  return out;
}

/// 한 fix만 비현실적으로 멀리 튀는 경우 (순간속도 [spikeSpeed] m/s).
///
/// 튄 뒤에는 원래 자리로 돌아와 정상적으로 이어진다 — GPS 튐의 실제 모습이다.
List<Position> speedSpike({
  double spikeSpeed = 30,
  double metersPerSecond = 3.3333333,
  Duration interval = const Duration(seconds: 3),
  int totalFixes = 30,
  int spikeAt = 15,
}) {
  final out = <Position>[];
  var travelled = 0.0;
  var at = kRunStart;
  final step = metersPerSecond * (interval.inMilliseconds / 1000);
  final spikeOffset = spikeSpeed * (interval.inMilliseconds / 1000);

  for (var i = 0; i < totalFixes; i++) {
    final isSpike = i == spikeAt;
    out.add(fix(
      lat: latAfter(isSpike ? travelled + spikeOffset : travelled),
      at: at,
      speed: metersPerSecond,
    ));
    travelled += step;
    at = at.add(interval);
  }
  return out;
}

/// 일시정지 중에도 fix가 계속 들어오는 구간.
///
/// [beforePause]만큼 달리고, [pauseSpan] 동안 멈춰 있고(그동안 지터만 들어옴),
/// 다시 [afterPause]만큼 달린다. 어디서 멈추고 재개할지는 인덱스로 알려준다.
PausedRun pausedSegment({
  Duration beforePause = const Duration(seconds: 60),
  Duration pauseSpan = const Duration(seconds: 120),
  Duration afterPause = const Duration(seconds: 60),
  double metersPerSecond = 3.3333333,
  Duration interval = const Duration(seconds: 3),
  double driftRadius = 8,
}) {
  final rng = math.Random(31);
  final out = <Position>[];
  var travelled = 0.0;
  var at = kRunStart;
  final step = metersPerSecond * (interval.inMilliseconds / 1000);

  void run(Duration span) {
    final end = at.add(span);
    while (at.isBefore(end)) {
      out.add(fix(lat: latAfter(travelled), at: at, speed: metersPerSecond));
      travelled += step;
      at = at.add(interval);
    }
  }

  run(beforePause);
  final pauseIndex = out.length;

  // 멈춰 있는 동안에도 GPS는 계속 흔들린 좌표를 보낸다
  final pauseEnd = at.add(pauseSpan);
  final stoppedAt = travelled;
  while (at.isBefore(pauseEnd)) {
    final offset = (rng.nextDouble() - 0.5) * 2 * driftRadius;
    out.add(fix(
      lat: latAfter(stoppedAt + offset),
      at: at,
      accuracy: 20,
      speed: 0,
    ));
    at = at.add(interval);
  }
  final resumeIndex = out.length;

  run(afterPause);

  return PausedRun(
    positions: out,
    pauseIndex: pauseIndex,
    resumeIndex: resumeIndex,
    movingMeters: travelled - (metersPerSecond * 0), // 정지 구간은 이동 없음
  );
}

/// [pausedSegment]의 결과 — 어느 인덱스에서 멈추고 재개해야 하는지 함께 준다
class PausedRun {
  final List<Position> positions;

  /// 이 인덱스부터 일시정지 상태로 넣어야 함
  final int pauseIndex;

  /// 이 인덱스부터 다시 달리는 상태
  final int resumeIndex;

  /// 실제로 이동한 거리(m) — 정지 구간은 포함하지 않음
  final double movingMeters;

  const PausedRun({
    required this.positions,
    required this.pauseIndex,
    required this.resumeIndex,
    required this.movingMeters,
  });
}
