import EventKit
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
  /** When a snooze ends (nil: not snoozed, or an older app version that sent no end). */
  var snoozedUntil: Date? = nil
  var worked: Set<String> = []
  var streak = 0
  var streakUnit = "day"
  /** Item 102: the focus modes this task is hidden in (unless it breaks through). */
  var hide: [String] = []
  /** Item 102, part 4: minutes on the focus timer today. */
  var focusToday = 0
}

/** Item 102, part 4: the focus timer as it stands at a moment (the app's timer moved on). */
struct FocusState {
  var phase: String
  var round: Int
  var end: Date?
  var left: TimeInterval
  var length: TimeInterval
  var ready: Bool
  var running: Bool { end != nil }
  var onBreak: Bool { phase != "focus" }
}

/** Item 102: a focus mode as the widgets see it: its name, colour and what breaks through. */
struct WMode {
  let id: String
  let name: String
  let colour: Color
  var overdue = true
  var due = "today"
  var starred = true
  /** Item 108: the focus timer's own lengths in this mode (focus, short, long, every), if set. */
  var timer: [Int]? = nil

  /** Whether [t] is hidden in this mode at [now] (the app works out the other reasons). */
  func hides(_ t: WTask, now: Date) -> Bool {
    guard t.hide.contains(id) else { return false }
    if let d = t.due {
      if overdue && d < now { return false }
      if let limit = WMode.limit(due, now: now), d < limit { return false }
    }
    if starred && t.star { return false }
    return true
  }

  /** The latest due time that still breaks through (DueWithin in lib/modes.dart). */
  static func limit(_ name: String, now: Date) -> Date? {
    let cal = Calendar.current
    let day = cal.startOfDay(for: now)
    switch name {
    case "off": return nil
    case "twoHours": return now.addingTimeInterval(2 * 3600)
    case "tomorrow": return cal.date(byAdding: .day, value: 2, to: day)
    case "threeDays": return now.addingTimeInterval(3 * 86400)
    case "week": return now.addingTimeInterval(7 * 86400)
    default: return cal.date(byAdding: .day, value: 1, to: day)
    }
  }
}

/** Item 101: a planned time from the Day plan, for the Today's plan widget. */
struct WPlan {
  let id: String
  let step: String?
  let title: String
  let task: String?
  let at: Date
  let end: Date
  /** More of the task's own time is planned later: ticking marks it worked on today. */
  let later: Bool
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
  /** Every open task the app sent, snoozed board tasks too, less what the focus mode hides. */
  var all: [WTask] = []
  /** Item 102: every open task the app sent, whatever the mode. */
  var everything: [WTask] = []
  /** Item 102: the focus modes, and which is in force when (start, end, mode id). */
  var modes: [WMode] = []
  var modeLine: [(start: Date, end: Date, id: String)] = []
  /** Item 108: whether the widgets follow the mode in force (Settings, Focus modes). */
  var follow = true
  /** Item 108: this widget's own choice: nil = follow the mode in force, "all", or a mode id. */
  var pin: String? = nil
  /** Item 108: a mode picked on the Focus mode widget that the app hasn't seen yet. */
  var picked: (id: String, until: Date?)? = nil
  var habits: [WTask] = []
  var stages: [WStage] = []
  var boxes: [String: String] = [:]
  var dueDays: [String: (n: Int, faded: Bool)] = [:]
  var doneThisWeek = 0
  var streak = 0
  var addedDone: [String: AddedDone] = [:]
  var burn: [String: Burn] = [:]
  var plan: [WPlan] = []
  /** Item 102, part 4: the running focus timer as the app shared it, and its lengths
   * (focus, short break, long break minutes, rounds before the long break). */
  var focusTimer: [String: Any]? = nil
  var focusLengths = [25, 5, 15, 4]
  /** Item 108: the lengths set for every mode (focusLengths is the mode in force's own, if it has them). */
  var baseLengths = [25, 5, 15, 4]
  /** Item 101: free time in working hours (the app's view, before calendar events). */
  var planFree: [(start: Date, end: Date)] = []

  /** The same tasks as they stand at [date]: snoozes that have ended by then show again. */
  func at(_ date: Date) -> Snapshot {
    var s = self
    let m = filterMode(at: date)
    s.all = everything.filter { m?.hides($0, now: date) != true }.map { t in
      var t = t
      if let until = t.snoozedUntil { t.snoozed = until > date }
      return t
    }
    return s
  }

  /** Item 108: the same data for a widget with its own focus mode choice. */
  func pinned(_ p: String?) -> Snapshot {
    var s = self
    s.pin = p
    let now = Date()
    let m = s.filterMode(at: now)
    s.all = everything.filter { m?.hides($0, now: now) != true }.map { t in
      var t = t
      if let until = t.snoozedUntil { t.snoozed = until > now }
      return t
    }
    return s
  }

  /** Item 108: the mode a widget filters by at [date]: its own choice, else the mode in force when the widgets follow it. */
  func filterMode(at date: Date) -> WMode? {
    if pin == "all" { return nil }
    if let p = pin, let m = modes.first(where: { $0.id == p }) { return m }
    return follow ? mode(at: date) : nil
  }

  /** Item 102: the mode in force at [date] (Everything is a mode that hides nothing). Item 108:
   * a mode picked on the Focus mode widget comes first, until it ends. */
  func mode(at date: Date) -> WMode? {
    if let p = picked, p.until == nil || p.until! > date { return modes.first { $0.id == p.id } }
    guard let s = modeLine.first(where: { $0.start <= date && date < $0.end }) else { return nil }
    return modes.first { $0.id == s.id }
  }

  /** Item 102: when the mode in force at [date] ends, if before the end of the timeline. */
  func modeEnds(at date: Date) -> Date? {
    if let p = picked, p.until == nil || p.until! > date { return p.until }
    guard let i = modeLine.firstIndex(where: { $0.start <= date && date < $0.end }) else { return nil }
    var j = i
    while j + 1 < modeLine.count && modeLine[j + 1].id == modeLine[i].id { j += 1 }
    return j + 1 < modeLine.count ? modeLine[j].end : nil
  }

  /** Item 102: tasks the mode in force at [date] hides. */
  func hiddenCount(at date: Date) -> Int {
    guard let m = mode(at: date) else { return 0 }
    return everything.filter { m.hides($0, now: date) }.count
  }

  /** Item 102, part 4: the timer at [date], moved on through the break as the app would. */
  func focus(at date: Date) -> FocusState? {
    guard let f = focusTimer else { return nil }
    var phase = (f["phase"] as? String) ?? "focus"
    var round = (f["round"] as? NSNumber)?.intValue ?? 1
    var length = (f["length"] as? NSNumber)?.doubleValue ?? 1500
    var end = (f["end"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
    var ready = (f["ready"] as? Bool) ?? false
    var moved = false
    let every = max(focusLengths[3], 1)
    var guardCount = 0
    while let e = end, date >= e, guardCount < 4 {
      guardCount += 1
      moved = true
      if phase == "focus" {
        phase = round % every == 0 ? "longBreak" : "shortBreak"
        length = Double(phase == "longBreak" ? focusLengths[2] : focusLengths[1]) * 60
        end = e.addingTimeInterval(length)
      } else {
        phase = "focus"
        round += 1
        length = Double(focusLengths[0]) * 60
        end = nil
        ready = true
      }
    }
    let left: TimeInterval
    if let e = end {
      left = e.timeIntervalSince(date)
    } else if ready && (moved || f["left"] == nil) {
      left = length
    } else {
      left = (f["left"] as? NSNumber)?.doubleValue ?? length
    }
    return FocusState(phase: phase, round: round, end: end, left: left, length: length, ready: ready)
  }

  /** Item 102, part 4: when the timer's phases end between [from] and [to], and each minute
   * while it runs, so the ring keeps up. */
  func focusTimes(from: Date, to: Date) -> [Date] {
    guard let s = focus(at: from), let e = s.end else { return [] }
    var out: [Date] = [e]
    if let next = focus(at: e.addingTimeInterval(1))?.end { out.append(next) }
    var t = from.addingTimeInterval(60)
    while t < min(e, to) && out.count < 70 {
      out.append(t)
      t = t.addingTimeInterval(60)
    }
    return out.filter { $0 > from && $0 < to }
  }

  /** Item 102: when the mode changes between [from] and [to], so the widgets redraw then. */
  func modeChanges(from: Date, to: Date) -> [Date] {
    modeLine.map { $0.start }.filter { $0 > from && $0 < to }
  }

  /** When snoozes end between [from] and [to], so the widgets can redraw then. */
  func snoozeEnds(from: Date, to: Date) -> [Date] {
    Array(Set(all.compactMap { $0.snoozedUntil }.filter { $0 > from && $0 < to })).sorted()
  }

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
    // Snoozed on a widget: hidden until the snooze ends, then back even if the app wasn't opened.
    var widgetSnoozed: [String: Date] = [:]
    for o in array(d, "widget_snoozed") {
      if let id = o["id"] as? String { widgetSnoozed[id] = date(o["until"]) ?? Date.distantFuture }
    }
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
      if done.contains(id) { continue }
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
      // Still snoozed only until the time the app sent (older app versions send none).
      // The redraws ask for the snapshot at their own time (Snapshot.at), so a snooze that ends
      // between the hourly redraws shows the task again then, not at the next reload.
      let snoozed = (o["snoozed"] as? Bool) ?? false
      let until = snoozed ? date(o["snoozedUntil"]) : nil
      t.snoozedUntil = until
      t.snoozed = snoozed && (until == nil || until! > Date())
      if let w = widgetSnoozed[id], w > Date() {
        t.snoozedUntil = w
        t.snoozed = true
      }
      t.worked = worked(id, o)
      t.hide = (o["hide"] as? [String]) ?? []
      t.focusToday = (o["focusToday"] as? NSNumber)?.intValue ?? 0
      s.everything.append(t)
    }
    // Item 108: sent even when the widgets don't follow the mode (for the Focus mode widget and
    // widgets set to a mode of their own); older app versions sent them only when they did.
    if root["modes"] != nil {
      s.follow = (root["modeWidgets"] as? Bool) ?? true
      s.modes = ((root["modes"] as? [[String: Any]]) ?? []).map { (o: [String: Any]) -> WMode in
        let timer = ints(o["timer"])
        return WMode(
          id: str(o["id"]), name: str(o["name"]),
          colour: argb((o["colour"] as? NSNumber)?.int64Value ?? 0xFF3F6FB5),
          overdue: (o["overdue"] as? Bool) ?? true, due: (o["due"] as? String) ?? "today",
          starred: (o["starred"] as? Bool) ?? true, timer: timer.count == 4 ? timer : nil)
      }
      s.modeLine = ((root["modeLine"] as? [[Any]]) ?? []).compactMap { a -> (start: Date, end: Date, id: String)? in
        guard a.count == 3, let f = date(a[0]), let e = date(a[1]), let id = a[2] as? String else { return nil }
        return (start: f, end: e, id: id)
      }
    }
    if let raw = d.string(forKey: "widget_mode_local"),
      let o = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any], let id = o["mode"] as? String
    {
      let until = (o["until"] as? NSNumber).flatMap { $0.int64Value > 0 ? Date(timeIntervalSince1970: $0.doubleValue / 1000) : nil }
      s.picked = (id: id, until: until)
    }
    s.focusTimer = root["focusTimer"] as? [String: Any]
    // Item 108: the timer as the widget's buttons left it, until the app catches up.
    if let raw = d.string(forKey: "focus_local"), !raw.isEmpty,
      let o = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any]
    {
      s.focusTimer = (o["stopped"] as? Bool) == true ? nil : o
    }
    let lengths = ints(root["focusLengths"])
    if lengths.count == 4 { s.baseLengths = lengths }
    s.focusLengths = s.mode(at: Date())?.timer ?? s.baseLengths
    let nowMode = s.filterMode(at: Date())
    s.all = s.everything.filter { nowMode?.hides($0, now: Date()) != true }
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
    s.plan = ((root["plan"] as? [[String: Any]]) ?? []).compactMap { o in
      guard let at = date(o["at"]) else { return nil }
      return WPlan(
        id: str(o["id"]), step: o["step"] as? String, title: str(o["title"]), task: o["task"] as? String, at: at,
        end: date(o["end"]) ?? at, later: (o["later"] as? Bool) ?? false)
    }
    s.planFree = ((root["planFree"] as? [[NSNumber]]) ?? []).compactMap { a in
      guard a.count == 2 else { return nil }
      return (Date(timeIntervalSince1970: a[0].doubleValue / 1000), Date(timeIntervalSince1970: a[1].doubleValue / 1000))
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

  /** A shorter [dueLabel] for narrow lists: "16:00" today, "Fri" this week, else "11 Nov". */
  static func shortDue(_ due: Date, now: Date) -> String {
    let today = Calendar.current.startOfDay(for: now)
    if due >= today && due < today.addingTimeInterval(day) { return due.formatted(date: .omitted, time: .shortened) }
    if due >= today && due < today.addingTimeInterval(7 * day) { return due.formatted(.dateTime.weekday(.abbreviated)) }
    return due.formatted(.dateTime.day().month(.abbreviated))
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

  /** Hourly redraws for [hours] hours, plus one at each snooze end in between. */
  static func redrawTimes(_ snap: Snapshot, now: Date, hours: Int) -> [Date] {
    let hourly = (0..<hours).map { now.addingTimeInterval(Double($0) * 3600) }
    let end = now.addingTimeInterval(Double(hours) * 3600)
    return (hourly + snap.snoozeEnds(from: now, to: end) + snap.modeChanges(from: now, to: end)
      + snap.focusTimes(from: now, to: end)).sorted()
  }

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

// MARK: - Calendar events (item 90)

/** Today's events from the iPad's calendars, once the app has been allowed to read them. */
enum Events {
  static func today(_ now: Date) -> [(id: String, title: String, start: Date, end: Date, allDay: Bool)] {
    guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
    let store = EKEventStore()
    let start = Calendar.current.startOfDay(for: now)
    let pred = store.predicateForEvents(withStart: start, end: start.addingTimeInterval(W.day), calendars: nil)
    return store.events(matching: pred).map {
      ($0.eventIdentifier ?? UUID().uuidString, $0.title ?? "(No title)", $0.startDate, $0.endDate, $0.isAllDay)
    }
  }
}
