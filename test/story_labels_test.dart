import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goingon/services/story_labels.dart';

Map<String, dynamic> _session(String id, DateTime startedAt,
    {double meKm = 1, double partnerKm = 1}) {
  return {
    'id': id,
    'startedAt': Timestamp.fromDate(startedAt),
    'results': {
      'me': {'km': meKm, 'seconds': 600},
      'partner': {'km': partnerKm, 'seconds': 600},
    },
  };
}

void main() {
  group('sessionField / combinedKm', () {
    test('세션에 없는 uid의 필드는 0', () {
      final s = _session('a', DateTime(2026, 1, 1));
      expect(sessionField(s, 'nobody', 'km'), 0);
    });

    test('combinedKm은 양쪽 km의 합', () {
      final s = _session('a', DateTime(2026, 1, 1), meKm: 3, partnerKm: 2);
      expect(combinedKm(s, 'me', 'partner'), 5.0);
    });
  });

  group('storyLabelsFor', () {
    test('빈 목록이면 빈 라벨', () {
      expect(storyLabelsFor([], 'me', 'partner'), isEmpty);
    });

    test('첫 세션엔 항상 "첫 함께 달리기"가 붙음', () {
      final sessions = [_session('a', DateTime(2026, 1, 1, 12))];
      final labels = storyLabelsFor(sessions, 'me', 'partner');
      expect(labels['a'], '첫 함께 달리기');
    });

    test('가장 멀리 간 날에 별도 라벨이 붙음', () {
      final sessions = [
        _session('a', DateTime(2026, 1, 1, 12), meKm: 1, partnerKm: 1),
        _session('b', DateTime(2026, 1, 2, 12), meKm: 5, partnerKm: 5),
      ];
      final labels = storyLabelsFor(sessions, 'me', 'partner');
      expect(labels['a'], '첫 함께 달리기');
      expect(labels['b'], '가장 멀리 간 날');
    });

    test('한 세션이 여러 조건을 만족해도 라벨은 하나만 (첫 함께 달리기 우선)', () {
      final sessions = [
        _session('a', DateTime(2026, 1, 1, 12), meKm: 10, partnerKm: 10),
      ];
      final labels = storyLabelsFor(sessions, 'me', 'partner');
      expect(labels, {'a': '첫 함께 달리기'});
    });

    test('새벽(5~7시) 러닝엔 첫 새벽 러닝 라벨', () {
      final sessions = [
        _session('a', DateTime(2026, 1, 1, 12)),
        _session('b', DateTime(2026, 1, 2, 6)),
      ];
      final labels = storyLabelsFor(sessions, 'me', 'partner');
      expect(labels['b'], '첫 새벽 러닝');
    });

    test('밤(22시 이후) 러닝엔 첫 밤 러닝 라벨', () {
      final sessions = [
        _session('a', DateTime(2026, 1, 1, 12)),
        _session('b', DateTime(2026, 1, 2, 23)),
      ];
      final labels = storyLabelsFor(sessions, 'me', 'partner');
      expect(labels['b'], '첫 밤 러닝');
    });
  });
}
