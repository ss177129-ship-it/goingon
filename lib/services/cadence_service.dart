import 'dart:async';

import 'package:flutter/services.dart';

/// 내 발걸음 리듬(분당 발걸음, spm).
///
/// 값을 만드는 곳은 iOS의 `CMPedometer`이고, 그 값을 넘겨주는 다리는
/// `ios/Runner/CadencePlugin.swift`다. pub.dev 플러그인들이 걸음 **수**만
/// 노출해서 직접 붙였다 — 자세한 이유는 그 파일 주석에 있다.
///
/// **없을 수 있는 값이다.** 시뮬레이터에는 만보기가 없고, 사용자가 모션
/// 권한을 거부할 수도 있다. 그때 이 스트림은 그냥 아무것도 내보내지 않는다.
/// 호출부는 "케이던스가 없다"를 정상 상태로 다뤄야 한다 — 러닝 기록과
/// 거리 계산은 케이던스와 아무 상관이 없다.
class CadenceService {
  static const _channel = EventChannel('goingon/cadence');

  /// 달리는 동안의 spm. 걷다 서면 값이 뜸해지거나 멈춘다
  Stream<double> stream() => _channel
      .receiveBroadcastStream()
      .map((v) => (v as num).toDouble())
      // 채널이 죽어도 러닝은 계속돼야 한다. 에러를 흘리지 않고 스트림만 닫는다
      .handleError((_) {})
      .where(isPlausible);

  /// 사람이 낼 수 있는 값인가.
  ///
  /// 주머니에서 폰이 흔들리거나 계단을 뛰어내릴 때 만보기가 터무니없는 값을
  /// 내는 일이 있다. 걷기는 분당 90보 아래로도 내려가지만 **달리기**에서
  /// 그 아래는 측정 오류로 본다. 위쪽 250은 세계 기록권 스프린터보다 높다
  static bool isPlausible(double spm) => spm >= 100 && spm <= 250;
}
