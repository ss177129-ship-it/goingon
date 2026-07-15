// 주간 스트릭 계산에 쓰는 순수 함수 — RunService에서 분리해
// Firestore 없이 단위 테스트할 수 있게 함

/// 그 주 월요일 날짜(YYYY-MM-DD)를 키로 사용
String weekKeyOf(DateTime d) {
  final monday =
      DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));
  return '${monday.year}-${monday.month.toString().padLeft(2, '0')}-'
      '${monday.day.toString().padLeft(2, '0')}';
}

/// currentWeekKey가 lastWeekKey 바로 다음 주(월요일 기준 7일 뒤)인지
bool isPrevWeek(String lastWeekKey, String currentWeekKey) {
  final last = DateTime.parse(lastWeekKey);
  final current = DateTime.parse(currentWeekKey);
  return current.difference(last).inDays == 7;
}
