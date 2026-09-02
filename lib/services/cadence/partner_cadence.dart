// 상대의 케이던스가 어디서 오는가 — 라이브와 고스트를 같은 문으로 들여보낸다.
//
// 왜 추상화하는가(P2): v1.0의 '함께'는 고스트런이고, v1.1에서 라이브가
// 합류한다. 두 경우에 ResonanceEngine이 다른 코드를 타면 공명 판정이 둘로
// 갈라지고, 그러면 라이브와 고스트에서 같은 케이던스가 다른 판정을 받는다.
// 판정을 한 곳으로 모으는 것이 이 인터페이스의 목적이다.
//
// 시간축이 둘인 것이 이 인터페이스의 전부다:
//   · 고스트는 **내 세션 경과 시간**을 본다 — 그날의 리듬을 처음부터 재생
//   · 라이브는 **벽시계**를 본다 — 방금 도착한 값이 아직 쓸 만한가
/// 상대 케이던스의 출처. 모르면 null을 돌려준다 —
/// **모르는 것을 아는 척하지 않는다**(옛 값으로 "나란히"라고 말하지 않는다).
abstract class PartnerCadenceSource {
  /// [elapsed]는 내 세션 경과 시간, [now]는 벽시계.
  /// 구현이 둘 중 필요한 것만 본다.
  double? spmAt({required Duration elapsed, required DateTime now});

  /// 이 상대가 더 이상 줄 것이 없는가(고스트의 기록이 끝남).
  /// 라이브는 세션이 끝나기 전까지 항상 false.
  ///
  /// §2-2의 '동반자 퇴장 의례'가 이것을 본다 — "지수의 그날은 여기까지였어요".
  bool isExhausted({required Duration elapsed});
}

/// 라이브 상대 — `live.{uid}` 맵으로 도착하는 케이던스 (v1.1 범위).
///
/// 값이 낡으면 null이 된다. 6초는 3초 스로틀로 쓰는 상대의 값이 한 번
/// 빠져도 견디고 두 번 빠지면 포기하는 길이다.
class LivePartnerCadence implements PartnerCadenceSource {
  LivePartnerCadence({this.staleAfter = const Duration(seconds: 6)});

  /// 이보다 낡은 값은 없는 것으로 친다
  final Duration staleAfter;

  double? _spm;
  DateTime? _at;

  /// 상대의 새 값이 도착했을 때 부른다
  void update({required double? spm, required DateTime at}) {
    _spm = spm;
    _at = at;
  }

  /// 상대가 세션을 떠났을 때
  void clear() {
    _spm = null;
    _at = null;
  }

  @override
  double? spmAt({required Duration elapsed, required DateTime now}) {
    final at = _at;
    if (at == null || _spm == null) return null;
    return now.difference(at) <= staleAfter ? _spm : null;
  }

  @override
  bool isExhausted({required Duration elapsed}) => false;
}

/// 고스트 — 지난 러닝의 케이던스 타임라인 (P4에서 저장·재생을 붙인다).
///
/// **시간축 기반이라 장소가 독립적이다**(§3-2). 지수가 도림천을 뛰었어도
/// 나는 내 동네에서 그날의 리듬과 함께 뛴다. GPS 경로는 재생에 필요 없다.
class GhostCadenceTimeline implements PartnerCadenceSource {
  GhostCadenceTimeline(this.spmPerSecond);

  /// 1초 해상도의 케이던스. 값이 없는 초(정지·결측)는 null.
  final List<double?> spmPerSecond;

  /// 기록 길이
  Duration get duration => Duration(seconds: spmPerSecond.length);

  @override
  double? spmAt({required Duration elapsed, required DateTime now}) {
    final i = elapsed.inSeconds;
    if (i < 0 || i >= spmPerSecond.length) return null;
    return spmPerSecond[i];
  }

  @override
  bool isExhausted({required Duration elapsed}) =>
      elapsed.inSeconds >= spmPerSecond.length;

  /// delta 압축된 정수 배열에서 복원 (P4의 저장 포맷).
  /// 첫 값은 절대값, 이후는 직전 값과의 차. `null`은 결측.
  factory GhostCadenceTimeline.fromDeltas(List<int?> deltas) {
    final out = <double?>[];
    double? prev;
    for (final d in deltas) {
      if (d == null) {
        out.add(null);
        continue;
      }
      final v = prev == null ? d.toDouble() : prev + d;
      out.add(v);
      prev = v;
    }
    return GhostCadenceTimeline(out);
  }

  /// 저장용 delta 압축. 케이던스는 초당 몇 spm씩만 움직여서 차이값이
  /// 대부분 한 자릿수다 — 8분 세션이 480개 작은 정수로 줄어든다.
  List<int?> toDeltas() {
    final out = <int?>[];
    double? prev;
    for (final v in spmPerSecond) {
      if (v == null) {
        out.add(null);
        continue;
      }
      final r = v.roundToDouble();
      out.add(prev == null ? r.toInt() : (r - prev).round());
      prev = r;
    }
    return out;
  }
}

/// 여러 출처 중 지금 값을 주는 쪽을 쓴다 — 고스트와 달리는 중에 상대가
/// 라이브로 합류하는 경우(v1.1). 앞에 놓인 것이 우선.
class FirstAvailableCadence implements PartnerCadenceSource {
  FirstAvailableCadence(this.sources);

  final List<PartnerCadenceSource> sources;

  @override
  double? spmAt({required Duration elapsed, required DateTime now}) {
    for (final s in sources) {
      final v = s.spmAt(elapsed: elapsed, now: now);
      if (v != null) return v;
    }
    return null;
  }

  @override
  bool isExhausted({required Duration elapsed}) =>
      sources.every((s) => s.isExhausted(elapsed: elapsed));
}

/// 내 케이던스의 출처. CadenceEngine(가속도계)과 CMPedometer가 같은 문으로
/// 들어오게 한다 — M0 실측이 끝나기 전까지 어느 쪽이 본선인지 모르기 때문.
abstract class MyCadenceSource {
  double? get spm;
}

/// 고정값 — 테스트·데모용
class StaticCadence implements MyCadenceSource {
  StaticCadence(this.spm);
  @override
  double? spm;
}

/// 정수비 배수 후보를 사람이 읽는 이름으로 (로그·디버그용)
String describeRatio(double mine, double theirs) {
  const named = <(double, String)>[
    (1.0, '1:1'),
    (2.0, '1:2'),
    (0.5, '2:1'),
    (1.5, '2:3'),
    (2 / 3, '3:2'),
  ];
  var best = '1:1';
  var bestGap = double.infinity;
  for (final (r, name) in named) {
    final g = (mine - theirs * r).abs();
    if (g < bestGap) {
      bestGap = g;
      best = name;
    }
  }
  return '$best (Δ${bestGap.toStringAsFixed(1)}spm)';
}
