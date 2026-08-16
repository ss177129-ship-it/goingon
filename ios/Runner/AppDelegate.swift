import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // 케이던스는 pub.dev 플러그인이 안 내줘서 직접 붙인다 (CadencePlugin 주석 참조)
    CadencePlugin.register(
      with: engineBridge.pluginRegistry.registrar(
        forPlugin: "GoingOnCadencePlugin")!)
  }
}
