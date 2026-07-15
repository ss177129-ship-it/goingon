import 'package:flutter_test/flutter_test.dart';
import 'package:goingon/services/location_service.dart';

void main() {
  group('LocationService.estimateKcal', () {
    test('1시간(3600초)이면 MET 9.8 × 체중 65kg 기준 637kcal', () {
      expect(LocationService.estimateKcal(3600), 637);
    });

    test('0초면 0kcal', () {
      expect(LocationService.estimateKcal(0), 0);
    });
  });

  group('LocationService.pace', () {
    test('50m 미만이면 아직 페이스를 계산할 수 없음', () {
      expect(LocationService.pace(0.03, 100), "--'--\"");
    });

    test('1km를 5분 30초에 뛰면 5\'30"', () {
      expect(LocationService.pace(1.0, 330), "5'30\"");
    });

    test('초 단위가 한 자리면 0으로 패딩됨', () {
      expect(LocationService.pace(5.0, 1500), "5'00\"");
    });
  });
}
