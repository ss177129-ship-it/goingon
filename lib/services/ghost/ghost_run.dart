// 고스트 — 지난 러닝이 남긴 '그날의 리듬'.
//
// **모든 러닝이 자동으로 고스트가 된다**(§3-2). 따로 저장 버튼을 두지 않는
// 이유는, 나중에 누군가 나와 달리고 싶어질 때 그 러닝이 이미 있어야 하기
// 때문이다. 사후에 만들 수 없는 데이터라 기본값이 '남긴다'여야 한다.
//
// **GPS 경로는 담지 않는다.** 재생이 시간축 기반이라 경로가 필요 없고(§3-2),
// 담지 않으면 위치정보 규제 부담도 사라진다(기술설계서 §1-3). 지수가 도림천을
// 뛰었어도 나는 내 동네에서 그날의 리듬과 함께 뛴다 — 그것이 "멀리 있어도"의
// 기술적 실체다.
import '../cadence/partner_cadence.dart';

/// 누가 이 고스트와 달릴 수 있는가. **기본은 페이스메이트만**(§3-2).
///
/// 기본값이 '모두'가 아닌 이유: 1차 세그먼트는 기록 공개가 부담스러운
/// 사람들이다(D-006). 공개가 기본이면 그들이 첫 러닝을 남기지 않는다.
enum GhostVisibility {
  /// 나만 — 내 과거와 달리는 데는 쓰인다
  private('private'),

  /// 페이스메이트만 (기본값)
  pacemates('pacemates'),

  /// 모두
  everyone('everyone');

  const GhostVisibility(this.wire);

  /// Firestore에 실려 가는 문자열
  final String wire;

  static GhostVisibility fromWire(String? s) =>
      values.firstWhere((v) => v.wire == s, orElse: () => pacemates);
}

/// 고스트 1건. `runs/{runId}` 문서 하나에 대응한다.
class GhostRun {
  const GhostRun({
    required this.id,
    required this.uid,
    required this.startedAt,
    required this.duration,
    required this.km,
    required this.cadence,
    this.kcal = 0,
    this.visibility = GhostVisibility.pacemates,
    this.story,
    this.episodeId,
    this.sessionId,
    this.slowdownMarkers = const [],
  });

  final String id;
  final String uid;
  final DateTime startedAt;
  final Duration duration;
  final double km;
  final int kcal;

  /// 1초 해상도의 케이던스. 값이 없는 초(정지·결측)는 null
  final List<double?> cadence;

  final GhostVisibility visibility;

  /// 사연 한 마디 — 쿨다운에서 채집한 음성의 전사(§5). P6에서 채워진다.
  /// **이 한 마디가 사연 아카이브·카드 캡션·릴레이 문구의 단일 공급원이다**
  final String? story;

  /// 어느 에피소드였는지 (자유런이면 null)
  final String? episodeId;

  /// 라이브 세션이었으면 그 id
  final String? sessionId;

  /// 상대가 느려진 지점(초). 화자가 여기서 한 줄 한다 — **세션당 최대 2회**.
  /// "여기서 지수가 힘들었나 봐요"는 관찰이지 평가가 아니다
  final List<int> slowdownMarkers;

  /// 재생기가 쓰는 형태로. P2의 인터페이스에 그대로 꽂힌다
  GhostCadenceTimeline get timeline => GhostCadenceTimeline(cadence);

  /// 2분 미만은 고스트로 쓰지 않는다 — 함께 달릴 것이 없다
  static const minUsable = Duration(minutes: 2);
  bool get isUsable => duration >= minUsable;

  Map<String, Object?> toMap() => {
        'uid': uid,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'seconds': duration.inSeconds,
        'km': km,
        'kcal': kcal,
        // delta 압축 — 케이던스는 초당 몇 spm씩만 움직여서 차이값이 대부분
        // 한 자릿수다. 8분 세션이 480개 작은 정수로 줄어든다
        'cadence': timeline.toDeltas(),
        'visibility': visibility.wire,
        if (story != null) 'story': story,
        if (episodeId != null) 'episodeId': episodeId,
        if (sessionId != null) 'sessionId': sessionId,
        if (slowdownMarkers.isNotEmpty) 'slowdownMarkers': slowdownMarkers,
        // route는 넣지 않는다 — 기본 비저장(§3-2)
      };

  static GhostRun? fromMap(String id, Map<String, dynamic>? m) {
    if (m == null) return null;
    final startedAt = DateTime.tryParse((m['startedAt'] as String?) ?? '');
    if (startedAt == null) return null;
    final deltas = (m['cadence'] as List?)
            ?.map((e) => e == null ? null : (e as num).toInt())
            .toList() ??
        const <int?>[];
    return GhostRun(
      id: id,
      uid: (m['uid'] as String?) ?? '',
      startedAt: startedAt,
      duration: Duration(seconds: ((m['seconds'] as num?) ?? 0).toInt()),
      km: ((m['km'] as num?) ?? 0).toDouble(),
      kcal: ((m['kcal'] as num?) ?? 0).toInt(),
      cadence: GhostCadenceTimeline.fromDeltas(deltas).spmPerSecond,
      visibility: GhostVisibility.fromWire(m['visibility'] as String?),
      story: m['story'] as String?,
      episodeId: m['episodeId'] as String?,
      sessionId: m['sessionId'] as String?,
      slowdownMarkers: (m['slowdownMarkers'] as List?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const [],
    );
  }
}

/// 러닝 중에 케이던스를 1초 해상도로 모은다.
///
/// 왜 1초인가: 더 촘촘하면 문서가 커지고, 더 성기면 발맞춤 판정(1Hz)이
/// 자기보다 느린 입력을 보게 된다. 재생 쪽과 같은 해상도여야 한다.
class GhostRecorder {
  GhostRecorder({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final _spm = <double?>[];
  DateTime? _startedAt;

  /// 상대가 느려진 지점 — 재생 때 화자가 한 줄 하는 자리
  final _slowdowns = <int>[];

  /// 이만큼 떨어지면 '느려짐'으로 본다. 러닝 중 자연스러운 흔들림보다는 크고,
  /// 걷기 전환보다는 작은 값
  static const kSlowdownDropSpm = 12.0;

  List<double?> get cadence => List.unmodifiable(_spm);
  List<int> get slowdownMarkers => List.unmodifiable(_slowdowns);
  Duration get duration => Duration(seconds: _spm.length);

  void start() {
    _startedAt = _clock();
    _spm.clear();
    _slowdowns.clear();
  }

  /// 1초 틱에서 부른다. [spm]이 null이면 그 초는 '모름'으로 남는다 —
  /// 0으로 채우면 "멈춰 서 있었다"는 없는 사실이 기록된다
  void sample(double? spm) {
    if (_startedAt == null) return;
    final prev = _lastKnown();
    _spm.add(spm);
    if (prev != null && spm != null && prev - spm >= kSlowdownDropSpm) {
      // 연속으로 찍히지 않게 — 한 번 느려진 구간에 마커가 열 개 생기면
      // 화자가 열 번 말한다
      if (_slowdowns.isEmpty || _spm.length - _slowdowns.last > 20) {
        _slowdowns.add(_spm.length - 1);
      }
    }
  }

  double? _lastKnown() {
    for (var i = _spm.length - 1; i >= 0; i--) {
      final v = _spm[i];
      if (v != null) return v;
    }
    return null;
  }

  /// 저장할 고스트를 만든다. [id]는 호출부(Firestore)가 정한다
  GhostRun build({
    required String id,
    required String uid,
    required double km,
    int kcal = 0,
    String? episodeId,
    String? sessionId,
    GhostVisibility visibility = GhostVisibility.pacemates,
  }) =>
      GhostRun(
        id: id,
        uid: uid,
        startedAt: _startedAt ?? _clock(),
        duration: duration,
        km: km,
        kcal: kcal,
        cadence: cadence,
        visibility: visibility,
        episodeId: episodeId,
        sessionId: sessionId,
        slowdownMarkers: slowdownMarkers,
      );
}
