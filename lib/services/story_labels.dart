import 'package:cloud_firestore/cloud_firestore.dart';

// '우리' 탭 데이터 계산에 쓰는 순수 함수들 — UsScreen에서 분리해
// 위젯 없이 단위 테스트할 수 있게 함

num sessionField(Map<String, dynamic> session, String uid, String key) {
  final results = session['results'];
  if (results is! Map) return 0;
  final r = results[uid];
  if (r is! Map) return 0;
  final v = r[key];
  return v is num ? v : 0;
}

double combinedKm(Map<String, dynamic> s, String me, String partner) =>
    sessionField(s, me, 'km').toDouble() +
    sessionField(s, partner, 'km').toDouble();

DateTime? sessionStartedAt(Map<String, dynamic> s) {
  final ts = s['startedAt'];
  return ts is Timestamp ? ts.toDate() : null;
}

/// 새 데이터 없이 기존 startedAt·km에서 계산하는 파생 스토리 라벨 —
/// 행마다 최대 하나만 붙음 (첫 함께 달리기 > 가장 멀리 간 날 > 첫 새벽/밤 순 우선)
Map<String, String> storyLabelsFor(
    List<Map<String, dynamic>> ascending, String me, String partnerUid) {
  final labels = <String, String>{};
  if (ascending.isEmpty) return labels;

  labels[ascending.first['id'] as String] = '첫 함께 달리기';

  var maxKm = -1.0;
  String? maxId;
  for (final s in ascending) {
    final km = combinedKm(s, me, partnerUid);
    if (km > maxKm) {
      maxKm = km;
      maxId = s['id'] as String;
    }
  }
  if (maxId != null) labels.putIfAbsent(maxId, () => '가장 멀리 간 날');

  var dawnFound = false;
  var nightFound = false;
  for (final s in ascending) {
    final started = sessionStartedAt(s);
    if (started == null) continue;
    final id = s['id'] as String;
    if (!dawnFound && started.hour >= 5 && started.hour < 7) {
      labels.putIfAbsent(id, () => '첫 새벽 러닝');
      dawnFound = true;
    }
    if (!nightFound && started.hour >= 22) {
      labels.putIfAbsent(id, () => '첫 밤 러닝');
      nightFound = true;
    }
  }
  return labels;
}
