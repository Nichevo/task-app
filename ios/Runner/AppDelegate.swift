import EventKit
import Flutter
import UIKit
import Vision
import UserNotifications
import flutter_local_notifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Upcoming events and Photo of a list on iPad (item 90).
  private let native = NativeChannel()

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
    // Item 90: the iPad side of lib/native.dart (Android has it in MainActivity.kt).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TaskBlocksNative") {
      let native = self.native
      FlutterMethodChannel(name: "app.taskblocks/native", binaryMessenger: registrar.messenger())
        .setMethodCallHandler { call, result in native.handle(call, result: result) }
    }
  }
}

/// The phone calendar (EventKit) and reading a photo of a list (Vision), for lib/native.dart.
/// Shared text and place reminders stay Android-only, so those calls answer "not implemented".
final class NativeChannel {
  private var store = EKEventStore()

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "calendarPermission":
      askCalendar(result)
    case "calendars":
      result(store.calendars(for: .event).map {
        ["id": $0.calendarIdentifier, "name": $0.title, "account": $0.source?.title ?? ""]
      })
    case "events":
      result(events(args))
    case "recognizeText":
      recognizeText(args["path"] as? String, result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func askCalendar(_ result: @escaping FlutterResult) {
    let done: (Bool, Error?) -> Void = { ok, _ in
      DispatchQueue.main.async {
        // A store made before access was given doesn't see the calendars.
        if ok { self.store = EKEventStore() }
        result(ok)
      }
    }
    if #available(iOS 17.0, *) {
      if EKEventStore.authorizationStatus(for: .event) == .fullAccess { return result(true) }
      store.requestFullAccessToEvents(completion: done)
    } else {
      if EKEventStore.authorizationStatus(for: .event) == .authorized { return result(true) }
      store.requestAccess(to: .event, completion: done)
    }
  }

  private func events(_ args: [String: Any]) -> [[String: Any]] {
    let from = Date(timeIntervalSince1970: ((args["from"] as? NSNumber)?.doubleValue ?? 0) / 1000)
    let to = Date(timeIntervalSince1970: ((args["to"] as? NSNumber)?.doubleValue ?? 0) / 1000)
    guard to > from else { return [] }
    let ids = Set(args["calendars"] as? [String] ?? [])
    var calendars: [EKCalendar]? = nil
    if !ids.isEmpty {
      calendars = store.calendars(for: .event).filter { ids.contains($0.calendarIdentifier) }
      if calendars!.isEmpty { return [] }
    }
    let found = store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: calendars))
    return found.sorted { $0.startDate < $1.startDate }.map { e -> [String: Any] in
      [
        "id": e.eventIdentifier ?? UUID().uuidString,
        "calendarId": e.calendar?.calendarIdentifier ?? "",
        "title": e.title ?? "(No title)",
        "start": Int64(e.startDate.timeIntervalSince1970 * 1000),
        "allDay": e.isAllDay,
        "location": (e.location as Any?) ?? NSNull(),
      ]
    }
  }

  /// The lines of writing in a photo, top to bottom, read on the iPad.
  private func recognizeText(_ path: String?, _ result: @escaping FlutterResult) {
    guard let path, let image = UIImage(contentsOfFile: path), let cg = image.cgImage else {
      return result([String]())
    }
    let orientation = NativeChannel.orientation(image.imageOrientation)
    DispatchQueue.global(qos: .userInitiated).async {
      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = true
      do {
        try VNImageRequestHandler(cgImage: cg, orientation: orientation).perform([request])
        let lines = (request.results ?? [])
          .sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
          .compactMap { $0.topCandidates(1).first?.string }
        DispatchQueue.main.async { result(lines) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "recognizeText", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  private static func orientation(_ o: UIImage.Orientation) -> CGImagePropertyOrientation {
    switch o {
    case .up: return .up
    case .down: return .down
    case .left: return .left
    case .right: return .right
    case .upMirrored: return .upMirrored
    case .downMirrored: return .downMirrored
    case .leftMirrored: return .leftMirrored
    case .rightMirrored: return .rightMirrored
    @unknown default: return .up
    }
  }
}
