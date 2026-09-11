import 'resonance.dart';

/// 러닝 중 서로에게 보내는 실시간 상태 한 조각.
///
/// 세션 문서의 `live.{uid}` 에 들어간다. 제스처(`gesture` 필드)와 **분리**돼
/// 있는 이유: 제스처는 순간 이벤트고 이건 계속 갱신되는 상태라, 한 필드에
/// 섞으면 신호가 위치 갱신에 묻혀 사라진다.
class LiveState {
  const LiveState({
    required this.paceSecPerKm,
    this.instantPaceSecPerKm,
    required this.cadenceSpm,
    required this.km,
    required this.at,
  });

  /// 누적 평균 페이스(km당 초). 아직 계산할 거리가 없으면 null
  final int? paceSecPerKm;

  /// **최근 30초 구간의 페이스(km당 초).**
  ///
  /// 화면의 큰 숫자는 이 값을 쓴다. 누적 평균은 시간이 갈수록 둔해져서,
  /// 상대가 지금 스퍼트를 해도 내 화면이 거의 안 움직인다 — 그러면 그 숫자는
  /// "상대가 지금 어떤지"가 아니라 "상대가 오늘 어땠는지"가 된다.
  ///
  /// 구버전 앱은 이 필드를 보내지 않으므로 null일 수 있다. 받는 쪽은
  /// `instantPaceSecPerKm ?? paceSecPerKm` 로 떨어진다
  final int? instantPaceSecPerKm;

  /// 분당 발걸음. 만보기가 없거나 권한이 없으면 null
  final double? cadenceSpm;

  final double km;
  final DateTime at;

  Map<String, dynamic> toMap() => {
        if (paceSecPerKm != null) 'paceSecPerKm': paceSecPerKm,
        if (instantPaceSecPerKm != null)
          'instantPaceSecPerKm': instantPaceSecPerKm,
        if (cadenceSpm != null) 'cadenceSpm': cadenceSpm,
        'km': km,
        'at': at.millisecondsSinceEpoch,
      };

  static LiveState? fromMap(Map<String, dynamic>? m) {
    if (m == null) return null;
    final at = (m['at'] as num?)?.toInt();
    if (at == null) return null;
    return LiveState(
      paceSecPerKm: (m['paceSecPerKm'] as num?)?.toInt(),
      instantPaceSecPerKm: (m['instantPaceSecPerKm'] as num?)?.toInt(),
      cadenceSpm: (m['cadenceSpm'] as num?)?.toDouble(),
      km: (m['km'] as num?)?.toDouble() ?? 0,
      at: DateTime.fromMillisecondsSinceEpoch(at),
    );
  }

  /// 화면에 쓸 상대 페이스 — 지금 값이 있으면 그것, 없으면 평균으로 떨어진다
  int? get displayPaceSecPerKm => instantPaceSecPerKm ?? paceSecPerKm;
}

/// 언제 쓰고 언제 건너뛸지를 정하는 곳.
///
/// **왜 아껴 쓰는가:** 30분 러닝에 1초마다 쓰면 인당 1800회다. 두 사람이면
/// 3600회 쓰기 + 상대의 모든 갱신을 실시간으로 받는 읽기까지 붙는다.
/// 화면이 1초에 한 번 바뀔 이유도 없다 — 공명 판정은 이미 1초 시정수로
/// 스무딩되므로 3초 간격이면 충분히 부드럽다.
///
/// 시간과 변화량 **둘 다** 본다. 시간만 보면 신호등에 서 있는 동안에도
/// 계속 쓰고, 변화량만 보면 페이스가 흔들릴 때 초당 여러 번 쓴다.
class LiveWriteGate {
  LiveWriteGate({
    this.interval = const Duration(seconds: 3),
    this.cadenceEpsilon = 2.0,
    this.kmEpsilon = 0.01,
    this.paceEpsilon = 8.0,
    this.heartbeat = const Duration(seconds: 10),
  });

  /// 아무리 많이 변해도 이 간격보다 자주 쓰지 않는다
  final Duration interval;

  /// 이만큼도 안 바뀌었으면 쓸 이유가 없다 (spm)
  final double cadenceEpsilon;

  /// 10m. 이보다 적게 움직였으면 상대 화면에서 달라 보이지 않는다
  final double kmEpsilon;

  /// km당 8초. 보폭만 늘려 빨라지는 경우는 케이던스가 거의 안 변해서
  /// 여기서 잡지 않으면 상대 화면에 끝내 도착하지 않는다
  final double paceEpsilon;

  /// **변화가 없어도 이 간격마다 한 번은 쓴다.**
  ///
  /// 없으면 신호등에 서 있는 동안 거리도 케이던스도 안 변해서 쓰기가 통째로
  /// 멎고, 상대 화면은 몇 초 뒤 "신호 약함"으로 떨어진다. 바로 옆에서
  /// 멀쩡히 연결돼 있는데 화면이 네트워크를 의심하는 셈이다.
  /// 살아 있다는 말 자체가 소식이라 그때도 보내야 한다
  final Duration heartbeat;

  LiveState? _lastWritten;

  /// 지금 써야 하는가. true면 **쓴 것으로 기록**하므로 실제로 쓸 때만 부를 것
  bool shouldWrite(LiveState next) {
    final last = _lastWritten;
    if (last == null) {
      _lastWritten = next;
      return true; // 첫 값은 무조건 — 상대가 나를 볼 수 있어야 시작된다
    }
    final since = next.at.difference(last.at);
    if (since < interval) return false;
    // 하트비트를 넘겼으면 변화량은 묻지 않는다
    if (since < heartbeat && !_changedEnough(last, next)) return false;
    _lastWritten = next;
    return true;
  }

  bool _changedEnough(LiveState a, LiveState b) {
    if ((a.km - b.km).abs() >= kmEpsilon) return true;
    final pa = a.instantPaceSecPerKm, pb = b.instantPaceSecPerKm;
    if (pa != null && pb != null && (pa - pb).abs() >= paceEpsilon) return true;
    if ((pa == null) != (pb == null)) return true; // 생겼거나 사라진 것도 소식이다
    final ca = a.cadenceSpm, cb = b.cadenceSpm;
    if (ca == null && cb == null) return false;
    if (ca == null || cb == null) return true;
    return (ca - cb).abs() >= cadenceEpsilon;
  }
}

/// 케이던스 차이를 0~1의 발맞춤 값으로 바꾼다.
///
/// **왜 케이던스인가:** 속도가 같아도 보폭이 다르면 발이 안 맞는다. 이 앱이
/// 파는 것은 "같은 속도"가 아니라 "같은 리듬"이라 발구름을 기준으로 삼는다.
///
/// 30spm에서 0이 되는 근거: 조깅이 대략 160~180spm이고, 30 차이는 한쪽이
/// 걷고 다른 쪽이 뛰는 정도다. 그보다 벌어지면 "가까워지는 중"이라고
/// 말할 것이 없다. 사이는 선형 — 곡선을 넣을 만큼 이 값을 잘 알지 못한다.
class CadenceCloseness {
  const CadenceCloseness._();

  /// 이 차이 이상이면 발맞춤 0 — 값의 주인은 [CadenceMatch]다
  static const maxGapSpm = CadenceMatch.maxGapSpm;

  /// 상대 값이 이보다 낡으면 **아예 계산하지 않는다.**
  /// 옛 값으로 "나란히 달리는 중"이라고 말하면 그건 거짓말이다
  static const staleAfter = Duration(seconds: 6);

  /// 둘의 케이던스로 0~1. 어느 한쪽이라도 없으면 null(= 모름).
  ///
  /// 계산은 [CadenceMatch]가 한다 — 2026-08-22 P2에서 발맞춤 판정이
  /// resonance.dart로 옮겨갔다. 여기에 같은 식을 한 벌 더 두면 정수비
  /// 폴리리듬 같은 규칙이 한쪽에만 생겨 두 코드가 조용히 갈라진다.
  static double? of(double? mine, double? theirs) =>
      CadenceMatch.closeness(mine, theirs);

  /// [at] 시점의 상대 데이터를 [now]에 써도 되는가
  static bool isFresh(DateTime at, DateTime now) =>
      now.difference(at) <= staleAfter;
}
