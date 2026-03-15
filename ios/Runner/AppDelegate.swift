import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let screenshotProtectionChannel = "ranksprint/screenshot_protection"
  private weak var protectedWindow: UIWindow?
  private var captureObserver: NSObjectProtocol?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let didFinishLaunching = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    guard let controller = window?.rootViewController as? FlutterViewController else {
      return didFinishLaunching
    }

    protectedWindow = window

    let channel = FlutterMethodChannel(
      name: screenshotProtectionChannel,
      binaryMessenger: controller.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "setEnabled" else {
        result(FlutterMethodNotImplemented)
        return
      }

      guard
        let args = call.arguments as? [String: Any],
        let enabled = args["enabled"] as? Bool
      else {
        result(
          FlutterError(
            code: "INVALID_ARGS",
            message: "Expected a boolean 'enabled' argument.",
            details: nil
          )
        )
        return
      }

      self?.setScreenshotProtectionEnabled(enabled)
      result(nil)
    }

    return didFinishLaunching
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  private func setScreenshotProtectionEnabled(_ enabled: Bool) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }

      self.protectedWindow?.isHidden = false

      if enabled {
        self.protectedWindow?.layer.superlayer?.addSublayer(CALayer())

        if #available(iOS 13.0, *) {
          if self.captureObserver == nil {
            self.captureObserver = NotificationCenter.default.addObserver(
              forName: UIScreen.capturedDidChangeNotification,
              object: nil,
              queue: .main
            ) { [weak self] _ in
              self?.protectedWindow?.isHidden = UIScreen.main.isCaptured
            }
          }

          self.protectedWindow?.isHidden = UIScreen.main.isCaptured
        }
      } else {
        if let observer = self.captureObserver {
          NotificationCenter.default.removeObserver(observer)
          self.captureObserver = nil
        }

        self.protectedWindow?.isHidden = false
      }
    }
  }
}
