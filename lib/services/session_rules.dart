import 'package:cloud_firestore/cloud_firestore.dart';

/// 세션 상태 전이 규칙 — `run_service`의 트랜잭션 안에 인라인으로 있던 판정을
/// 떼어낸 것.
///
/// 전이 자체는 단순한데(waiting → ready → running → finished) **하지 말아야 할
/// 것**들이 규칙의 대부분이다: 취소된 세션은 부활하지 않고, 함께 출발한 시각은
/// 나중 사람이 덮어쓰지 못하며, 결과를 두 번 내도 집계는 한 번만 오른다.
/// 이런 건 화면으로 재현하기 어려워 검증이 계속 미뤄졌다.
///
/// 여기 있는 함수는 전부 **입력을 받아 "어떤 업데이트를 할지"만 돌려준다.**
/// `null`을 돌려주면 아무것도 하지 말라는 뜻이다. Firestore 접근은 호출부에
/// 남으므로 앱을 띄우지 않고 규칙만 시험할 수 있다.
class SessionRules {
  const SessionRules._();

  /// GO? 요청이 살아 있는 시간
  static const requestTtl = Duration(minutes: 30);

  /// 이보다 오래 `running`에 멈춰 있으면 사실상 끝난 것으로 본다.
  /// 상대가 영영 마치지 않아도 내 기록은 '우리' 탭에 남아야 하기 때문
  static const staleRunningAfter = Duration(hours: 24);

  static String? _status(Map<String, dynamic>? data) =>
      data?['status'] as String?;

  /// 준비 완료를 표시하는 업데이트. 취소된 세션이면 `null`.
  ///
  /// 취소를 확인하는 이유: 상대가 취소한 직후 내가 준비 버튼을 누르면
  /// 세션이 되살아나 아무도 원하지 않는 러닝이 시작된다
  static Map<String, Object?>? ready(Map<String, dynamic>? data, String uid) {
    if (_status(data) == 'cancelled') return null;
    return {'ready.$uid': true, 'status': 'ready'};
  }

  /// 출발 업데이트. 취소된 세션이면 `null`.
  ///
  /// `startedAt`은 **먼저 찍힌 값을 유지한다.** 양쪽 클라이언트가 각자 이걸
  /// 부르는데 덮어쓰면 '함께 출발한 시각'이 나중 사람 기준으로 밀리고,
  /// 두 사람의 기록이 서로 다른 시작점을 갖게 된다
  static Map<String, Object?>? start(Map<String, dynamic>? data) {
    if (_status(data) == 'cancelled') return null;
    final alreadyStarted = data?['startedAt'] != null;
    return {
      'status': 'running',
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
        if (results.length >= 2) 'status': 'finished',
      },
      isFirstSubmit: !alreadySubmitted,
    );
  }

  /// 취소 업데이트. 이미 달리는 중이거나 끝난 세션이면 `null`.
  ///
  /// 오래된 정리 로직이 뒤늦게 도착해 진행 중인 러닝을 취소하면 기록이 통째로
  /// 날아가므로, 아직 시작 전인 세션만 취소한다
  static Map<String, Object?>? cancel(
    Map<String, dynamic>? data, {
    String? declineMessage,
  }) {
    final status = _status(data);
    if (status != 'waiting' && status != 'ready') return null;
    return {
      'status': 'cancelled',
      if (declineMessage != null) 'declineMessage': declineMessage,
    };
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
