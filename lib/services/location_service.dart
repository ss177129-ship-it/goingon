import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// GPS 트래킹 — 거리 누적 + 페이스 계산
class LocationService {
  StreamSubscription<Position>? _sub;
  Position? _last;
  double totalKm = 0;

  /// 위치 권한 요청. 거부되면 false
  Future<bool> requestPermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  /// 트래킹 시작. onUpdate(누적 km)를 매 갱신마다 호출
  void start(void Function(double km) onUpdate) {
    totalKm = 0;
    _last = null;
    const settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5, // 5m 이동마다 갱신 (배터리 절약)
    );
    _sub = Geolocator.getPositionStream(locationSettings: settings)
        .listen((pos) {
      // GPS 튐 방지: 정확도 30m 이상이면 무시
      if (pos.accuracy > 30) return;
      if (_last != null) {
        final meters = Geolocator.distanceBetween(
            _last!.latitude, _last!.longitude, pos.latitude, pos.longitude);
        // 순간이동(1초에 50m 이상) 무시 — 터널/신호 튐 대응
        if (meters < 50) totalKm += meters / 1000;
      }
      _last = pos;
      onUpdate(totalKm);
    });
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  /// 대략적 칼로리 (러닝 MET 9.8 × 체중 65kg 가정, v1.1에서 체중 입력)
  static int estimateKcal(int seconds) =>
      (9.8 * 65 * (seconds / 3600)).round();

  /// 분'초" 페이스 문자열
  static String pace(double km, int seconds) {
    if (km < 0.05) return "--'--\"";
    final secPerKm = seconds / km;
    final m = secPerKm ~/ 60;
    final s = (secPerKm % 60).round();
    return "$m'${s.toString().padLeft(2, '0')}\"";
  }
}
