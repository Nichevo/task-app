import AppIntents
import Foundation
import UserNotifications
import WidgetKit

// Item 79, step B: buttons on the iPad widgets (iPadOS 17 interactive widgets). Each one adds
// what was done to the same lists the Android widget buttons use (widget_done, widget_snoozed,
// widget_steps, widget_moves, widget_worked). The widgets show it straight away (WidgetStore
// reads the lists), and the app applies it the next time it opens (HomeWidgets.take...).

enum Pending {
  static func append(_ key: String, _ item: [String: Any]) {
    guard let d = Snapshot.defaults else { return }
    var list: [[String: Any]] = []
    if let raw = d.string(forKey: key),
      let a = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [[String: Any]]
    {
      list = a
    }
    list.append(item)
    if let data = try? JSONSerialization.data(withJSONObject: list), let s = String(data: data, encoding: .utf8) {
      d.set(s, forKey: key)
    }
  }

  static var nowMs: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
}

/** Ticks a task off; the app archives it when it next opens. */
struct TickTaskAction: AppIntent {
  static var title: LocalizedStringResource { "Tick off" }
  @Parameter(title: "Task") var id: String

  init() {}
  init(id: String) { self.id = id }

  func perform() async throws -> some IntentResult {
    Pending.append("widget_done", ["id": id, "at": Pending.nowMs])
    return .result()
  }
}

/** Snoozes a task until 8am tomorrow, as on Android. */
struct SnoozeTaskAction: AppIntent {
  static var title: LocalizedStringResource { "Snooze until tomorrow" }
  @Parameter(title: "Task") var id: String

  init() {}
  init(id: String) { self.id = id }

  func perform() async throws -> some IntentResult {
    let cal = Calendar.current
    let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date()
    let until = cal.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    Pending.append("widget_snoozed", ["id": id, "until": Int64(until.timeIntervalSince1970 * 1000)])
    SnoozeReminder.add(task: id, title: Snapshot.load().task(id)?.title ?? "", at: until)
    return .result()
  }
}

/**
 Reminds again when a widget snooze ends, even if the app isn't opened before then (the app
 replaces it with its own reminder when it next sets them all). Shaped like the app's reminders
 (flutter_local_notifications), so its Done and snooze buttons and a tap work the same.
 */
enum SnoozeReminder {
  static func add(task: String, title: String, at: Date) {
    guard !title.isEmpty, at > Date() else { return }
    // Below the ids the app uses for tasks and steps, the same for a task each time.
    var h: UInt32 = 5381
    for b in task.utf8 { h = (h &* 33) &+ UInt32(b) }
    let id = -600_000_000 - Int(h & 0x0fff_ffff)
    let payload = (try? JSONSerialization.data(withJSONObject: ["task": task, "dir": ""]))
      .flatMap { String(data: $0, encoding: .utf8) } ?? ""
    let content = UNMutableNotificationContent()
    content.title = "Snoozed task"
    content.body = title
    content.sound = .default
    content.categoryIdentifier = "due"
    content.userInfo = [
      "NotificationId": id, "payload": payload, "presentAlert": true, "presentSound": true,
      "presentBadge": true, "presentBanner": true, "presentList": true,
    ]
    let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: at)
    let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: String(id), content: content, trigger: trigger))
  }
}

/** Ticks one checklist step. */
struct TickStepAction: AppIntent {
  static var title: LocalizedStringResource { "Tick step" }
  @Parameter(title: "Task") var task: String
  @Parameter(title: "Step") var step: String

  init() {}
  init(task: String, step: String) {
    self.task = task
    self.step = step
  }

  func perform() async throws -> some IntentResult {
    Pending.append("widget_steps", ["task": task, "step": step])
    return .result()
  }
}

/** Moves a board task, or one of its board steps, to another stage. */
struct MoveAction: AppIntent {
  static var title: LocalizedStringResource { "Move to the next stage" }
  @Parameter(title: "Task") var task: String
  @Parameter(title: "Step") var step: String?
  @Parameter(title: "Stage") var stage: String

  init() {}
  init(task: String, step: String? = nil, stage: String) {
    self.task = task
    self.step = step
    self.stage = stage
  }

  func perform() async throws -> some IntentResult {
    var o: [String: Any] = ["task": task, "stage": stage, "at": Pending.nowMs]
    if let step { o["step"] = step }
    Pending.append("widget_moves", o)
    return .result()
  }
}

/** Ticks (or unticks) a day as worked on, for tasks and habits. */
struct WorkedDayAction: AppIntent {
  static var title: LocalizedStringResource { "Worked on it today" }
  @Parameter(title: "Task") var id: String
  @Parameter(title: "Day") var day: String
  @Parameter(title: "On") var on: Bool

  init() {}
  init(id: String, day: String, on: Bool) {
    self.id = id
    self.day = day
    self.on = on
  }

  func perform() async throws -> some IntentResult {
    Pending.append("widget_worked", ["id": id, "day": day, "on": on])
    return .result()
  }
}

// MARK: - Item 108: the Focus timer and Focus mode widgets' buttons

/**
 One press on the Focus timer widget: start, pause, resume, add (+5), skip (the break) or stop.
 The widget moves its own copy of the timer on ('focus_local') and notes the press
 ('widget_focus'); the app does the same presses, in order, when it next opens. Until then the
 round's end reminder is the widget's (the app's own one is taken off).
 */
struct FocusOpAction: AppIntent {
  static var title: LocalizedStringResource { "Focus timer" }
  @Parameter(title: "Button") var op: String
  @Parameter(title: "Task") var task: String

  init() {}
  init(op: String, task: String = "") {
    self.op = op
    self.task = task
  }

  func perform() async throws -> some IntentResult {
    FocusOps.apply(op: op, task: task.isEmpty ? nil : task)
    WidgetCenter.shared.reloadAllTimelines()
    return .result()
  }
}

/** A mode picked on the Focus mode widget: shown on the widgets at once, applied by the app when it opens. */
struct ModePickAction: AppIntent {
  static var title: LocalizedStringResource { "Switch focus mode" }
  @Parameter(title: "Mode") var mode: String

  init() {}
  init(mode: String) { self.mode = mode }

  func perform() async throws -> some IntentResult {
    let snap = Snapshot.load()
    let now = Date()
    // Until the app's timeline next changes mode by itself (the app works it out exactly).
    var until: Date? = nil
    if let i = snap.modeLine.firstIndex(where: { $0.start <= now && now < $0.end }) {
      var j = i
      while j + 1 < snap.modeLine.count && snap.modeLine[j + 1].id == snap.modeLine[i].id { j += 1 }
      if j + 1 < snap.modeLine.count { until = snap.modeLine[j].end }
    }
    Pending.append("widget_mode", ["mode": mode, "at": Pending.nowMs])
    let local: [String: Any] = ["mode": mode, "until": until.map { Int64($0.timeIntervalSince1970 * 1000) } ?? 0]
    if let data = try? JSONSerialization.data(withJSONObject: local), let s = String(data: data, encoding: .utf8) {
      Snapshot.defaults?.set(s, forKey: "widget_mode_local")
    }
    WidgetCenter.shared.reloadAllTimelines()
    return .result()
  }
}

enum FocusOps {
  /** The app's notification id for the end of a round or break (Reminders.focusEndId). */
  static let endId = -950_000_001

  static func ms(_ d: Date) -> Int64 { Int64(d.timeIntervalSince1970 * 1000) }

  static func num(_ v: Any?) -> Int64? { (v as? NSNumber)?.int64Value }

  /** [f] moved on to [now] as the app would, in the same form the app shares it. */
  static func settle(_ f: [String: Any], lengths: [Int], now: Date) -> [String: Any] {
    var probe = Snapshot()
    probe.focusTimer = f
    probe.focusLengths = lengths
    guard let st = probe.focus(at: now) else { return f }
    var o = f
    o["phase"] = st.phase
    o["round"] = st.round
    o["length"] = Int64(st.length.rounded())
    if let e = st.end {
      o["end"] = ms(e)
      o["left"] = nil
    } else {
      o["end"] = nil
      o["left"] = Int64(st.left.rounded())
    }
    if st.ready { o["ready"] = true } else { o["ready"] = nil }
    return o
  }

  static func apply(op: String, task: String?) {
    guard let d = Snapshot.defaults else { return }
    let snap = Snapshot.load()
    let lengths = snap.focusLengths
    let now = Date()
    let cur = snap.focusTimer.map { settle($0, lengths: lengths, now: now) }
    var next: [String: Any]?
    switch op {
    case "start":
      guard let id = task, let t = snap.everything.first(where: { $0.id == id }) else { return }
      next = [
        "task": t.id, "title": t.title,
        "steps": t.steps.map { ["id": $0.id, "title": $0.title, "done": $0.done] as [String: Any] },
        "phase": "focus", "round": 1, "length": lengths[0] * 60,
        "end": ms(now.addingTimeInterval(Double(lengths[0]) * 60)), "today": t.focusToday,
      ]
    case "pause":
      guard var f = cur else { return }
      if let e = num(f["end"]) {
        f["left"] = max(0, (e - ms(now)) / 1000)
        f["end"] = nil
      }
      next = f
    case "resume":
      guard var f = cur else { return }
      if f["end"] == nil {
        let left = (f["left"] as? NSNumber)?.doubleValue ?? (f["length"] as? NSNumber)?.doubleValue ?? 1500
        f["end"] = ms(now.addingTimeInterval(left))
        f["left"] = nil
        f["ready"] = nil
      }
      next = f
    case "add":
      guard var f = cur else { return }
      let length = num(f["length"]) ?? 1500
      if let e = num(f["end"]) {
        f["end"] = e + 300_000
      } else {
        f["left"] = ((f["left"] as? NSNumber)?.int64Value ?? length) + 300
      }
      f["length"] = length + 300
      next = f
    case "skip":
      guard var f = cur else { return }
      let phase = (f["phase"] as? String) ?? "focus"
      if phase == "focus" && f["end"] != nil { return }
      if phase != "focus" { f["round"] = ((f["round"] as? NSNumber)?.intValue ?? 1) + 1 }
      f["phase"] = "focus"
      f["length"] = lengths[0] * 60
      f["end"] = ms(now.addingTimeInterval(Double(lengths[0]) * 60))
      f["left"] = nil
      f["ready"] = nil
      next = f
    case "stop":
      guard cur != nil else { return }
      next = nil
    default:
      return
    }
    var press: [String: Any] = ["op": op, "at": ms(now)]
    if op == "start", let task { press["task"] = task }
    Pending.append("widget_focus", press)
    let saved: [String: Any] = next ?? ["stopped": true]
    if let data = try? JSONSerialization.data(withJSONObject: saved), let s = String(data: data, encoding: .utf8) {
      d.set(s, forKey: "focus_local")
    }
    remind(next, lengths: lengths)
  }

  /**
   The reminder when the round or break ends, shaped like the app's (flutter_local_notifications,
   same id), so a tap opens the timer. The app's own is taken off first; it sets its own again
   when it next opens.
   */
  static func remind(_ f: [String: Any]?, lengths: [Int]) {
    let centre = UNUserNotificationCenter.current()
    centre.removePendingNotificationRequests(withIdentifiers: [String(endId)])
    guard let f, let e = num(f["end"]) else { return }
    let end = Date(timeIntervalSince1970: Double(e) / 1000)
    guard end > Date() else { return }
    let round = (f["round"] as? NSNumber)?.intValue ?? 1
    let title = (f["title"] as? String) ?? ""
    let content = UNMutableNotificationContent()
    if ((f["phase"] as? String) ?? "focus") == "focus" {
      let long = round % max(lengths[3], 1) == 0
      content.title = "Time for a break"
      content.body = "Round \(round) on \"\(title)\" is done. \(long ? lengths[2] : lengths[1]) minutes off."
    } else {
      content.title = "Break's over"
      content.body = "Ready for round \(round + 1) on \"\(title)\"?"
    }
    content.sound = .default
    if #available(iOS 15.0, *) { content.interruptionLevel = .timeSensitive }
    let payload = (try? JSONSerialization.data(withJSONObject: ["focus": true]))
      .flatMap { String(data: $0, encoding: .utf8) } ?? ""
    content.userInfo = [
      "NotificationId": endId, "payload": payload, "presentAlert": true, "presentSound": true,
      "presentBadge": true, "presentBanner": true, "presentList": true,
    ]
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow), repeats: false)
    centre.add(UNNotificationRequest(identifier: String(endId), content: content, trigger: trigger))
  }
}
