import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// APNs 등록 결과. **이걸 붙잡아 두는 이유**가 있다.
  ///
  /// firebase_messaging 플러그인은 등록 실패를 `NSLog` 한 줄로만 남기고
  /// Dart로 올려보내지 않는다. 그래서 앱은 "토큰을 못 받았다"까지만 알고
  /// **왜** 못 받았는지는 모른다. 실기기 로그를 볼 수 없는 상황에서는
  /// 그 한 줄이 유일한 단서인데 손에 닿지 않는다 — 실제로 그 상태로
  /// 오래 헤맸다(2026-09-11).
  ///
  /// 플러그인이 AppDelegate 메서드를 스위즐링하지만 원본 구현을 함께
  /// 부르므로, 여기 적어 두면 양쪽 다 동작한다.
  static var apnsError: String?
  static var apnsRegistered = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    AppDelegate.apnsRegistered = true
    AppDelegate.apnsError = nil
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    let ns = error as NSError
    AppDelegate.apnsRegistered = false
    AppDelegate.apnsError = "\(ns.domain) \(ns.code): \(ns.localizedDescription)"
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // 케이던스는 pub.dev 플러그인이 안 내줘서 직접 붙인다 (CadencePlugin 주석 참조)
    CadencePlugin.register(
      with: engineBridge.pluginRegistry.registrar(
        forPlugin: "GoingOnCadencePlugin")!)

    // APNs 등록 결과를 Dart가 물어볼 수 있게 한다 (설정 화면에서 보여준다)
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "GoingOnPushDiag")!
    let channel = FlutterMethodChannel(
      name: "goingon/push_diag", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      if call.method == "apnsStatus" {
        result([
          "registered": AppDelegate.apnsRegistered,
          "error": AppDelegate.apnsError as Any,
        ])
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
