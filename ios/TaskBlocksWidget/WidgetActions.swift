import AppIntents
import Foundation
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
    return .result()
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
