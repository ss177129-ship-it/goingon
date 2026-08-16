import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import 'run_accumulator.dart';

/// GPS 트래킹 — 스트림 구독·권한·백그라운드 관리.
///
/// 필터링과 거리 누적은 [RunAccumulator]가 맡는다. 예전에는 [start] 안에
/// 뒤섞여 있어서 앱을 띄우지 않고는 검증할 수 없었는데, 떼어낸 뒤로는
/// 합성 fix를 넣어 `test/run_accumulator_test.dart`에서 그대로 재생할 수 있다.
class LocationService {
  StreamSubscription<Position>? _sub;
  RunAccumulator? _accumulator;

  double get totalKm => _accumulator?.totalKm ?? 0;

  /// Always 권한까지 받았는지 — 이때만 배경 위치 추적을 켬.
  /// When In Use만 있는데 배경 추적을 강제로 켜면 iOS가 앱을 강제 종료시킴
  bool _canRunInBackground = false;

  /// 폰을 잠가도 기록이 이어지는가.
  ///
  /// false면 화면이 꺼지는 순간 GPS가 멈춰 거리가 안 늘어난다 — 그래서 그때만
  /// 화면을 강제로 켜두고(wakelock) 사용자에게도 알려야 한다. true면 잠금화면에
  /// 맡기고 화면을 꺼도 되므로 배터리를 아낄 수 있다
  bool get tracksInBackground => _canRunInBackground;

  /// 위치 권한 요청. When In Use를 먼저 받고, 그것뿐이면 Always로 업그레이드를
  /// 시도함(화면 꺼도 계속 기록되게). onBeforeAlwaysUpgrade는 시스템 다이얼로그
  /// 뜨기 직전에 왜 필요한지 안내할 기회 — 거절해도 크래시 없이 When In Use로
  /// 계속 진행되고, 그 경우 배경 추적만 못 함 (전면 실행 중에는 그대로 동작)
  Future<bool> requestPermission(
      {Future<void> Function()? onBeforeAlwaysUpgrade}) async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    final hasBasicAccess = permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
    if (!hasBasicAccess) return false;

    if (permission == LocationPermission.whileInUse) {
      await onBeforeAlwaysUpgrade?.call();
      await ph.Permission.locationAlways.request();
      permission = await Geolocator.checkPermission();
    }
    _canRunInBackground = permission == LocationPermission.always;
    return true;
  }

  /// 트래킹 시작. onUpdate(누적 km)를 매 갱신마다 호출.
  /// onError는 위치 서비스가 꺼지거나 권한이 중간에 취소되는 등
  /// 트래킹이 더 이상 불가능해졌을 때 호출됨
  void start(void Function(double km) onUpdate, {void Function()? onError}) {
    _accumulator = RunAccumulator(config: RunFilterConfig.current);
    // iOS 전용 앱 — Always 권한이 있을 때만 배경 위치 업데이트를 허용함
    // (requestPermission에서 미리 확인됨). When In Use만 있으면 폰이 잠기는
    // 순간 GPS가 멈추지만, 최소한 크래시는 나지 않음
    final settings = AppleSettings(
      accuracy: LocationAccuracy.high,
      // 5m 이동마다 갱신 (배터리 절약) — 값은 RunFilterConfig에 모아둠
      distanceFilter: RunFilterConfig.current.locationDistanceFilter.toInt(),
      allowBackgroundLocationUpdates: _canRunInBackground,
      showBackgroundLocationIndicator: _canRunInBackground,
      pauseLocationUpdatesAutomatically: false,
    );
    _sub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (pos) {
        // 필터·누적 판정은 전부 RunAccumulator가 한다. null은 "호출부가
        // 아무것도 하지 않아야 하는 fix"이고(예전 코드의 이른 return과 동일),
        // 이상치로 거리에 반영되지 않은 fix는 거리가 그대로인 채 콜백까지
        // 도달한다 — 이것도 예전 동작 그대로
        if (_accumulator?.add(pos) == null) return;
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
  /// 너무 이른 거리(20m 미만)에서는 GPS 오차가 상대적으로 커서 계산 안 함 —
  /// 예전엔 50m 기준이라 걷는 속도에선 30~40초 넘게 빈 값만 보여서
  /// 마치 안 되는 것처럼 느껴졌음
  static String pace(double km, int seconds) {
    if (km < 0.02) return "--'--\"";
    final secPerKm = seconds / km;
    final m = secPerKm ~/ 60;
    final s = (secPerKm % 60).round();
    return "$m'${s.toString().padLeft(2, '0')}\"";
  }
}
