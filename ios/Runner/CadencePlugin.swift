import CoreMotion
import Flutter

/// 케이던스(분당 발걸음, spm)를 Flutter로 흘려보낸다.
///
/// **왜 직접 만들었나:** pub.dev의 만보기 플러그인들(pedometer, pedometer_2)은
/// 걸음 **수**와 보행 상태만 노출한다. 우리가 필요한 것은 `CMPedometerData`의
/// `currentCadence`(초당 발걸음)인데 어느 플러그인도 이걸 내주지 않는다.
/// 걸음 수를 시간으로 나눠 직접 계산할 수도 있지만, 애플이 이미 보정해 주는
/// 값을 두고 우리가 다시 추정할 이유가 없다.
///
/// **없어도 러닝은 된다.** 시뮬레이터에는 만보기 하드웨어가 없고, 사용자가
/// 모션 권한을 거부할 수도 있다. 그런 경우 이 채널은 그냥 아무것도 보내지
/// 않는다 — 기능 저하이지 실패가 아니므로 에러로 만들지 않는다.
class CadencePlugin: NSObject, FlutterStreamHandler {
  static let channelName = "goingon/cadence"

  private let pedometer = CMPedometer()
  private var sink: FlutterEventSink?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterEventChannel(
      name: channelName, binaryMessenger: registrar.messenger())
    channel.setStreamHandler(CadencePlugin())
  }

  func onListen(withArguments _: Any?, eventSink: @escaping FlutterEventSink)
    -> FlutterError?
  {
    sink = eventSink

    // 하드웨어나 권한이 없으면 조용히 아무것도 보내지 않는다.
    // 에러를 보내면 Dart 쪽에서 러닝을 방해하는 처리를 하게 된다
    guard CMPedometer.isCadenceAvailable() else { return nil }

    pedometer.startUpdates(from: Date()) { [weak self] data, error in
      guard let self, error == nil, let cadence = data?.currentCadence else {
        return
      }
      // CMPedometer는 **초당** 발걸음을 준다. 사람이 말하는 단위는 분당이라
      // 여기서 한 번만 바꾼다 — Dart 쪽에서 또 바꾸면 단위가 갈린다
      let spm = cadence.doubleValue * 60.0
      DispatchQueue.main.async { self.sink?(spm) }
    }
    return nil
  }

  func onCancel(withArguments _: Any?) -> FlutterError? {
    pedometer.stopUpdates()
    sink = nil
    return nil
  }
}
