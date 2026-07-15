import 'package:flutter_test/flutter_test.dart';
import 'package:goingon/services/week_key.dart';

void main() {
  group('weekKeyOf', () {
    test('그 주 월요일 날짜를 반환함 (목요일 기준)', () {
      // 2026-01-15는 목요일, 그 주 월요일은 2026-01-12
      expect(weekKeyOf(DateTime(2026, 1, 15)), '2026-01-12');
    });

    test('월요일 자신을 넣으면 그대로 반환함', () {
      expect(weekKeyOf(DateTime(2026, 1, 12)), '2026-01-12');
    });

    test('일요일이면 그 주(전날까지) 월요일을 반환함', () {
      expect(weekKeyOf(DateTime(2026, 1, 18)), '2026-01-12');
    });
  });

  group('isPrevWeek', () {
    test('연속된 두 주 월요일이면 true', () {
      expect(isPrevWeek('2026-01-05', '2026-01-12'), isTrue);
    });

    test('같은 주면 false', () {
      expect(isPrevWeek('2026-01-12', '2026-01-12'), isFalse);
    });

    test('한 주를 건너뛰면 false', () {
      expect(isPrevWeek('2026-01-05', '2026-01-19'), isFalse);
    });
  });
}
