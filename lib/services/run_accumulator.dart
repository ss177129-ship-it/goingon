import 'package:geolocator/geolocator.dart';

/// GPS fix 필터링 + 거리 누적의 순수 로직.
///
/// `location_service.dart`의 `start()` 안에 스트림 구독과 뒤섞여 있던 계산을
/// 떼어낸 것. 스트림 생명주기는 여전히 LocationService가 갖고, 여기는
/// `Position`을 받아 판정·누적만 한다 — 그래서 앱을 띄우지 않고 테스트할 수 있다.
///
/// **이 클래스는 추출 시점의 동작을 한 치도 바꾸지 않는다.** 감사에서 발견된
/// 버그도 그대로 옮겨져 있고, 각각 `// AUDIT: #N` 으로 표시해 뒀다. 고치는 것은
/// 다음 단계이며, 대부분 [RunFilterConfig] 값만 바꾸면 되도록 배선해 두었다.

/// 필터·누적 파라미터를 한곳에 모은 설정.
///
/// 아직 구현되지 않은 필터도 **비활성 기본값**으로 미리 자리를 잡아 두었다
/// (`maxFixAge: null`, `minMovementThreshold: 0` 등). 그래서 [current]를 쓰는 한
/// 지금 앱의 계산 결과와 완전히 같고, 나중에 값만 바꾸면 필터가 켜진다.
class RunFilterConfig {
  /// 이 값을 넘는 수평 정확도(m)의 fix는 버린다.
  /// CLAUDE.md에 실내 드리프트 대응으로 검증된 값이라 명시돼 있음 — 임의 변경 금지.
  final double maxHorizontalAccuracy;

  /// 이 값보다 **작은** 정확도의 fix를 버린다.
  ///
  /// iOS는 위치를 못 구했을 때 `horizontalAccuracy`에 음수를 넣어 보낸다.
  /// 현재 기본값은 음의 무한대라 **아무것도 걸러내지 않는다** — 현재 동작 그대로.
  /// `0`으로 올리면 무효 fix가 걸러진다.
  // AUDIT: #2 — 음수 정확도가 필터를 통과함
  final double minHorizontalAccuracy;

  /// 두 fix 사이 속도가 이 값(m/s)을 넘으면 순간이동으로 보고 거리에 더하지 않는다.
  /// 10 m/s ≈ 36 km/h — 일반적인 러닝 최고 속도를 넉넉히 웃도는 값.
  final double maxPlausibleSpeed;

  /// 시간 간격을 믿을 수 없을 때(dt ≤ 0) 쓰는 대체 기준. 절대 거리(m).
  final double outlierDistanceWithoutDt;

  /// 이 거리(m) 미만의 이동은 누적하지 않는다 — 절대 하한.
  ///
  /// 단독으로는 쓰기 위험하다. `distanceFilter: 5m` 때문에 걷는 사람의 fix는
  /// 5m 간격으로 들어오는데, 여기에 8m 같은 값을 박으면 **걷기가 통째로
  /// 기록되지 않는다.** 그래서 실질적인 판정은 아래
  /// [minMovementAccuracyFactor]가 맡고 이 값은 0으로 둔다.
  final double minMovementThreshold;

  /// 이동 거리가 `정확도 × 이 계수`보다 작으면 누적하지 않는다.
  ///
  /// 정지 상태 드리프트의 본질은 "실제로 움직인 거리보다 위치 오차가 크다"는
  /// 것이므로, 고정된 미터가 아니라 **그때의 정확도에 비례한 기준**으로 잘라야
  /// 한다. 정확도 20m로 서 있으면 20m 미만의 흔들림은 무시되고, 정확도 5m로
  /// 달리면 5m만 넘으면 인정된다.
  ///
  /// 걸러진 fix는 기준점도 갱신하지 않으므로(아래 [keepAnchorOnRejectedFix])
  /// 천천히 걷는 사람의 거리는 **사라지지 않고 뭉쳐서 반영된다** — 기준점에서
  /// 충분히 멀어진 순간 그동안의 이동이 한 번에 더해진다.
  // AUDIT: #4
  final double minMovementAccuracyFactor;

  /// fix의 `timestamp`가 이보다 오래됐으면 버린다.
  ///
  /// 현재 기본값 `null`은 **비활성**. iOS가 스트림 첫 fix로 캐시된 옛 위치를
  /// 주면 dt가 커져 속도 필터가 무력화되고 허위 거리가 더해진다.
  // AUDIT: #1 — 오래된 캐시 fix를 거르지 않음
  final Duration? maxFixAge;

  /// 버려진 fix를 다음 계산의 기준점으로 **쓰지 않을지** 여부.
  ///
  /// `false`면 버린 fix도 기준점이 된다 — 튄 좌표가 기준점을 오염시켜 다음
  /// 정상 fix까지 이상치로 걸리고, 결과적으로 실제 달린 거리가 누락된다.
  ///
  /// `true`면 기준점을 붙들고 있다가 신뢰할 만한 fix가 올 때 그 사이 거리를
  /// 한 번에 반영한다. [minMovementAccuracyFactor]가 제 몫을 하려면 이것이
  /// 반드시 켜져 있어야 한다 — 그래야 걸러진 이동이 사라지지 않고 누적된다.
  // AUDIT: #3
  final bool keepAnchorOnRejectedFix;

  /// [keepAnchorOnRejectedFix]가 켜져 있을 때, 이만큼 연속으로 이상치가 나오면
  /// 기준점을 강제로 옮긴다(거리는 더하지 않음).
  ///
  /// 기준점을 무조건 붙들면 **교착**이 생긴다 — 차를 타는 등 실제로 크게
  /// 이동해 버리면 이후 모든 fix가 이상치로 걸려 트래킹이 영영 멈춘다.
  /// 탈출구를 둬서 그 상황에서 회복하게 한다.
  final int maxConsecutiveOutliers;

  /// 즉시 페이스를 낼 때 되돌아볼 시간 창.
  ///
  /// 현재 기본값 `null`은 **비활성** — 지금 앱에는 즉시 페이스가 없고
  /// 누적 평균만 보여준다.
  // AUDIT: #9 — 즉시 페이스 부재
  final Duration? paceSmoothingWindow;

  /// 이 거리(km) 미만에서는 페이스를 계산하지 않는다.
  /// GPS 오차가 상대적으로 커서 숫자가 의미 없기 때문.
  final double minPaceDistanceKm;

  /// 스플릿 한 구간의 거리(km).
  final double splitDistanceKm;

  /// 참고용 — `AppleSettings.distanceFilter`에 넘기는 값(m).
  /// 누적 로직이 직접 쓰지는 않지만, 표본이 얼마나 솎여 들어오는지를 결정하므로
  /// 스무딩 창 크기를 정할 때 함께 봐야 한다.
  final double locationDistanceFilter;

  const RunFilterConfig({
    required this.maxHorizontalAccuracy,
    required this.minHorizontalAccuracy,
    required this.maxPlausibleSpeed,
    required this.outlierDistanceWithoutDt,
    required this.minMovementThreshold,
    required this.minMovementAccuracyFactor,
    required this.maxFixAge,
    required this.keepAnchorOnRejectedFix,
    required this.maxConsecutiveOutliers,
    required this.paceSmoothingWindow,
    required this.minPaceDistanceKm,
    required this.splitDistanceKm,
    required this.locationDistanceFilter,
  });

  /// **앱이 실제로 쓰는 설정.**
  ///
  /// CLAUDE.md가 "검증된 값이므로 유저 승인 없이 변경 금지"로 지정한 네 값
  /// (정확도 30m, 속도 10m/s, dt 없을 때 50m, distanceFilter 5m)은
  /// [legacy]와 **완전히 동일하다.** 감사 수정은 그 값들을 건드린 것이 아니라
  /// 없던 필터를 새로 켠 것이다.
  static const current = RunFilterConfig(
    // ── 보호된 값 (legacy와 동일) ──
    maxHorizontalAccuracy: 30,
    maxPlausibleSpeed: 10,
    outlierDistanceWithoutDt: 50,
    locationDistanceFilter: 5,
    minPaceDistanceKm: 0.02,
    splitDistanceKm: 1,
    // ── 감사 수정으로 새로 켠 필터 ──
    minHorizontalAccuracy: 0, // AUDIT #2 — 음수(무효) fix 거부
    maxFixAge: Duration(seconds: 10), // AUDIT #1 — 캐시 fix 거부
    keepAnchorOnRejectedFix: true, // AUDIT #3 — 기준점 오염 방지
    maxConsecutiveOutliers: 3, //         교착 탈출구
    minMovementThreshold: 0, // AUDIT #4 — 절대 하한은 쓰지 않음
    minMovementAccuracyFactor: 1, //         정확도 비례로 판정
    paceSmoothingWindow: Duration(seconds: 30), // AUDIT #9 — 즉시 페이스
  );

  /// **감사 수정 이전의 동작.** 새 필터가 전부 비활성이라, 이 설정으로 돌리면
  /// `location_service.dart`에 인라인으로 있던 옛 계산과 결과가 같다.
  ///
  /// 앱은 쓰지 않는다. 추출이 여전히 충실한지 확인하는 회귀 테스트의 기준선으로만
  /// 남겨둔 것이므로 지우지 말 것 — 이게 있어야 "무엇이 어떻게 달라졌는지"를
  /// 언제든 되짚을 수 있다.
  static const legacy = RunFilterConfig(
    maxHorizontalAccuracy: 30,
    minHorizontalAccuracy: double.negativeInfinity, // 비활성 — AUDIT #2
    maxPlausibleSpeed: 10,
    outlierDistanceWithoutDt: 50,
    minMovementThreshold: 0, // 비활성 — AUDIT #4
    minMovementAccuracyFactor: 0, // 비활성 — AUDIT #4
    maxFixAge: null, // 비활성 — AUDIT #1
    keepAnchorOnRejectedFix: false, // 옛 동작 — AUDIT #3
    maxConsecutiveOutliers: 0,
    paceSmoothingWindow: null, // 비활성 — AUDIT #9
    minPaceDistanceKm: 0.02,
    splitDistanceKm: 1,
    locationDistanceFilter: 5,
  );

  RunFilterConfig copyWith({
    double? maxHorizontalAccuracy,
    double? minHorizontalAccuracy,
    double? maxPlausibleSpeed,
    double? outlierDistanceWithoutDt,
    double? minMovementThreshold,
    double? minMovementAccuracyFactor,
    Duration? maxFixAge,
    bool? keepAnchorOnRejectedFix,
    int? maxConsecutiveOutliers,
    Duration? paceSmoothingWindow,
    double? minPaceDistanceKm,
    double? splitDistanceKm,
    double? locationDistanceFilter,
  }) {
    return RunFilterConfig(
      maxHorizontalAccuracy:
          maxHorizontalAccuracy ?? this.maxHorizontalAccuracy,
      minHorizontalAccuracy:
          minHorizontalAccuracy ?? this.minHorizontalAccuracy,
      maxPlausibleSpeed: maxPlausibleSpeed ?? this.maxPlausibleSpeed,
      outlierDistanceWithoutDt:
          outlierDistanceWithoutDt ?? this.outlierDistanceWithoutDt,
      minMovementThreshold: minMovementThreshold ?? this.minMovementThreshold,
      minMovementAccuracyFactor:
          minMovementAccuracyFactor ?? this.minMovementAccuracyFactor,
      maxFixAge: maxFixAge ?? this.maxFixAge,
      keepAnchorOnRejectedFix:
          keepAnchorOnRejectedFix ?? this.keepAnchorOnRejectedFix,
      maxConsecutiveOutliers:
          maxConsecutiveOutliers ?? this.maxConsecutiveOutliers,
      paceSmoothingWindow: paceSmoothingWindow ?? this.paceSmoothingWindow,
      minPaceDistanceKm: minPaceDistanceKm ?? this.minPaceDistanceKm,
      splitDistanceKm: splitDistanceKm ?? this.splitDistanceKm,
      locationDistanceFilter:
          locationDistanceFilter ?? this.locationDistanceFilter,
    );
  }
}

/// fix가 왜 버려졌는지 — 테스트가 "안 더해졌다"를 넘어 "왜"까지 볼 수 있게
enum RunFixVerdict {
  /// 거리에 더해짐
  accepted,

  /// 첫 fix — 기준점만 잡고 거리는 없음
  anchor,

  /// 정확도가 허용 범위 밖
  rejectedAccuracy,

  /// fix가 너무 오래됨
  rejectedStale,

  /// 두 지점 사이 속도가 비현실적
  rejectedSpeed,

  /// 이동 거리가 최소 임계값 미만
  rejectedTooSmall,

  /// 일시정지 중
  rejectedPaused,
}

/// 받아들여진 fix 하나에 대한 결과
class RunSample {
  final Position position;
  final RunFixVerdict verdict;

  /// 이 fix로 더해진 거리(m). 기준점·이상치면 0
  final double addedMeters;

  /// 이 fix 시점의 누적 거리(km)
  final double cumulativeKm;

  const RunSample({
    required this.position,
    required this.verdict,
    required this.addedMeters,
    required this.cumulativeKm,
  });
}

/// 1 km 구간 기록
class RunSplit {
  /// 몇 번째 구간인지 (1부터)
  final int index;

  /// 이 구간에 걸린 시간
  final Duration duration;

  const RunSplit({required this.index, required this.duration});

  double get secondsPerKm => duration.inMilliseconds / 1000;
}

/// 어느 시점의 누적 상태
class RunStats {
  final double totalKm;
  final Duration elapsed;

  /// 누적 평균 페이스(초/km). 거리가 너무 짧으면 null
  final double? averageSecPerKm;

  /// 최근 구간 페이스(초/km). [RunFilterConfig.paceSmoothingWindow]가
  /// 없으면 항상 null — 지금 앱이 그렇다
  final double? instantSecPerKm;

  final List<RunSplit> splits;

  const RunStats({
    required this.totalKm,
    required this.elapsed,
    required this.averageSecPerKm,
    required this.instantSecPerKm,
    required this.splits,
  });
}

/// 누적 거리와 그때의 시각 — 스플릿·즉시 페이스 계산용
class _Mark {
  final double meters;
  final DateTime at;
  const _Mark(this.meters, this.at);
}

/// GPS fix를 받아 걸러내고 거리를 누적한다.
///
/// 스트림·권한·백그라운드는 전혀 모른다. `Position`만 넣으면 되므로
/// 합성 데이터로 전체 시나리오를 재생할 수 있다.
class RunAccumulator {
  final RunFilterConfig config;

  /// 경과 시간 기준점. 넘기지 않으면 첫 fix의 시각이 기준이 된다
  DateTime? _startedAt;

  /// [RunFilterConfig.maxFixAge] 판정에 쓰는 "지금". 테스트에서 주입 가능
  final DateTime Function() _now;

  Position? _anchor;
  double _totalMeters = 0;
  DateTime? _lastAcceptedAt;

  /// 기준점 교착을 풀기 위한 카운터 — [RunFilterConfig.maxConsecutiveOutliers] 참고
  int _consecutiveOutliers = 0;

  bool _paused = false;
  Duration _pausedTotal = Duration.zero;
  DateTime? _pausedAt;

  final List<_Mark> _marks = [];

  RunAccumulator({
    this.config = RunFilterConfig.current,
    DateTime? startedAt,
    DateTime Function()? now,
  })  : _startedAt = startedAt,
        _now = now ?? DateTime.now;

  double get totalKm => _totalMeters / 1000;
  bool get isPaused => _paused;

  /// fix 하나를 넣는다.
  ///
  /// 반환값이 null이면 **호출부가 아무것도 하지 않아야 하는** fix다
  /// (추출 이전 코드에서 `return`으로 빠져나가던 경우와 정확히 일치).
  /// 이상치로 거리에 반영되지 않은 fix는 null이 아니라 `addedMeters: 0`인
  /// 샘플로 돌아온다 — 예전 코드도 이 경우엔 콜백을 호출했기 때문이다.
  RunSample? add(Position position) {
    if (_paused) return null;

    // ── 필터 1: 정확도 ──
    // 추출 이전 조건은 `pos.accuracy > 30` 하나뿐이었다. 아래 하한 검사는
    // 기본값이 음의 무한대라 현재 설정에서는 절대 참이 되지 않는다
    // (= 음수 정확도가 그대로 통과한다).
    // AUDIT: #2
    if (position.accuracy > config.maxHorizontalAccuracy ||
        position.accuracy < config.minHorizontalAccuracy) {
      return null;
    }

    // ── 필터 2: fix 신선도 ──
    // maxFixAge가 null이면 검사하지 않는다 = 현재 동작.
    // AUDIT: #1
    final maxAge = config.maxFixAge;
    if (maxAge != null && _now().difference(position.timestamp) > maxAge) {
      return null;
    }

    _startedAt ??= position.timestamp;

    final anchor = _anchor;
    if (anchor == null) {
      _anchor = position;
      _marks.add(_Mark(0, position.timestamp));
      _lastAcceptedAt = position.timestamp;
      return RunSample(
        position: position,
        verdict: RunFixVerdict.anchor,
        addedMeters: 0,
        cumulativeKm: totalKm,
      );
    }

    final meters = Geolocator.distanceBetween(
      anchor.latitude,
      anchor.longitude,
      position.latitude,
      position.longitude,
    );
    final dtSeconds =
        position.timestamp.difference(anchor.timestamp).inMilliseconds / 1000;

    // ── 필터 3: 순간이동 ──
    // 시간 간격을 믿을 수 있으면 속도로, 아니면 절대 거리로 판정.
    // 추출 이전과 동일한 식이다.
    final isOutlier = dtSeconds > 0
        ? (meters / dtSeconds) > config.maxPlausibleSpeed
        : meters >= config.outlierDistanceWithoutDt;

    // ── 필터 4: 유의미한 이동인가 ──
    // 위치 오차보다 작은 이동은 "움직였다"고 볼 수 없다. 고정된 미터가 아니라
    // 그때의 정확도에 비례해 자른다 — 정확도 20m로 서 있으면 20m 미만의
    // 흔들림은 무시되고, 정확도 5m로 달리면 5m만 넘으면 인정된다.
    // AUDIT: #4
    final significant = _significanceThreshold(position);
    final isTooSmall = meters < significant;

    var added = 0.0;
    RunFixVerdict verdict;
    if (isOutlier) {
      _consecutiveOutliers++;
      verdict = RunFixVerdict.rejectedSpeed;
    } else if (isTooSmall) {
      verdict = RunFixVerdict.rejectedTooSmall;
    } else {
      added = meters;
      _totalMeters += meters;
      _marks.add(_Mark(_totalMeters, position.timestamp));
      _lastAcceptedAt = position.timestamp;
      _consecutiveOutliers = 0;
      verdict = RunFixVerdict.accepted;
    }

    // ── 기준점 갱신 ──
    // 버려진 fix를 기준점으로 삼으면 (1) 튄 좌표가 다음 계산을 오염시키고,
    // (2) 지터가 조금씩 기준점을 밀어내 정지 상태에서도 거리가 쌓인다.
    // 붙들고 있으면 걸러진 이동도 사라지지 않고 다음 유의미한 fix에서
    // 한 번에 반영된다.
    // AUDIT: #3, #4
    //
    // 다만 무조건 붙들면 교착이 생긴다 — 차를 타는 등 실제로 크게 이동해
    // 버리면 이후 모든 fix가 이상치로 걸려 트래킹이 영영 멈춘다. 연속 이상치가
    // 임계치를 넘으면 거리는 더하지 않은 채 기준점만 옮겨 회복한다.
    final stuck = config.maxConsecutiveOutliers > 0 &&
        _consecutiveOutliers >= config.maxConsecutiveOutliers;
    if (verdict == RunFixVerdict.accepted ||
        !config.keepAnchorOnRejectedFix ||
        stuck) {
      _anchor = position;
      if (stuck) _consecutiveOutliers = 0;
    }

    return RunSample(
      position: position,
      verdict: verdict,
      addedMeters: added,
      cumulativeKm: totalKm,
    );
  }

  /// 이 fix를 "실제로 움직인 것"으로 인정하기 위해 필요한 최소 이동 거리(m).
  ///
  /// 정확도 비례 기준과 절대 하한 중 **큰 쪽**을 쓴다. 정확도가 비정상적으로
  /// 작게(0에 가깝게) 보고되는 기기·시뮬레이터에서도 최소한의 방어가 남도록.
  double _significanceThreshold(Position position) {
    final byAccuracy = position.accuracy * config.minMovementAccuracyFactor;
    return byAccuracy > config.minMovementThreshold
        ? byAccuracy
        : config.minMovementThreshold;
  }

  /// 일시정지. 재개 전까지 들어오는 fix는 전부 무시된다.
  ///
  /// **주의: 이 기능은 추출된 것이 아니라 새로 추가된 것이다.** 지금 앱에는
  /// 일시정지가 없고 호출하는 곳도 없으므로 앱 동작은 달라지지 않는다.
  void pause() {
    if (_paused) return;
    _paused = true;
    _pausedAt = _lastAcceptedAt ?? _startedAt ?? _now();
  }

  /// 재개. 멈춰 있는 동안 이동했을 수 있으므로 기준점을 버린다 —
  /// 그래야 재개 후 첫 fix까지의 거리가 러닝에 섞이지 않는다.
  void resume() {
    if (!_paused) return;
    _paused = false;
    final pausedAt = _pausedAt;
    if (pausedAt != null) {
      final until = _lastAcceptedAt ?? _now();
      final gap = until.difference(pausedAt);
      if (gap > Duration.zero) _pausedTotal += gap;
    }
    _pausedAt = null;
    _anchor = null;
    _consecutiveOutliers = 0;
  }

  void reset() {
    _anchor = null;
    _totalMeters = 0;
    _startedAt = null;
    _lastAcceptedAt = null;
    _paused = false;
    _pausedTotal = Duration.zero;
    _pausedAt = null;
    _consecutiveOutliers = 0;
    _marks.clear();
  }

  /// 일시정지 중에 들어온 fix도 시간에 반영되도록, 정지 구간을 뺀 경과 시간
  Duration get elapsed {
    final start = _startedAt;
    final last = _lastAcceptedAt;
    if (start == null || last == null) return Duration.zero;
    var total = last.difference(start) - _pausedTotal;
    if (_paused && _pausedAt != null) {
      total -= last.difference(_pausedAt!);
    }
    return total.isNegative ? Duration.zero : total;
  }

  RunStats get stats {
    final km = totalKm;
    final seconds = elapsed.inMilliseconds / 1000;
    return RunStats(
      totalKm: km,
      elapsed: elapsed,
      averageSecPerKm:
          (km < config.minPaceDistanceKm || seconds <= 0) ? null : seconds / km,
      instantSecPerKm: _instantSecPerKm(),
      splits: _splits(),
    );
  }

  /// 최근 [RunFilterConfig.paceSmoothingWindow] 구간의 페이스.
  /// 창이 설정되지 않았으면 null — 지금 앱이 그렇다.
  double? _instantSecPerKm() {
    final window = config.paceSmoothingWindow;
    if (window == null || _marks.length < 2) return null;
    final last = _marks.last;
    final cutoff = last.at.subtract(window);
    _Mark? from;
    for (final m in _marks) {
      if (!m.at.isBefore(cutoff)) {
        from = m;
        break;
      }
    }
    from ??= _marks.first;
    final meters = last.meters - from.meters;
    final seconds = last.at.difference(from.at).inMilliseconds / 1000;
    if (meters <= 0 || seconds <= 0) return null;
    return seconds / (meters / 1000);
  }

  /// 1 km 스플릿. 경계가 두 fix 사이에 걸리면 **선형 보간**으로 통과 시각을 구한다.
  ///
  /// **주의: 스플릿은 추출된 것이 아니라 새로 추가된 것이다.** 지금 앱에는
  /// 스플릿 기능이 없으므로 비교 대상이 없고, 이 계산의 정확성은 아래 테스트가
  /// 직접 검증한다.
  List<RunSplit> _splits() {
    if (_marks.length < 2) return const [];
    final boundary = config.splitDistanceKm * 1000;
    final splits = <RunSplit>[];
    var previousCrossing = _marks.first.at;
    var index = 1;

    while (index * boundary <= _totalMeters + 1e-9) {
      final target = index * boundary;
      DateTime? crossing;
      for (var i = 1; i < _marks.length; i++) {
        final a = _marks[i - 1], b = _marks[i];
        if (b.meters >= target && a.meters < target) {
          final span = b.meters - a.meters;
          final ratio = span <= 0 ? 0.0 : (target - a.meters) / span;
          final micros = b.at.difference(a.at).inMicroseconds;
          crossing = a.at.add(Duration(microseconds: (micros * ratio).round()));
          break;
        }
      }
      if (crossing == null) break;
      splits.add(RunSplit(
        index: index,
        duration: crossing.difference(previousCrossing),
      ));
      previousCrossing = crossing;
      index++;
    }
    return splits;
  }
}
