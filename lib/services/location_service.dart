import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// GPS 트래킹 — 거리 누적 + 페이스 계산
class LocationService {
  StreamSubscription<Position>? _sub;
  Position? _last;
  double totalKm = 0;

  /// 위치 권한 요청. 위치 서비스가 꺼져 있거나 거부되면 false
  Future<bool> requestPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  /// 트래킹 시작. onUpdate(누적 km)를 매 갱신마다 호출.
  /// onError는 위치 서비스가 꺼지거나 권한이 중간에 취소되는 등
  /// 트래킹이 더 이상 불가능해졌을 때 호출됨
  void start(void Function(double km) onUpdate, {void Function()? onError}) {
    totalKm = 0;
    _last = null;
    // iOS 전용 앱 — 폰이 잠겨도 이미 시작된 추적은 계속 이어지도록 배경 위치
    // 업데이트를 허용함. 포그라운드에서 시작한 추적을 이어가는 것뿐이라
    // "When In Use" 권한만으로도 동작함 (Always 권한 불필요)
    final settings = AppleSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5, // 5m 이동마다 갱신 (배터리 절약)
      allowBackgroundLocationUpdates: true,
      showBackgroundLocationIndicator: true,
      pauseLocationUpdatesAutomatically: false,
    );
    _sub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (pos) {
        // GPS 튐 방지: 정확도 30m 이상이면 무시
        if (pos.accuracy > 30) return;
        if (_last != null) {
          final meters = Geolocator.distanceBetween(
              _last!.latitude, _last!.longitude, pos.latitude, pos.longitude);
          final dtSeconds =
              pos.timestamp.difference(_last!.timestamp).inMilliseconds / 1000;
          // 순간이동 무시 — 터널/신호 튐 대응. 두 지점 사이 속도가
          // 10m/s(약 36km/h, 일반적인 러닝 최고 속도를 넉넉히 웃도는 값)를
          // 넘으면 무시. 업데이트가 뭉쳐 들어와 dt를 못 믿을 상황(dt<=0)이면
          // 예전처럼 절대 거리 50m 기준으로 대체
          final isOutlier =
              dtSeconds > 0 ? (meters / dtSeconds) > 10 : meters >= 50;
          if (!isOutlier) totalKm += meters / 1000;
        }
        _last = pos;
        onUpdate(totalKm);
      },
      onError: (_) => onError?.call(),
    );
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
