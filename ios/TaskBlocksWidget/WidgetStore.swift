import Foundation
import SwiftUI

// Item 79: what the app shares with the home screen widgets (lib/home_widgets.dart writes it as
// `widget_data` into the shared app group). The same JSON the Android widgets read
// (android/.../WidgetData.kt), so both stay in step.

struct WStep {
  let id: String
  let title: String
  let done: Bool
  let stage: String?
  let since: Date?
}

struct WStage {
  let id: String
  let name: String
  let colour: Color?
  let limit: Int?
}

struct WTask {
  let id: String
  let title: String
  let cat: String?
  let start: Date
  let due: Date?
  let locked: Bool
  let star: Bool
  var steps: [WStep] = []
  var stage: String? = nil
  var since: Date? = nil
  var box: String? = nil
  var snoozed = false
  var worked: Set<String> = []
  var streak = 0
  var streakUnit = "day"
}

struct AddedDone {
  var added: [Int] = []
  var done: [Int] = []
  var open: [Int] = []
}

struct Burn {
  var from = ""
  var end = ""
  var total = 1.0
  var left: [Double] = []
  var projected: String? = nil
  var summary = ""
}

struct Snapshot {
  var hasData = false
  var hoursToRed = 72.0
  var byDue = true
  var categories: [(id: String, name: String)] = []
  /** Every open task the app sent, snoozed board tasks too. */
  var all: [WTask] = []
  var habits: [WTask] = []
  var stages: [WStage] = []
  var boxes: [String: String] = [:]
  var dueDays: [String: (n: Int, faded: Bool)] = [:]
  var doneThisWeek = 0
  var streak = 0
  var addedDone: [String: AddedDone] = [:]
  var burn: [String: Burn] = [:]

  /** Open tasks that aren't snoozed: what the list widgets show. */
  var tasks: [WTask] { all.filter { !$0.snoozed } }

  func categoryName(_ id: String?) -> String? { categories.first { $0.id == id }?.name }
  func task(_ id: String?) -> WTask? { all.first { $0.id == id } }
  func stage(_ id: String?) -> WStage? { stages.first { $0.id == id } }

  func nextStage(_ id: String?) -> WStage? {
    guard let i = stages.firstIndex(where: { $0.id == id }), i + 1 < stages.count else { return nil }
    return stages[i + 1]
  }

  func boardTasks(_ stageId: String, cat: String?) -> [WTask] {
    all.filter { $0.stage == stageId && (cat == nil || $0.cat == cat) }
  }

  func boardSteps(_ stageId: String, cat: String?) -> [(WTask, WStep)] {
    all.filter { cat == nil || $0.cat == cat }.flatMap { t in t.steps.filter { $0.stage == stageId }.map { (t, $0) } }
  }

  // MARK: Reading

  static var defaults: UserDefaults? { AppGroup.id.flatMap { UserDefaults(suiteName: $0) } }

  static func load() -> Snapshot {
    var s = Snapshot()
    guard let d = defaults, let raw = d.string(forKey: "widget_data"),
      let root = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any]
    else { return s }
    s.hasData = true

    // Things done on a widget that the app hasn't picked up yet (item 79, step B writes them).
    let done = Set(array(d, "widget_done").compactMap { $0["id"] as? String })
    let snoozed = Set(array(d, "widget_snoozed").compactMap { $0["id"] as? String })
    let stepTicks = Set(array(d, "widget_steps").map { "\(str($0["task"]))/\(str($0["step"]))" })
    var moves: [String: (String, Date)] = [:]
    for o in array(d, "widget_moves") {
      let key = o["step"] != nil ? "\(str(o["task"]))/\(str(o["step"]))" : str(o["task"])
      moves[key] = (str(o["stage"]), date(o["at"]) ?? Date())
    }
    var workedTicks: [(String, String, Bool)] = []
    for o in array(d, "widget_worked") {
      workedTicks.append((str(o["id"]), str(o["day"]), (o["on"] as? Bool) ?? true))
    }
    func worked(_ id: String, _ o: [String: Any]) -> Set<String> {
      var w = Set((o["worked"] as? [String]) ?? [])
      for (tid, day, on) in workedTicks where tid == id {
        if on { w.insert(day) } else { w.remove(day) }
      }
      return w
    }

    s.hoursToRed = (root["hoursToRed"] as? NSNumber)?.doubleValue ?? 72
    s.byDue = (root["colourByDue"] as? Bool) ?? true
    s.categories = ((root["categories"] as? [[String: Any]]) ?? []).map { (str($0["id"]), str($0["name"])) }
    for o in (root["tasks"] as? [[String: Any]]) ?? [] {
      let id = str(o["id"])
      if done.contains(id) || snoozed.contains(id) { continue }
      let steps: [WStep] = ((o["steps"] as? [[String: Any]]) ?? []).map { st in
        let sid = str(st["id"])
        let moved = moves["\(id)/\(sid)"]
        return WStep(
          id: sid, title: str(st["title"]),
          done: ((st["done"] as? Bool) ?? false) || stepTicks.contains("\(id)/\(sid)"),
          stage: moved?.0 ?? (st["stage"] as? String), since: moved?.1 ?? date(st["since"]))
      }
      let moved = moves[id]
      var t = WTask(
        id: id, title: str(o["title"]), cat: o["cat"] as? String, start: date(o["start"]) ?? Date(),
        due: date(o["due"]), locked: (o["locked"] as? Bool) ?? false, star: (o["star"] as? Bool) ?? false)
      t.steps = steps
      t.stage = moved?.0 ?? (o["stage"] as? String)
      t.since = moved?.1 ?? date(o["since"])
      t.box = o["box"] as? String
      t.snoozed = (o["snoozed"] as? Bool) ?? false
      t.worked = worked(id, o)
      s.all.append(t)
    }
    for o in (root["habits"] as? [[String: Any]]) ?? [] {
      let id = str(o["id"])
      // `locked` here means "not due today" (enough this week already), as on Android.
      var t = WTask(
        id: id, title: str(o["title"]), cat: nil, start: Date(), due: nil,
        locked: !((o["due"] as? Bool) ?? true), star: false)
      t.worked = worked(id, o)
      t.streak = (o["streak"] as? NSNumber)?.intValue ?? 0
      t.streakUnit = (o["unit"] as? String) ?? "day"
      s.habits.append(t)
    }
    s.stages = ((root["stages"] as? [[String: Any]]) ?? []).map {
      WStage(
        id: str($0["id"]), name: str($0["name"]),
        colour: ($0["colour"] as? NSNumber).map { argb($0.int64Value) },
        limit: ($0["limit"] as? NSNumber)?.intValue)
    }
    s.boxes = (root["boxes"] as? [String: String]) ?? [:]
    for (k, v) in (root["dueDays"] as? [String: [String: Any]]) ?? [:] {
      s.dueDays[k] = ((v["n"] as? NSNumber)?.intValue ?? 0, (v["faded"] as? Bool) ?? false)
    }
    let stats = (root["stats"] as? [String: Any]) ?? [:]
    s.doneThisWeek = (stats["week"] as? NSNumber)?.intValue ?? 0
    s.streak = (stats["streak"] as? NSNumber)?.intValue ?? 0
    for (k, v) in (root["addedDone"] as? [String: [String: Any]]) ?? [:] {
      s.addedDone[k] = AddedDone(added: ints(v["added"]), done: ints(v["done"]), open: ints(v["open"]))
    }
    for (k, v) in (root["burn"] as? [String: [String: Any]]) ?? [:] {
      s.burn[k] = Burn(
        from: str(v["from"]), end: str(v["end"]), total: max((v["total"] as? NSNumber)?.doubleValue ?? 1, 1),
        left: ((v["left"] as? [NSNumber]) ?? []).map { $0.doubleValue }, projected: v["projected"] as? String,
        summary: str(v["summary"]))
    }
    return s
  }

  private static func array(_ d: UserDefaults, _ key: String) -> [[String: Any]] {
    guard let raw = d.string(forKey: key),
      let a = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [[String: Any]]
    else { return [] }
    return a
  }
}

private func str(_ v: Any?) -> String { (v as? String) ?? "" }

private func date(_ v: Any?) -> Date? {
  guard let n = v as? NSNumber else { return nil }
  return Date(timeIntervalSince1970: n.doubleValue / 1000)
}

private func ints(_ v: Any?) -> [Int] { ((v as? [NSNumber]) ?? []).map { $0.intValue } }

/** A Flutter colour value (0xAARRGGBB). */
func argb(_ v: Int64) -> Color {
  let u = UInt32(truncatingIfNeeded: v)
  return Color(
    .sRGB, red: Double((u >> 16) & 0xFF) / 255, green: Double((u >> 8) & 0xFF) / 255,
    blue: Double(u & 0xFF) / 255, opacity: Double((u >> 24) & 0xFF) / 255)
}

// MARK: - Shared helpers

enum W {
  static let day: TimeInterval = 86_400

  static let keyFormat: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f
  }()

  static func key(_ d: Date) -> String { keyFormat.string(from: d) }

  /** The seven days (yyyy-MM-dd) of the week holding [now], Monday first. */
  static func week(_ now: Date) -> [String] {
    var cal = Calendar.current
    cal.firstWeekday = 2
    let start = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
    return (0..<7).map { key(cal.date(byAdding: .day, value: $0, to: start) ?? start) }
  }

  /** Same green-to-red colour as the app (lib/widgets/task_colors.dart). */
  static func colour(_ snap: Snapshot, _ t: WTask, now: Date) -> Color {
    if t.locked { return Color(red: 0xD5 / 255, green: 0xD5 / 255, blue: 0xD5 / 255) }
    let age = now.timeIntervalSince(t.start) / 3600
    let span = snap.byDue && t.due != nil ? t.due!.timeIntervalSince(t.start) / 3600 : snap.hoursToRed
    let p = span <= 0 ? 1 : min(max(age / span, 0), 1)
    return Color(hue: 120 * (1 - p) / 360, saturation: 0.6, brightness: 0.88)
  }

  /** "14:30" today, "Tomorrow", else "Fri 7 Nov". */
  static func dueLabel(_ due: Date, now: Date) -> String {
    let cal = Calendar.current
    if cal.isDate(due, inSameDayAs: now) { return due.formatted(date: .omitted, time: .shortened) }
    if let tomorrow = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(due, inSameDayAs: tomorrow) {
      return "Tomorrow"
    }
    return due.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
  }

  /** "overdue 2 days", "due Fri", or "". */
  static func dueText(_ due: Date?, now: Date) -> String {
    guard let due else { return "" }
    if due < now {
      let cal = Calendar.current
      let days = cal.dateComponents([.day], from: cal.startOfDay(for: due), to: cal.startOfDay(for: now)).day ?? 0
      return days <= 0 ? "overdue" : days == 1 ? "overdue 1 day" : "overdue \(days) days"
    }
    return "due " + dueLabel(due, now: now)
  }

  /** How long something has been in its stage: "5 h", "3 days". */
  static func spell(_ since: Date?, now: Date) -> String {
    guard let since else { return "" }
    let h = Int(now.timeIntervalSince(since) / 3600)
    return h < 1 ? "under an hour" : h < 24 ? "\(h) h" : h < 48 ? "1 day" : "\(h / 24) days"
  }

  static func join(_ parts: String...) -> String { parts.filter { !$0.isEmpty }.joined(separator: " · ") }

  /** A link that opens the app; the `homeWidget` mark makes the home_widget plugin pass it on. */
  static func link(_ host: String, _ query: [String: String?] = [:]) -> URL {
    var c = URLComponents()
    c.scheme = "taskblocks"
    c.host = host
    var items = query.compactMap { k, v in v.map { URLQueryItem(name: k, value: $0) } }
    items.append(URLQueryItem(name: "homeWidget", value: nil))
    c.queryItems = items
    return c.url ?? URL(string: "taskblocks://home?homeWidget")!
  }

  static func open(_ id: String) -> URL { link("open", ["id": id]) }

  /** A light tile colour for a stage: its own colour washed out, else one from a set. */
  static func tile(_ s: WStage, _ i: Int) -> Color {
    let set: [Color] = [
      Color(red: 0.89, green: 0.93, blue: 0.98), Color(red: 0.90, green: 0.96, blue: 0.91),
      Color(red: 1.0, green: 0.91, blue: 0.66), Color(red: 0.99, green: 0.89, blue: 0.86),
      Color(red: 0.93, green: 0.93, blue: 0.95),
    ]
    if let c = s.colour { return c.opacity(0.25) }
    return set[i % set.count]
  }

  static let amber = Color(red: 0.90, green: 0.32, blue: 0.0)
  static let blue = Color(red: 0.10, green: 0.37, blue: 0.71)
}
