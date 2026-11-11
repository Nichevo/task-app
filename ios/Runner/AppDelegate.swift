import AppIntents
import CoreLocation
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
    // Place reminders: iPadOS wakes the app in the background on arriving at or leaving a saved
    // place, and the watcher has to be listening by the end of launch to hear about it.
    PlaceWatcher.shared.start()
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
/// Also shared text (from the Add to Task Blocks action below) and place reminders (PlaceWatcher).
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
    case "takeShared":
      result(SharedInbox.take())
    case "setPlaces":
      result(
        PlaceWatcher.shared.save(
          places: args["places"] as? String ?? "[]", summary: args["summary"] as? Bool ?? false,
          dir: args["dir"] as? String ?? ""))
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

// MARK: - Add to Task Blocks: Siri, Shortcuts and the Share sheet

/// Text handed to the app by the Add to Task Blocks action, waiting for the app to show it
/// (lib/native.dart takeShared, as Android's Share and "note to self").
enum SharedInbox {
  private static let key = "shared_inbox"

  static func add(_ text: String, subject: String? = nil, voice: Bool) {
    var list = UserDefaults.standard.array(forKey: key) as? [[String: Any]] ?? []
    var item: [String: Any] = ["text": text, "voice": voice]
    if let subject, !subject.isEmpty { item["subject"] = subject }
    list.append(item)
    UserDefaults.standard.set(list, forKey: key)
  }

  /// Everything waiting, as one piece of text (several become one line each), then forgets it.
  static func take() -> [String: Any]? {
    let list = UserDefaults.standard.array(forKey: key) as? [[String: Any]] ?? []
    UserDefaults.standard.removeObject(forKey: key)
    let texts = list.compactMap { $0["text"] as? String }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    if texts.isEmpty { return nil }
    if list.count == 1 { return list[0] }
    return ["text": texts.joined(separator: "\n"), "voice": list.allSatisfy { ($0["voice"] as? Bool) ?? false }]
  }
}

/// "Add a task in Task Blocks": Siri asks what the task is, or a shortcut passes text in (a Share
/// sheet shortcut passes what was shared). The app opens with the task ready to check and save.
@available(iOS 16.0, *)
struct AddTaskIntent: AppIntent {
  static var title: LocalizedStringResource { "Add to Task Blocks" }
  static var description: IntentDescription { IntentDescription("Adds a task to Task Blocks. Several lines become several tasks.") }
  static var openAppWhenRun: Bool { true }

  @Parameter(title: "Task", requestValueDialog: IntentDialog("What's the task?"))
  var text: String

  @Parameter(title: "Spoken", default: false)
  var spoken: Bool

  func perform() async throws -> some IntentResult {
    SharedInbox.add(text, voice: spoken)
    return .result()
  }
}

@available(iOS 16.0, *)
struct TaskBlocksShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: AddTaskIntent(spoken: true),
      phrases: [
        "Add a task in \(.applicationName)",
        "New task in \(.applicationName)",
        "Remind me in \(.applicationName)",
      ],
      shortTitle: "Add a task",
      systemImageName: "plus.circle")
  }
}

@available(iOS 16.0, *)
extension AddTaskIntent {
  init(spoken: Bool) {
    self.init()
    self.spoken = spoken
  }
}

// MARK: - Place reminders (item 33 on iPad)

/// Watches the saved places with iPadOS region monitoring (up to 20), also while the app is
/// closed, and on arriving or leaving reads the saved tasks.json and shows the reminders, as
/// PlaceReceiver.kt does on Android.
final class PlaceWatcher: NSObject, CLLocationManagerDelegate {
  static let shared = PlaceWatcher()

  private let manager = CLLocationManager()
  private let prefs = UserDefaults.standard
  private let prefix = "taskblocks.place."

  func start() {
    manager.delegate = self
  }

  /// Saves what the app sent and watches those places. False without "Always" location access.
  func save(places: String, summary: Bool, dir: String) -> Bool {
    prefs.set(places, forKey: "place_places")
    prefs.set(summary, forKey: "place_summary")
    prefs.set(dir, forKey: "place_dir")
    return register()
  }

  private func places() -> [[String: Any]] {
    guard let raw = prefs.string(forKey: "place_places"),
      let list = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [[String: Any]]
    else { return [] }
    return list
  }

  private func register() -> Bool {
    for r in manager.monitoredRegions where r.identifier.hasPrefix(prefix) { manager.stopMonitoring(for: r) }
    let list = places()
    if list.isEmpty { return true }
    guard manager.authorizationStatus == .authorizedAlways,
      CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self)
    else { return false }
    for p in list.prefix(20) {
      guard let id = p["id"] as? String, let lat = (p["lat"] as? NSNumber)?.doubleValue,
        let lng = (p["lng"] as? NSNumber)?.doubleValue
      else { continue }
      let radius = min(max((p["radius"] as? NSNumber)?.doubleValue ?? 150, 100), manager.maximumRegionMonitoringDistance)
      let region = CLCircularRegion(
        center: CLLocationCoordinate2D(latitude: lat, longitude: lng), radius: radius, identifier: prefix + id)
      region.notifyOnEntry = true
      region.notifyOnExit = true
      manager.startMonitoring(for: region)
    }
    return true
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    if manager.authorizationStatus == .authorizedAlways { _ = register() }
  }

  func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
    fired(region, arriving: true)
  }

  func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
    fired(region, arriving: false)
  }

  private func fired(_ region: CLRegion, arriving: Bool) {
    guard region.identifier.hasPrefix(prefix) else { return }
    let id = String(region.identifier.dropFirst(prefix.count))
    guard let place = places().first(where: { ($0["id"] as? String) == id }), let name = place["name"] as? String
    else { return }
    remind(name, arriving: arriving)
  }

  /// The app's folder moves when iPadOS updates the app, so find tasks.json under today's one.
  private func tasksFile() -> URL? {
    guard let dir = prefs.string(forKey: "place_dir"), !dir.isEmpty else { return nil }
    var url = URL(fileURLWithPath: dir).appendingPathComponent("tasks.json")
    if !FileManager.default.fileExists(atPath: url.path), let r = dir.range(of: "/Library/") {
      url = URL(fileURLWithPath: NSHomeDirectory() + String(dir[r.lowerBound...])).appendingPathComponent("tasks.json")
    }
    return FileManager.default.fileExists(atPath: url.path) ? url : nil
  }

  private func remind(_ place: String, arriving: Bool) {
    guard let file = tasksFile(), let data = try? Data(contentsOf: file),
      let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let active = root["active"] as? [[String: Any]]
    else { return }
    let now = Date()
    let cal = Calendar.current
    let endOfToday = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
    let today = PlaceWatcher.dayKey(now)
    var fired = Set(prefs.stringArray(forKey: "place_fired") ?? [])
    var dueToday: [String] = []
    for o in active {
      if let snoozed = PlaceWatcher.parse(o["snoozedUntil"]), snoozed > now { continue }
      let due = PlaceWatcher.parse(o["dueAt"])
      let title = o["title"] as? String ?? ""
      if let due, due < endOfToday { dueToday.append(title) }
      guard let p = o["place"] as? String, p.caseInsensitiveCompare(place) == .orderedSame else { continue }
      let leave = o["placeLeave"] as? Bool ?? false
      if leave == arriving { continue }
      // With a due date: on the day it is due, and each day while overdue. Without one: once.
      if let due, due >= endOfToday { continue }
      let tid = o["id"] as? String ?? title
      let key = due == nil ? "\(tid)|once|\(leave)" : "\(tid)|\(today)|\(leave)"
      if !fired.insert(key).inserted { continue }
      notify(id: "place-\(tid)", title: arriving ? "At \(place)" : "Leaving \(place)", body: title)
    }
    if arriving, prefs.bool(forKey: "place_summary"), !dueToday.isEmpty, fired.insert("summary|\(place)|\(today)").inserted {
      let names = dueToday.prefix(5).joined(separator: ", ") + (dueToday.count > 5 ? "…" : "")
      let n = dueToday.count
      notify(id: "place-summary-\(place)", title: "At \(place): \(n) task\(n == 1 ? "" : "s") for today", body: names)
    }
    // Forget days gone by (keep the "once" keys).
    prefs.set(fired.filter { !$0.contains("|20") || $0.contains("|\(today)") }.sorted(), forKey: "place_fired")
  }

  private func notify(id: String, title: String, body: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
  }

  private static func dayKey(_ d: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: d)
  }

  /// The app saves local times without a zone ("2026-11-11T09:00:00.000") and UTC times with a Z.
  static func parse(_ v: Any?) -> Date? {
    guard var s = v as? String, !s.isEmpty, s != "null" else { return nil }
    let utc = s.hasSuffix("Z")
    if utc { s.removeLast() }
    if let dot = s.firstIndex(of: ".") { s = String(s[..<dot]) }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    if utc { f.timeZone = TimeZone(identifier: "UTC") }
    return f.date(from: s)
  }
}
