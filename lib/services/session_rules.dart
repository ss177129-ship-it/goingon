import 'package:cloud_firestore/cloud_firestore.dart';

/// 세션 상태 전이 규칙 — `run_service`의 트랜잭션 안에 인라인으로 있던 판정을
/// 떼어낸 것.
///
/// ## 상태 (2026-09-09 개편)
///
/// ```
/// invited ──수락──▶ accepted ──둘 다 ready──▶ running ──▶ finished
///    │                  │
///    ├─거절─▶ declined   └─나감─▶ cancelled
///    └─만료─▶ expired
/// ```
///
/// **전에는 `waiting`/`ready` 둘뿐이었고, 그중 `ready`가 거짓말을 했다.**
/// 한 사람만 준비완료를 눌러도 status가 `ready`로 바뀌어서, 이 필드로는
/// "상대가 수락했는가"도 "둘 다 준비됐는가"도 답할 수 없었다. 그래서 보낸
/// 사람은 상대가 요청을 보지도 않았는데 곧장 준비 화면으로 넘어갔다.
///
/// 지금은 **준비 여부가 status에서 빠졌다.** `ready`는 `{uid: bool}` 맵에만
/// 있고, status는 "이 만남이 어디까지 왔는가"만 말한다. 수락은 게스트만
/// 할 수 있고(규칙이 강제), 끝난 상태에서는 아무 데로도 못 간다.
///
/// 전이 자체는 단순한데 **하지 말아야 할 것**들이 규칙의 대부분이다:
/// 취소된 세션은 부활하지 않고, 함께 출발한 시각은 나중 사람이 덮어쓰지
/// 못하며, 결과를 두 번 내도 집계는 한 번만 오른다.
/// 이런 건 화면으로 재현하기 어려워 검증이 계속 미뤄졌다.
///
/// 여기 있는 함수는 전부 **입력을 받아 "어떤 업데이트를 할지"만 돌려준다.**
/// `null`을 돌려주면 아무것도 하지 말라는 뜻이다. Firestore 접근은 호출부에
/// 남으므로 앱을 띄우지 않고 규칙만 시험할 수 있다.
class SessionRules {
  const SessionRules._();

  /// GO? 요청이 살아 있는 시간
  static const requestTtl = Duration(minutes: 30);

  /// 만들어진 직후 — 게스트의 답을 기다린다
  static const invited = 'invited';

  /// 게스트가 수락했다. 이때부터 양쪽이 로비에 있다
  static const accepted = 'accepted';
  static const running = 'running';
  static const finished = 'finished';

  /// 게스트가 거절했다(한 줄 답장이 붙을 수 있다)
  static const declined = 'declined';

  /// [requestTtl]이 지나도록 답이 없었다
  static const expired = 'expired';

  /// 누군가 그만뒀다 — 호스트의 취소, 로비에서 나가기
  static const cancelled = 'cancelled';

  /// 더 갈 곳이 없는 상태. 여기서는 어떤 전이도 허용하지 않는다
  static const terminal = {finished, declined, expired, cancelled};

  /// 아직 살아 있어서 '제안' 탭에 보여야 하는 상태
  static const openStatuses = [invited, accepted];

  /// 이보다 오래 `running`에 멈춰 있으면 사실상 끝난 것으로 본다.
  /// 상대가 영영 마치지 않아도 내 기록은 '우리' 탭에 남아야 하기 때문
  static const staleRunningAfter = Duration(hours: 24);

  static String? _status(Map<String, dynamic>? data) =>
      data?['status'] as String?;

  /// 게스트의 수락. `invited`가 아니면 `null`.
  ///
  /// 호스트는 이걸 부를 수 없다 — 부르더라도 보안 규칙이 거부한다.
  /// 수락은 초대받은 쪽만 할 수 있는 일이고, 그게 이 흐름의 전부다
  static Map<String, Object?>? accept(Map<String, dynamic>? data) {
    if (_status(data) != invited) return null;
    return {'status': accepted};
  }

  /// 게스트의 거절. `invited`가 아니면 `null`.
  ///
  /// [message]는 침묵 대신 건네는 한 줄이다 — 없어도 거절은 성립한다
  static Map<String, Object?>? decline(
    Map<String, dynamic>? data, {
    String? message,
  }) {
    if (_status(data) != invited) return null;
    return {
      'status': declined,
      if (message != null && message.isNotEmpty) 'declineMessage': message,
    };
  }

  /// 답이 없는 채로 [requestTtl]이 지난 요청. `invited`가 아니면 `null`.
  ///
  /// 취소와 나누는 이유: 만료는 아무도 그만두지 않았는데 끝난 것이라,
  /// 보낸 사람에게 보여줄 문장이 다르다("답이 오지 않았어요")
  static Map<String, Object?>? expire(Map<String, dynamic>? data) {
    if (_status(data) != invited) return null;
    return {'status': expired};
  }

  /// 준비 완료를 표시하는 업데이트. 살아 있지 않은 세션이면 `null`.
  ///
  /// **status를 건드리지 않는다.** 전에는 여기서 `status: 'ready'`로 바꿨는데,
  /// 한 사람만 눌러도 바뀌는 값이라 "둘 다 준비됐다"는 뜻이 될 수 없었다.
  /// 준비 여부는 `ready` 맵 하나에만 산다.
  ///
  /// 상태를 확인하는 이유: 상대가 취소한 직후 내가 준비 버튼을 누르면
  /// 세션이 되살아나 아무도 원하지 않는 러닝이 시작된다
  static Map<String, Object?>? ready(Map<String, dynamic>? data, String uid) {
    if (_status(data) != accepted) return null;
    return {'ready.$uid': true};
  }

  /// 두 사람 모두 준비됐는가 — 카운트다운을 시작해도 되는 유일한 조건
  static bool bothReady(Map<String, dynamic>? data) {
    final ready = data?['ready'];
    if (ready is! Map) return false;
    final host = data?['hostId'], guest = data?['guestId'];
    return ready[host] == true && ready[guest] == true;
  }

  /// 출발 업데이트. 취소된 세션이면 `null`.
  ///
  /// `startedAt`은 **먼저 찍힌 값을 유지한다.** 양쪽 클라이언트가 각자 이걸
  /// 부르는데 덮어쓰면 '함께 출발한 시각'이 나중 사람 기준으로 밀리고,
  /// 두 사람의 기록이 서로 다른 시작점을 갖게 된다
  static Map<String, Object?>? start(Map<String, dynamic>? data) {
    if (_status(data) != accepted) return null;
    final alreadyStarted = data?['startedAt'] != null;
    return {
      'status': running,
      if (!alreadyStarted) 'startedAt': FieldValue.serverTimestamp(),
    };
  }

  /// 결과 제출 업데이트와 "이번이 첫 제출인지".
  ///
  /// 첫 제출 여부가 중요한 이유: 제출이 실패해 재시도하면 같은 러닝이 두 번
  /// 올라오는데, 그때마다 이번 달 거리와 횟수가 또 더해지면 안 된다
  static SubmitOutcome submit(
    Map<String, dynamic>? data,
    String uid, {
    required int seconds,
    required double km,
    required int kcal,
    String? mood,
  }) {
    final results = Map<String, dynamic>.from(data?['results'] ?? {});
    final alreadySubmitted = results.containsKey(uid);
    final mine = {
      'seconds': seconds,
      'km': km,
      'kcal': kcal,
      if (mood != null) 'mood': mood,
    };
    results[uid] = mine;
    return SubmitOutcome(
      update: {
        'results.$uid': mine,
        // 둘 다 냈으면 세션을 닫는다
        if (results.length >= 2) 'status': finished,
      },
      isFirstSubmit: !alreadySubmitted,
    );
  }

  /// 그만두기. 이미 달리는 중이거나 끝난 세션이면 `null`.
  ///
  /// 오래된 정리 로직이 뒤늦게 도착해 진행 중인 러닝을 취소하면 기록이 통째로
  /// 날아가므로, 아직 시작 전인 세션만 취소한다.
  ///
  /// 거절([decline])과 다르다 — 거절은 초대를 받은 쪽이 "안 할래요"라고 하는
  /// 것이고, 취소는 누구든 하던 것을 그만두는 것이다
  static Map<String, Object?>? cancel(Map<String, dynamic>? data) {
    final status = _status(data);
    if (status != invited && status != accepted) return null;
    return {'status': cancelled};
  }

  /// 아직 살아 있는 요청인지. `createdAt`이 없으면 서버 시각이 아직 안 찍힌
  /// 것이므로 판단을 보류한다(살아 있다고 보지 않음)
  static bool isRequestAlive(Timestamp? createdAt, DateTime now) {
    if (createdAt == null) return false;
    return now.difference(createdAt.toDate()) < requestTtl;
  }

  /// `running`으로 멈춰 있지만 사실상 끝난 세션인지.
  /// 내 결과가 올라가 있어야 하고([staleRunningAfter])만큼 지나야 한다
  static bool isStaleRunning(
    Map<String, dynamic> data,
    String myUid,
    DateTime now,
  ) {
    final startedAt = data['startedAt'] as Timestamp?;
    if (startedAt == null) return false;
    final results = data['results'];
    final hasMyResult = results is Map && results.containsKey(myUid);
    if (!hasMyResult) return false;
    return now.difference(startedAt.toDate()) > staleRunningAfter;
  }
}

/// [SessionRules.submit]의 결과
class SubmitOutcome {
  final Map<String, Object?> update;

  /// 이 세션에 내 기록이 처음 올라가는가. 월간 집계는 이때만 올린다
  final bool isFirstSubmit;

  const SubmitOutcome({required this.update, required this.isFirstSubmit});
}
