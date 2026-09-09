import 'week_key.dart';

/// 페이스메이트가 지금 어떤 상태인지 — 홈 카드의 한 줄.
///
/// **presence(온라인·뛰는 중)는 만들 수 없다.** 보안 규칙이 세션을
/// hostId/guestId 직접 비교로만 열어 주기 때문에, 나와 얽히지 않은 상대의
/// 세션은 애초에 읽히지 않는다. 그래서 여기서 말하는 "상태"는 실시간이
/// 아니라 **러닝이 끝날 때마다 상대 문서에 남는 기록**이다:
/// `lastRunWeek`·`weekStreak`·`monthKey`·`monthKm`.
///
/// 없는 것을 있다고 말하지 않기 위해, 해상도는 **주 단위**로 못박는다.
/// "3시간 전에 달렸어요" 같은 문장은 쓸 수 있는 데이터가 아니다.
enum PacemateTone {
  /// 이번 주에 달렸다 — 지금 부르면 응답할 가능성이 가장 높은 사람
  active,

  /// 최근에 달린 흔적은 있다
  steady,

  /// 최근 기록이 없다. 점을 찍지 않는다 — 회색 점은 고장으로 읽힌다
  quiet,
}

class PacemateStatus {
  final String label;
  final PacemateTone tone;

  const PacemateStatus(this.label, this.tone);

  /// 연속 주(`weekStreak`)가 **아직 살아 있는가.**
  ///
  /// 이 필드는 러닝이 끝날 때만 갱신되므로, 끊긴 연속이 문서에 영원히
  /// 남는다. 몇 달 전에 멈춘 사람 옆에 "3주 연속"이 붙어 있으면 그것은
  /// 기록이 아니라 거짓말이다. 이번 주에 달렸거나(계속 중), 지난주에
  /// 달렸으면(이번 주에 이으면 유지) 살아 있다고 본다
  static bool streakAlive(Map<String, dynamic>? user, DateTime now) {
    final streak = ((user?['weekStreak'] ?? 0) as num).toInt();
    if (streak < 1) return false;
    final lastRunWeek = user?['lastRunWeek'] as String?;
    if (lastRunWeek == null) return false;
    final thisWeek = weekKeyOf(now);
    return lastRunWeek == thisWeek || _isLastWeek(lastRunWeek, thisWeek);
  }

  /// [user]는 `users/{uid}` 문서. 필드가 통째로 없는 새 계정도 들어온다
  static PacemateStatus of(Map<String, dynamic>? user, DateTime now) {
    final thisWeek = weekKeyOf(now);
    final lastRunWeek = user?['lastRunWeek'] as String?;
    final streak = ((user?['weekStreak'] ?? 0) as num).toInt();

    if (lastRunWeek == thisWeek) {
      // 연속 주는 2주부터가 이야기다 — 1주 연속은 그냥 "이번 주"다
      return PacemateStatus(
        streak >= 2 ? '이번 주 달렸어요 · $streak주 연속' : '이번 주 달렸어요',
        PacemateTone.active,
      );
    }

    if (lastRunWeek != null && _isLastWeek(lastRunWeek, thisWeek)) {
      return const PacemateStatus('지난주에 달렸어요', PacemateTone.steady);
    }

    final monthKm = _monthKm(user, now);
    if (monthKm > 0) {
      return PacemateStatus(
          '이번 달 ${monthKm.toStringAsFixed(1)}km', PacemateTone.steady);
    }

    // 기록이 아예 없는 사람과, 있었지만 뜸해진 사람을 굳이 가르지 않는다.
    // 둘 다 지금 할 수 있는 일은 같다 — 부르는 것
    return const PacemateStatus('먼저 불러보세요', PacemateTone.quiet);
  }

  /// 달이 바뀌면 monthKm은 지난달 값이 그대로 남아 있다([monthKey]로만
  /// 알 수 있다). 그걸 이번 달 기록으로 읽으면 없는 거리를 만들어 낸다
  static double _monthKm(Map<String, dynamic>? user, DateTime now) {
    final monthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    if (user?['monthKey'] != monthKey) return 0;
    return ((user?['monthKm'] ?? 0) as num).toDouble();
  }

  /// [isPrevWeek]는 "current가 last 다음 주인가"를 묻는다 — 인자 순서가
  /// 헷갈리기 쉬워 여기서 한 번만 감싸 둔다. 형식이 깨진 옛 값이 들어와도
  /// 화면이 죽지 않아야 하므로 파싱 실패는 '아님'으로 흘린다
  static bool _isLastWeek(String lastRunWeek, String thisWeek) {
    try {
      return isPrevWeek(lastRunWeek, thisWeek);
    } on FormatException {
      return false;
    }
  }
}
