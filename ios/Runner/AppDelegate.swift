import Flutter
import UIKit
import UserNotifications
import flutter_local_notifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Lets the Done / snooze buttons on a reminder work while the app is closed.
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    // Shows reminders even while the app is open.
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Tells the Dart side which shared group (app group) the home screen widgets read from.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TaskBlocksWidgets") {
      FlutterMethodChannel(name: "app.taskblocks/widgets", binaryMessenger: registrar.messenger())
        .setMethodCallHandler { call, result in
          switch call.method {
          case "appGroup": result(AppGroup.id)
          default: result(FlutterMethodNotImplemented)
          }
        }
    }
  }
}
