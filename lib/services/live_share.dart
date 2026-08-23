import 'resonance.dart';

/// 러닝 중 서로에게 보내는 실시간 상태 한 조각.
///
/// 세션 문서의 `live.{uid}` 에 들어간다. 제스처(`gesture` 필드)와 **분리**돼
/// 있는 이유: 제스처는 순간 이벤트고 이건 계속 갱신되는 상태라, 한 필드에
/// 섞으면 신호가 위치 갱신에 묻혀 사라진다.
class LiveState {
  const LiveState({
    required this.paceSecPerKm,
    required this.cadenceSpm,
    required this.km,
    required this.at,
  });

  /// km당 초. 아직 계산할 거리가 없으면 null
  final int? paceSecPerKm;

  /// 분당 발걸음. 만보기가 없거나 권한이 없으면 null
  final double? cadenceSpm;

  final double km;
  final DateTime at;

  Map<String, dynamic> toMap() => {
        if (paceSecPerKm != null) 'paceSecPerKm': paceSecPerKm,
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
      cadenceSpm: (m['cadenceSpm'] as num?)?.toDouble(),
      km: (m['km'] as num?)?.toDouble() ?? 0,
      at: DateTime.fromMillisecondsSinceEpoch(at),
    );
  }
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
  });

  /// 아무리 많이 변해도 이 간격보다 자주 쓰지 않는다
  final Duration interval;

  /// 이만큼도 안 바뀌었으면 쓸 이유가 없다 (spm)
  final double cadenceEpsilon;

  /// 10m. 이보다 적게 움직였으면 상대 화면에서 달라 보이지 않는다
  final double kmEpsilon;

  LiveState? _lastWritten;

  /// 지금 써야 하는가. true면 **쓴 것으로 기록**하므로 실제로 쓸 때만 부를 것
  bool shouldWrite(LiveState next) {
    final last = _lastWritten;
    if (last == null) {
      _lastWritten = next;
      return true; // 첫 값은 무조건 — 상대가 나를 볼 수 있어야 시작된다
    }
    if (next.at.difference(last.at) < interval) return false;
    if (!_changedEnough(last, next)) return false;
    _lastWritten = next;
    return true;
  }

  bool _changedEnough(LiveState a, LiveState b) {
    if ((a.km - b.km).abs() >= kmEpsilon) return true;
    final ca = a.cadenceSpm, cb = b.cadenceSpm;
    if (ca == null && cb == null) return false;
    if (ca == null || cb == null) return true; // 있다가 없어진 것도 소식이다
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
