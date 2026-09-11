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
    test('20m 미만이면 아직 페이스를 계산할 수 없음', () {
      expect(LocationService.pace(0.01, 100), "--'--\"");
    });

    test('1km를 5분 30초에 뛰면 5\'30"', () {
      expect(LocationService.pace(1.0, 330), "5'30\"");
    });

    test('초 단위가 한 자리면 0으로 패딩됨', () {
      expect(LocationService.pace(5.0, 1500), "5'00\"");
    });
  });

  group('LocationService.formatPace', () {
    test('km당 330초면 5\'30"', () {
      expect(LocationService.formatPace(330), "5'30\"");
    });

    test('59.6초가 60으로 반올림돼 5\'60"이 되지 않는다', () {
      expect(LocationService.formatPace(359.6), "6'00\"");
    });

    test('모르는 값(NaN·무한대·0 이하)은 빈 페이스', () {
      expect(LocationService.formatPace(double.nan), "--'--\"");
      expect(LocationService.formatPace(double.infinity), "--'--\"");
      expect(LocationService.formatPace(0), "--'--\"");
      expect(LocationService.formatPace(-5), "--'--\"");
    });

    test('20분/km를 넘으면 서 있는 것 — 숫자 대신 빈 페이스', () {
      expect(LocationService.formatPace(1199), "19'59\"");
      expect(LocationService.formatPace(1200), "--'--\"");
    });
  });
}
