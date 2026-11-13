import AppIntents
import Charts
import SwiftUI
import WidgetKit

// Item 79: the iPad (and iPhone) home screen widgets. Eleven kinds cover the 17 Android widgets;
// similar ones are one kind with a "Show" choice in Edit Widget. Item 90 adds the Calendar widget
// and Lock Screen widgets (At a glance, Quick add).

// MARK: - Timeline

struct SnapEntry<I>: TimelineEntry {
  let date: Date
  let snap: Snapshot
  let config: I
}

/** Reads the shared data once and plans hourly redraws, so block colours keep ageing. */
struct SnapProvider<I: WidgetConfigurationIntent>: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> SnapEntry<I> {
    SnapEntry(date: Date(), snap: Snapshot(), config: I())
  }

  func snapshot(for configuration: I, in context: Context) async -> SnapEntry<I> {
    SnapEntry(date: Date(), snap: Snapshot.load(), config: configuration)
  }

  func timeline(for configuration: I, in context: Context) async -> Timeline<SnapEntry<I>> {
    let snap = Snapshot.load()
    let now = Date()
    let times = W.redrawTimes(snap, now: now, hours: 6)
    let entries = times.map { SnapEntry(date: $0, snap: snap.at($0), config: configuration) }
    return Timeline(entries: entries, policy: .atEnd)
  }
}

struct PlainEntry: TimelineEntry {
  let date: Date
  let snap: Snapshot
}

struct PlainProvider: TimelineProvider {
  /** Also redraw every hour (the Calendar widget's list and colours), not only at midnight. */
  var hourly = false

  func placeholder(in context: Context) -> PlainEntry { PlainEntry(date: Date(), snap: Snapshot()) }

  func getSnapshot(in context: Context, completion: @escaping (PlainEntry) -> Void) {
    completion(PlainEntry(date: Date(), snap: Snapshot.load()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<PlainEntry>) -> Void) {
    // Redraw just after midnight, so the month and today move on.
    let snap = Snapshot.load()
    let cal = Calendar.current
    let now = Date()
    let next = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now.addingTimeInterval(3600)
    if hourly {
      let entries = W.redrawTimes(snap, now: now, hours: 6).map { PlainEntry(date: $0, snap: snap.at($0)) }
      completion(Timeline(entries: entries, policy: .atEnd))
      return
    }
    // Also when a snooze ends before midnight, so that task shows again then.
    let times = [now] + snap.snoozeEnds(from: now, to: next)
    completion(Timeline(entries: times.map { PlainEntry(date: $0, snap: snap.at($0)) },
                        policy: .after(next.addingTimeInterval(60))))
  }
}

// MARK: - Shared pieces

extension View {
  func widgetCard() -> some View {
    self.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .containerBackground(.background, for: .widget)
  }
}

/** How many rows fit in each size. */
func rowCount(_ f: WidgetFamily) -> Int {
  switch f {
  case .systemSmall: return 3
  case .systemMedium: return 3
  case .systemLarge: return 8
  case .systemExtraLarge: return 8
  default: return 3
  }
}

struct Header: View {
  let title: String
  var detail: String = ""
  var url: URL? = nil
  var add: URL? = nil

  var body: some View {
    HStack(spacing: 6) {
      Group {
        if let url { Link(destination: url) { titleText } } else { titleText }
      }
      Spacer(minLength: 0)
      if let add {
        Link(destination: add) {
          Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.tint)
        }
      }
    }
  }

  private var titleText: some View {
    HStack(spacing: 4) {
      Text(title).font(.headline).lineLimit(1)
      if !detail.isEmpty { Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
    }
  }
}

/** A task as a coloured block, as in the app's list. */
struct Block: View {
  let snap: Snapshot
  let task: WTask
  let now: Date
  var compact = false
  /** The Calendar widget's narrow list: "16:00", "Fri", "11 Nov" (item 83). */
  var short = false

  var body: some View {
    Link(destination: W.open(task.id)) {
      HStack(spacing: 6) {
        Text((task.star ? "★ " : "") + task.title).font(compact ? .caption : .subheadline).lineLimit(1)
        Spacer(minLength: 4)
        if let due = task.due {
          Text(short ? W.shortDue(due, now: now) : W.dueLabel(due, now: now)).font(.caption2)
            .foregroundStyle(due < now ? Color.red : Color.black.opacity(0.6))
        }
      }
      .foregroundStyle(Color.black.opacity(0.85))
      .padding(.horizontal, 8)
      .padding(.vertical, compact ? 3 : 5)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(W.colour(snap, task, now: now), in: RoundedRectangle(cornerRadius: 6))
    }
  }
}

/** A block with a tick button before it, and on big widgets a snooze button after it. */
struct TaskRow: View {
  let snap: Snapshot
  let task: WTask
  let now: Date
  var compact = false
  var snooze = false
  var short = false

  var body: some View {
    HStack(spacing: 6) {
      if task.locked {
        Image(systemName: "lock").font(.caption).foregroundStyle(.secondary).frame(width: 20)
      } else {
        Button(intent: TickTaskAction(id: task.id)) {
          Image(systemName: "circle").font(.body).foregroundStyle(.secondary).frame(width: 20)
        }
        .buttonStyle(.plain)
      }
      Block(snap: snap, task: task, now: now, compact: compact, short: short)
      if snooze {
        Button(intent: SnoozeTaskAction(id: task.id)) {
          Image(systemName: "moon.zzz").font(.caption).foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
      }
    }
  }
}

struct EmptyNote: View {
  let text: String
  var body: some View {
    Text(text).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
  }
}

let openAppFirst = "Open Task Blocks once so it can share your tasks."

/** "Work" or the base title with the category: "Kanban board · Work". */
func titled(_ base: String, _ snap: Snapshot, _ cat: String?) -> String {
  guard let cat else { return base }
  return "\(base) · \(snap.categoryName(cat) ?? "category")"
}

// MARK: - 1. Task list (Android: Task list, Today)

func listTasks(_ snap: Snapshot, show: ListShow, cat: String?, now: Date) -> [WTask] {
  let endOfToday = Calendar.current.startOfDay(for: now).addingTimeInterval(W.day)
  var out = snap.tasks.filter { t in
    if let cat, t.cat != cat { return false }
    switch show {
    case .all: return true
    case .soon: return t.due == nil || t.due! <= now.addingTimeInterval(30 * W.day)
    case .starred: return t.star
    case .overdue: return t.due.map { $0 < now } ?? false
    case .today: return t.due.map { $0 < endOfToday } ?? false
    }
  }
  if show == .today { out.sort { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) } }
  return out
}

struct TaskListView: View {
  @Environment(\.widgetFamily) var family
  let entry: SnapEntry<TaskListIntent>

  var body: some View {
    let snap = entry.snap
    let cat = entry.config.category?.id
    let show = entry.config.show
    let tasks = listTasks(snap, show: show, cat: cat, now: entry.date)
    let label: String = {
      switch show {
      case .all: return snap.categoryName(cat) ?? "Tasks"
      case .soon: return titled("Due soon", snap, cat)
      case .starred: return titled("Starred", snap, cat)
      case .overdue: return titled("Overdue", snap, cat)
      case .today: return titled("Today", snap, cat)
      }
    }()
    VStack(alignment: .leading, spacing: 4) {
      Header(title: label, detail: "\(tasks.count)", url: W.link("home"), add: W.link("add", ["cat": cat]))
      if !snap.hasData {
        EmptyNote(text: openAppFirst)
      } else if tasks.isEmpty {
        EmptyNote(text: "Nothing to do here")
      } else {
        ForEach(tasks.prefix(rowCount(family)), id: \.id) { t in
          TaskRow(
            snap: snap, task: t, now: entry.date, compact: family == .systemMedium,
            snooze: family == .systemLarge || family == .systemExtraLarge)
        }
        if tasks.count > rowCount(family) {
          Text("\(tasks.count - rowCount(family)) more").font(.caption2).foregroundStyle(.secondary)
        }
      }
    }
    .widgetCard()
  }
}

struct TaskListWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(kind: "TaskList", intent: TaskListIntent.self, provider: SnapProvider<TaskListIntent>()) {
      TaskListView(entry: $0)
    }
    .configurationDisplayName("Task list")
    .description("Coloured tasks, all or due soon, starred, overdue or today, for one category or all.")
    .supportedFamilies([.systemMedium, .systemLarge, .systemExtraLarge])
  }
}

// MARK: - 2. Summary (Android: Compact, Stats)

struct SummaryView: View {
  @Environment(\.widgetFamily) var family
  let entry: SnapEntry<SummaryIntent>

  var body: some View {
    let snap = entry.snap
    let now = entry.date
    if entry.config.mode == .stats {
      VStack(alignment: .leading, spacing: 6) {
        Text("This week").font(.headline)
        HStack(alignment: .firstTextBaseline, spacing: 4) {
          Text("\(snap.doneThisWeek)").font(.system(size: 36, weight: .bold))
          Text("done").foregroundStyle(.secondary)
        }
        HStack(alignment: .firstTextBaseline, spacing: 4) {
          Text("\(snap.streak)").font(.title2.bold())
          Text("day streak").foregroundStyle(.secondary)
        }
      }
      .widgetCard()
      .widgetURL(W.link("stats"))
    } else {
      let cat = entry.config.category?.id
      let tasks = snap.tasks.filter { cat == nil || $0.cat == cat }
      let overdue = tasks.filter { ($0.due.map { $0 < now }) ?? false }.count
      let next = tasks.filter { $0.due != nil && !$0.locked }.sorted { $0.due! < $1.due! }.prefix(3)
      VStack(alignment: .leading, spacing: 4) {
        Text(snap.categoryName(cat) ?? "Tasks").font(.caption).foregroundStyle(.secondary)
        Text("\(tasks.count) open" + (overdue > 0 ? " · \(overdue) overdue" : "")).font(.headline)
        if !snap.hasData {
          EmptyNote(text: openAppFirst)
        } else if next.isEmpty {
          EmptyNote(text: "Nothing with a due date")
        }
        ForEach(Array(next), id: \.id) { t in
          Text(W.dueLabel(t.due!, now: now) + "  " + t.title).font(.caption).lineLimit(1)
            .foregroundStyle(t.due! < now ? Color.red : Color.primary)
        }
      }
      .widgetCard()
      .widgetURL(W.link("home"))
    }
  }
}

struct SummaryWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(kind: "Summary", intent: SummaryIntent.self, provider: SnapProvider<SummaryIntent>()) {
      SummaryView(entry: $0)
    }
    .configurationDisplayName("Summary")
    .description("Open and overdue counts with the next 3 due, or done this week and your streak.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

// MARK: - 3. Focus (Android: Focus, Now doing)

func topTask(_ tasks: [WTask]) -> WTask? {
  let open = tasks.filter { !$0.locked }
  return open.first { $0.star } ?? open.filter { $0.due != nil }.min { $0.due! < $1.due! } ?? open.first
}

func watchedStage(_ snap: Snapshot, _ id: String?) -> WStage? {
  snap.stage(id) ?? snap.stage("doing") ?? (snap.stages.isEmpty ? nil : snap.stages[snap.stages.count / 2])
}

struct FocusView: View {
  @Environment(\.widgetFamily) var family
  let entry: SnapEntry<FocusIntent>

  var body: some View {
    let snap = entry.snap
    let now = entry.date
    if entry.config.mode == .now {
      nowDoing(snap, now)
    } else {
      let cat = entry.config.category?.id
      if let t = topTask(snap.tasks.filter { cat == nil || $0.cat == cat }) {
        VStack(alignment: .leading, spacing: 6) {
          Text((t.star ? "★ " : "") + t.title).font(family == .systemSmall ? .headline : .title3.bold())
            .lineLimit(family == .systemSmall ? 4 : 3)
          if let due = t.due {
            Text(due < now ? "Overdue · " + W.dueLabel(due, now: now) : "Due " + W.dueLabel(due, now: now))
              .font(.caption)
          }
          Spacer(minLength: 0)
          if !t.locked {
            Button(intent: TickTaskAction(id: t.id)) {
              Label("Done", systemImage: "checkmark").font(.caption.bold())
            }
            .buttonStyle(.bordered)
            .tint(.black)
          }
        }
        .foregroundStyle(Color.black.opacity(0.85))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(W.colour(snap, t, now: now), for: .widget)
        .widgetURL(W.open(t.id))
      } else {
        Text(snap.hasData ? "All done" : openAppFirst).font(.headline).foregroundStyle(.secondary)
          .widgetCard().widgetURL(W.link("home"))
      }
    }
  }

  @ViewBuilder
  private func nowDoing(_ snap: Snapshot, _ now: Date) -> some View {
    let stage = watchedStage(snap, entry.config.stage?.id)
    let t = stage.flatMap { s in snap.boardTasks(s.id, cat: nil).min { ($0.since ?? .distantFuture) < ($1.since ?? .distantFuture) } }
    if let t {
      let open = t.steps.filter { !$0.done }
      let shown = family == .systemSmall ? 0 : family == .systemMedium ? 2 : 6
      VStack(alignment: .leading, spacing: 4) {
        Text(W.join(snap.stage(t.stage)?.name ?? "", t.since == nil ? "" : "for " + W.spell(t.since, now: now)))
          .font(.caption).foregroundStyle(.secondary)
        Text((t.star ? "★ " : "") + t.title).font(.headline).lineLimit(2)
        Text(W.join(snap.categoryName(t.cat) ?? "", W.dueText(t.due, now: now))).font(.caption2)
          .foregroundStyle(.secondary)
        ForEach(open.prefix(shown), id: \.id) { s in
          Button(intent: TickStepAction(task: t.id, step: s.id)) {
            Label(s.title, systemImage: "square").font(.caption).lineLimit(1)
          }
          .buttonStyle(.plain)
        }
        if open.count > shown && shown > 0 {
          Text("\(open.count - shown) more steps").font(.caption2).foregroundStyle(.secondary)
        } else if !t.steps.isEmpty && open.isEmpty {
          Text("All \(t.steps.count) steps ticked").font(.caption2).foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
        HStack(spacing: 6) {
          if let next = snap.nextStage(t.stage), family != .systemSmall {
            Button(intent: MoveAction(task: t.id, stage: next.id)) {
              Text("Next: \(next.name)").font(.caption2.bold()).lineLimit(1)
            }
            .buttonStyle(.bordered)
          }
          if !t.locked {
            Button(intent: TickTaskAction(id: t.id)) {
              Label("Done", systemImage: "checkmark").font(.caption2.bold())
            }
            .buttonStyle(.bordered)
          }
        }
      }
      .widgetCard()
      .widgetURL(W.open(t.id))
    } else {
      VStack(alignment: .leading, spacing: 4) {
        Text("Now doing").font(.headline)
        EmptyNote(text: !snap.hasData ? openAppFirst : stage.map { "Nothing in \($0.name)" } ?? "Nothing on the board")
      }
      .widgetCard()
      .widgetURL(W.link("board"))
    }
  }
}

struct FocusWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(kind: "Focus", intent: FocusIntent.self, provider: SnapProvider<FocusIntent>()) {
      FocusView(entry: $0)
    }
    .configurationDisplayName("Focus")
    .description("One big block for your top task, or the board task you're doing now with its steps.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

// MARK: - 4. Checklist (Android: Checklist, Board steps)

struct ChecklistView: View {
  @Environment(\.widgetFamily) var family
  let entry: SnapEntry<ChecklistIntent>

  var body: some View {
    let snap = entry.snap
    if entry.config.mode == .board {
      boardSteps(snap)
    } else {
      let t = snap.task(entry.config.task?.id) ?? snap.tasks.first { !$0.steps.isEmpty }
      VStack(alignment: .leading, spacing: 4) {
        if let t {
          Header(
            title: t.title, detail: t.steps.isEmpty ? "" : "\(t.steps.filter { $0.done }.count)/\(t.steps.count)",
            url: W.open(t.id))
          if t.steps.isEmpty { EmptyNote(text: "No steps") }
          ForEach(t.steps.prefix(rowCount(family) + 1), id: \.id) { s in
            let row = Label {
              Text(s.title).strikethrough(s.done).foregroundStyle(s.done ? Color.secondary : Color.primary)
            } icon: {
              Image(systemName: s.done ? "checkmark.square.fill" : "square")
            }
            .font(.subheadline).lineLimit(1)
            if s.done {
              Link(destination: W.open(t.id)) { row }
            } else {
              Button(intent: TickStepAction(task: t.id, step: s.id)) { row }.buttonStyle(.plain)
            }
          }
        } else {
          Header(title: "Checklist")
          EmptyNote(text: snap.hasData ? "Pick a task: press and hold, Edit Widget." : openAppFirst)
        }
      }
      .widgetCard()
    }
  }

  @ViewBuilder
  private func boardSteps(_ snap: Snapshot) -> some View {
    let cat = entry.config.category?.id
    // Furthest stage first; the last stage (done) is left out.
    let groups: [(WStage, [(WTask, WStep)])] = snap.stages.dropLast().reversed().compactMap { (s: WStage) -> (WStage, [(WTask, WStep)])? in
      let steps = snap.boardSteps(s.id, cat: cat).filter { !$0.1.done }
      return steps.isEmpty ? nil : (s, steps)
    }
    let open = groups.reduce(0) { $0 + $1.1.count }
    VStack(alignment: .leading, spacing: 3) {
      Header(title: titled("Steps on the board", snap, cat), detail: "\(open) open", url: W.link("board"))
      if groups.isEmpty {
        EmptyNote(text: snap.hasData ? "No steps on the board." : openAppFirst)
      }
      ForEach(Array(groups.prefix(4).enumerated()), id: \.offset) { _, g in
        Text(g.0.name).font(.caption.bold()).foregroundStyle(.secondary)
        ForEach(Array(g.1.prefix(family == .systemMedium ? 2 : 4).enumerated()), id: \.offset) { _, p in
          HStack(spacing: 4) {
            Link(destination: W.open(p.0.id)) {
              Text(W.join(p.1.title, p.0.title)).font(.caption).lineLimit(1)
            }
            Spacer(minLength: 2)
            if let next = snap.nextStage(g.0.id) {
              Button(intent: MoveAction(task: p.0.id, step: p.1.id, stage: next.id)) {
                Image(systemName: "arrow.right.circle").font(.caption)
              }
              .buttonStyle(.plain)
            }
          }
        }
      }
    }
    .widgetCard()
  }
}

struct ChecklistWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(kind: "Checklist", intent: ChecklistIntent.self, provider: SnapProvider<ChecklistIntent>()) {
      ChecklistView(entry: $0)
    }
    .configurationDisplayName("Checklist")
    .description("The steps of one task, or the steps on the board grouped by stage.")
    .supportedFamilies([.systemMedium, .systemLarge])
  }
}

// MARK: - 5. Mini month

struct MonthView: View {
  let entry: PlainEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Link(destination: W.link("day")) {
        Text(entry.date.formatted(.dateTime.month(.wide).year())).font(.headline)
      }
      MonthGrid(snap: entry.snap, now: entry.date)
      Spacer(minLength: 0)
    }
    .widgetCard()
  }
}

/** This month's days, Monday first, with a dot on days with tasks due. Tap a day to open it. */
struct MonthGrid: View {
  let snap: Snapshot
  let now: Date
  var big = false

  var body: some View {
    let cal: Calendar = {
      var c = Calendar.current
      c.firstWeekday = 2
      return c
    }()
    let month = cal.dateInterval(of: .month, for: now)!
    let lead = (cal.component(.weekday, from: month.start) + 5) % 7
    let days = cal.range(of: .day, in: .month, for: now)?.count ?? 30
    let today = cal.component(.day, from: now)
    let cells: [Int?] = Array(repeating: nil, count: lead) + (1...days).map { Optional($0) }
    let rows = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
    VStack(alignment: .leading, spacing: big ? 6 : 2) {
      HStack(spacing: 0) {
        ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, d in
          Text(d).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
        }
      }
      ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
        HStack(spacing: 0) {
          ForEach(0..<7, id: \.self) { i in
            let d = i < row.count ? row[i] : nil
            dayCell(d, cal: cal, month: month.start, today: today)
          }
        }
      }
    }
  }

  @ViewBuilder
  private func dayCell(_ d: Int?, cal: Calendar, month: Date, today: Int) -> some View {
    if let d, let date = cal.date(byAdding: .day, value: d - 1, to: month) {
      let key = W.key(date)
      let due = snap.dueDays[key]
      Link(destination: W.link("day", ["d": key])) {
        VStack(spacing: 1) {
          Text("\(d)").font((big ? Font.subheadline : Font.caption2).weight(d == today ? .bold : .regular))
            .foregroundStyle(d == today ? W.blue : Color.primary)
          Circle().fill(due == nil ? Color.clear : due!.faded ? Color.secondary.opacity(0.5) : Color.accentColor)
            .frame(width: big ? 5 : 4, height: big ? 5 : 4)
        }
        .frame(maxWidth: .infinity)
      }
    } else {
      Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
    }
  }
}

struct MonthWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "Month", provider: PlainProvider()) { MonthView(entry: $0) }
      .configurationDisplayName("Mini month")
      .description("This month with a dot on days with tasks due. Tap a day to open it.")
      .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

// MARK: - 6. Kanban board (Android: Board summary, Stage list)

struct StageTiles: View {
  let snap: Snapshot
  let cat: String?
  var selected: String? = nil

  var body: some View {
    HStack(spacing: 4) {
      ForEach(Array(snap.stages.enumerated()), id: \.element.id) { i, s in
        let n = snap.boardTasks(s.id, cat: cat).count
        let steps = snap.boardSteps(s.id, cat: cat).count
        let over = s.limit.map { n > $0 } ?? false
        Link(destination: W.link("board", ["stage": s.id])) {
          VStack(spacing: 0) {
            Text(steps > 0 ? "\(n)·\(steps)" : "\(n)").font(.title3.bold())
            Text(s.name).font(.caption2).lineLimit(1).minimumScaleFactor(0.7)
          }
          .foregroundStyle(over ? W.amber : s.id == selected ? W.blue : Color.black.opacity(0.85))
          .frame(maxWidth: .infinity)
          .padding(.vertical, 4)
          .background(W.tile(s, i), in: RoundedRectangle(cornerRadius: 8))
        }
      }
    }
  }
}

struct BoardView: View {
  @Environment(\.widgetFamily) var family
  let entry: SnapEntry<BoardIntent>

  var body: some View {
    let snap = entry.snap
    let cat = entry.config.category?.id
    let now = entry.date
    VStack(alignment: .leading, spacing: 6) {
      Header(title: titled("Kanban board", snap, cat), url: W.link("board"))
      if snap.stages.isEmpty {
        EmptyNote(text: snap.hasData ? "No stages" : openAppFirst)
      } else if entry.config.mode == .summary || family == .systemSmall {
        StageTiles(snap: snap, cat: cat)
        let over = snap.stages.filter { s in s.limit.map { snap.boardTasks(s.id, cat: cat).count > $0 } ?? false }
        if !over.isEmpty {
          Text(over.map { "\($0.name) is over its limit of \($0.limit!)" }.joined(separator: "; "))
            .font(.caption2).foregroundStyle(W.amber)
        }
      } else {
        let shown = snap.stage(entry.config.stage?.id) ?? snap.stage("doing") ?? snap.stages[0]
        let cards = snap.boardTasks(shown.id, cat: cat).sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
        StageTiles(snap: snap, cat: cat, selected: shown.id)
        Text("\(shown.name) · \(cards.count)").font(.subheadline.bold())
        if cards.isEmpty { EmptyNote(text: "Nothing here") }
        ForEach(cards.prefix(family == .systemMedium ? 1 : 6), id: \.id) { t in
          HStack(spacing: 4) {
          Link(destination: W.open(t.id)) {
            VStack(alignment: .leading, spacing: 1) {
              Text((t.star ? "★ " : "") + t.title).font(.caption).lineLimit(1)
              let steps = t.steps.isEmpty ? "" : "\(t.steps.filter { $0.done }.count)/\(t.steps.count) steps"
              let here = W.spell(t.since, now: now)
              Text(W.join(W.dueText(t.due, now: now), steps, here.isEmpty ? "" : "\(here) here", t.snoozed ? "snoozed" : ""))
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
          }
          Spacer(minLength: 2)
          if let next = snap.nextStage(shown.id) {
            Button(intent: MoveAction(task: t.id, stage: next.id)) {
              Image(systemName: "arrow.right.circle").font(.body)
            }
            .buttonStyle(.plain)
          }
          }
        }
      }
    }
    .widgetCard()
  }
}

struct BoardWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(kind: "Board", intent: BoardIntent.self, provider: SnapProvider<BoardIntent>()) {
      BoardView(entry: $0)
    }
    .configurationDisplayName("Kanban board")
    .description("How many tasks are in each stage, or the cards in one stage.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

// MARK: - 7. Matrix

struct MatrixView: View {
  @Environment(\.widgetFamily) var family
  let entry: SnapEntry<CategoryIntent>

  static let order = ["do", "decide", "delegate", "delete"]
  static let names = ["do": "Do", "decide": "Decide", "delegate": "Delegate", "delete": "Delete"]
  static let tints: [String: Color] = [
    "do": Color(red: 0.99, green: 0.89, blue: 0.86), "decide": Color(red: 0.89, green: 0.93, blue: 0.98),
    "delegate": Color(red: 1.0, green: 0.95, blue: 0.80), "delete": Color(red: 0.93, green: 0.93, blue: 0.95),
  ]

  var body: some View {
    let snap = entry.snap
    let cat = entry.config.category?.id
    let per = family == .systemMedium ? 1 : 4
    VStack(alignment: .leading, spacing: 4) {
      Header(title: titled("Matrix", snap, cat), url: W.link("matrix"))
      Grid(horizontalSpacing: 4, verticalSpacing: 4) {
        ForEach(0..<2, id: \.self) { r in
          GridRow {
            ForEach(0..<2, id: \.self) { c in
              let box = MatrixView.order[r * 2 + c]
              let tasks = snap.tasks.filter { $0.box == box && (cat == nil || $0.cat == cat) }
              Link(destination: W.link("matrix", ["box": box])) {
                VStack(alignment: .leading, spacing: 1) {
                  Text("\(snap.boxes[box] ?? MatrixView.names[box]!) · \(tasks.count)").font(.caption.bold())
                  ForEach(tasks.prefix(per), id: \.id) { t in
                    Text(t.title).font(.caption2).lineLimit(1)
                  }
                  Spacer(minLength: 0)
                }
                .foregroundStyle(Color.black.opacity(0.85))
                .padding(5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(MatrixView.tints[box]!, in: RoundedRectangle(cornerRadius: 8))
              }
            }
          }
        }
      }
    }
    .widgetCard()
  }
}

struct MatrixWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(kind: "Matrix", intent: CategoryIntent.self, provider: SnapProvider<CategoryIntent>()) {
      MatrixView(entry: $0)
    }
    .configurationDisplayName("Matrix")
    .description("The four boxes and the top tasks in each.")
    .supportedFamilies([.systemMedium, .systemLarge, .systemExtraLarge])
  }
}

// MARK: - 8. Worked today

struct WorkedView: View {
  @Environment(\.widgetFamily) var family
  let entry: SnapEntry<WorkedIntent>

  var body: some View {
    let snap = entry.snap
    let habits = entry.config.mode == .habits
    let cat = entry.config.category?.id
    let list: [WTask] =
      habits
      ? snap.habits.sorted { ($0.locked ? 1 : 0) < ($1.locked ? 1 : 0) }
      : snap.tasks.filter { (cat == nil || $0.cat == cat) && !$0.locked }
    let today = W.key(entry.date)
    let week = W.week(entry.date)
    let n = list.filter { $0.worked.contains(today) }.count
    let of = habits ? list.filter { !$0.locked || $0.worked.contains(today) }.count : list.count
    VStack(alignment: .leading, spacing: 4) {
      Header(
        title: habits ? "Habits today" : titled("Worked today", snap, cat), detail: "\(n) of \(of)",
        url: W.link(habits ? "habits" : "achievements"))
      if list.isEmpty {
        EmptyNote(
          text: !snap.hasData
            ? openAppFirst : habits ? "No habits yet. Turn on \"Habit\" on a task in the app." : "No open tasks here.")
      }
      ForEach(list.prefix(rowCount(family)), id: \.id) { t in
        HStack(spacing: 6) {
          Button(intent: WorkedDayAction(id: t.id, day: today, on: !t.worked.contains(today))) {
            Image(systemName: t.worked.contains(today) ? "checkmark.circle.fill" : "circle")
              .foregroundStyle(t.worked.contains(today) ? Color.green : Color.secondary)
          }
          .buttonStyle(.plain)
          Link(destination: W.open(t.id)) {
          HStack(spacing: 6) {
            Text(t.title).font(.subheadline).lineLimit(1)
            Spacer(minLength: 4)
            Text(week.map { $0 > today ? "·" : t.worked.contains($0) ? "●" : "○" }.joined())
              .font(.caption2.monospaced()).foregroundStyle(.secondary)
            if habits && t.streak > 0 {
              Text("\(t.streak)").font(.caption2.bold()).foregroundStyle(.orange)
            }
          }
          }
        }
      }
    }
    .widgetCard()
  }
}

struct WorkedWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(kind: "Worked", intent: WorkedIntent.self, provider: SnapProvider<WorkedIntent>()) {
      WorkedView(entry: $0)
    }
    .configurationDisplayName("Worked today")
    .description("A category's open tasks, or your habits, with the days worked this week.")
    .supportedFamilies([.systemMedium, .systemLarge])
  }
}

// MARK: - 9. Charts (Android: Added vs done, Burn-down)

struct ChartView: View {
  let entry: SnapEntry<ChartIntent>

  var body: some View {
    let snap = entry.snap
    let cat = entry.config.category?.id
    let key = cat ?? ""
    if entry.config.mode == .burnDown, let task = entry.config.task {
      // Item 86: one task's own burn-down; a tap opens the task.
      burnDown(snap.burn["task:" + task.id], title: "Burn-down · \(task.title)",
               empty: "This task needs two or more steps and a date to finish by.")
        .widgetURL(W.open(task.id))
    } else if entry.config.mode == .burnDown {
      burnDown(snap.burn[key], title: titled("Burn-down", snap, cat))
        .widgetURL(W.link("gantt", ["cat": key]))
    } else {
      addedDone(snap.addedDone[key] ?? AddedDone(), title: titled("Added vs done", snap, cat))
        .widgetURL(W.link("stats"))
    }
  }

  private func addedDone(_ a: AddedDone, title: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Header(title: title)
      Chart {
        ForEach(Array(a.added.enumerated()), id: \.offset) { i, v in
          BarMark(x: .value("Day", i), y: .value("Count", v))
            .foregroundStyle(by: .value("Series", "Added"))
            .position(by: .value("Series", "Added"))
        }
        ForEach(Array(a.done.enumerated()), id: \.offset) { i, v in
          BarMark(x: .value("Day", i), y: .value("Count", v))
            .foregroundStyle(by: .value("Series", "Done"))
            .position(by: .value("Series", "Done"))
        }
      }
      .chartForegroundStyleScale(["Added": Color(red: 0.36, green: 0.55, blue: 0.94), "Done": Color(red: 0.26, green: 0.63, blue: 0.28)])
      .chartXAxis(.hidden)
      .chartLegend(.hidden)
      Text("Last 4 weeks: \(a.added.reduce(0, +)) added (blue), \(a.done.reduce(0, +)) done (green), \(a.open.last ?? 0) open now")
        .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
    }
    .widgetCard()
  }

  private func days(_ a: String, _ b: String) -> Int {
    guard let x = W.keyFormat.date(from: a), let y = W.keyFormat.date(from: b) else { return 0 }
    return Int((y.timeIntervalSince(x) / W.day).rounded())
  }

  @ViewBuilder
  private func burnDown(_ b: Burn?, title: String,
                        empty: String = "Nothing with dates on the Gantt chart here yet.") -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Header(title: title)
      if let b {
        let endIdx = days(b.from, b.end)
        let todayIdx = max(b.left.count - 1, 0)
        Chart {
          // The plan: from everything left on the first day to nothing at the end.
          LineMark(x: .value("Day", 0), y: .value("Left", b.total), series: .value("Line", "Plan"))
            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4])).foregroundStyle(.secondary)
          LineMark(x: .value("Day", endIdx), y: .value("Left", 0.0), series: .value("Line", "Plan"))
            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4])).foregroundStyle(.secondary)
          ForEach(Array(b.left.enumerated()), id: \.offset) { i, v in
            LineMark(x: .value("Day", i), y: .value("Left", v), series: .value("Line", "Actual"))
              .lineStyle(StrokeStyle(lineWidth: 2.5)).foregroundStyle(W.blue)
          }
          if let p = b.projected, let now = b.left.last, now > 0 {
            let pi = days(b.from, p)
            LineMark(x: .value("Day", todayIdx), y: .value("Left", now), series: .value("Line", "Pace"))
              .lineStyle(StrokeStyle(lineWidth: 2, dash: [2, 4])).foregroundStyle(pi > endIdx ? Color.red : Color.teal)
            LineMark(x: .value("Day", min(pi, max(endIdx, 7) * 2)), y: .value("Left", 0.0), series: .value("Line", "Pace"))
              .lineStyle(StrokeStyle(lineWidth: 2, dash: [2, 4])).foregroundStyle(pi > endIdx ? Color.red : Color.teal)
          }
          RuleMark(x: .value("Today", todayIdx)).foregroundStyle(W.blue.opacity(0.4))
        }
        .chartXAxis(.hidden)
        .chartLegend(.hidden)
        Text(b.summary).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
      } else {
        EmptyNote(text: empty)
      }
    }
    .widgetCard()
  }
}

struct ChartWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(kind: "Chart", intent: ChartIntent.self, provider: SnapProvider<ChartIntent>()) {
      ChartView(entry: $0)
    }
    .configurationDisplayName("Chart")
    .description("Added vs done for the last 4 weeks, or a burn-down for one category, all, or one task.")
    .supportedFamilies([.systemMedium, .systemLarge])
  }
}

// MARK: - 10. Quick add

struct QuickAddView: View {
  @Environment(\.widgetFamily) var family
  let entry: SnapEntry<CategoryIntent>

  var body: some View {
    let cat = entry.config.category?.id
    if family == .accessoryCircular {
      // Lock Screen (item 90).
      ZStack {
        AccessoryWidgetBackground()
        Image(systemName: "plus").font(.title.bold())
      }
      .containerBackground(for: .widget) {}
      .widgetURL(W.link("add", ["cat": cat]))
    } else {
    VStack(spacing: 6) {
      Image(systemName: "plus.circle.fill").font(.system(size: 44)).foregroundStyle(.tint)
      Text("Add a task").font(.headline)
      if let name = entry.snap.categoryName(cat) {
        Text(name).font(.caption).foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .containerBackground(.background, for: .widget)
    .widgetURL(W.link("add", ["cat": cat]))
    }
  }
}

struct QuickAddWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(kind: "QuickAdd", intent: CategoryIntent.self, provider: SnapProvider<CategoryIntent>()) {
      QuickAddView(entry: $0)
    }
    .configurationDisplayName("Quick add")
    .description("Opens Task Blocks ready to type a new task. Also fits on the Lock Screen.")
    .supportedFamilies([.systemSmall, .accessoryCircular])
  }
}

// MARK: - 11. Calendar (Android: Calendar, item 83; iPad item 90)

/** A line in the Calendar widget's list: a task, or one of today's calendar events. */
struct CalItem: Identifiable {
  let id: String
  let title: String
  let due: Date
  var task: WTask? = nil
  var allDay = false
}

/** Overdue, the next two weeks and today's events, by date, as on Android. */
func upcoming(_ snap: Snapshot, now: Date) -> [CalItem] {
  let end = Calendar.current.startOfDay(for: now).addingTimeInterval(14 * W.day)
  var out: [CalItem] = snap.tasks.compactMap { t in
    guard let due = t.due, due < end else { return nil }
    return CalItem(id: t.id, title: t.title, due: due, task: t)
  }
  out += Events.today(now).map { CalItem(id: "ev:" + $0.id, title: $0.title, due: $0.start, allDay: $0.allDay) }
  return out.sorted { $0.due < $1.due }
}

struct CalendarView: View {
  @Environment(\.widgetFamily) var family
  let entry: PlainEntry

  var body: some View {
    let snap = entry.snap
    let now = entry.date
    let big = family == .systemExtraLarge
    let items = upcoming(snap, now: now)
    let rows = big ? 12 : 9
    VStack(alignment: .leading, spacing: 6) {
      Header(
        title: now.formatted(.dateTime.month(.wide).year()), url: W.link("day"), add: W.link("add"))
      HStack(alignment: .top, spacing: 12) {
        MonthGrid(snap: snap, now: now, big: big)
          .frame(maxWidth: .infinity)
        VStack(alignment: .leading, spacing: 4) {
          if !snap.hasData {
            EmptyNote(text: openAppFirst)
          } else if items.isEmpty {
            EmptyNote(text: "Nothing in the next two weeks")
          }
          ForEach(items.prefix(rows)) { item in
            if let t = item.task {
              TaskRow(snap: snap, task: t, now: now, compact: true, short: true)
            } else {
              HStack(spacing: 6) {
                Image(systemName: "calendar").font(.caption).foregroundStyle(.secondary).frame(width: 20)
                Text(item.title).font(.caption).lineLimit(1)
                Spacer(minLength: 4)
                Text(item.allDay ? "Today" : W.shortDue(item.due, now: now)).font(.caption2).foregroundStyle(.secondary)
              }
              .padding(.horizontal, 8)
              .padding(.vertical, 3)
              .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
            }
          }
          if items.count > rows {
            Text("\(items.count - rows) more").font(.caption2).foregroundStyle(.secondary)
          }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }
      Spacer(minLength: 0)
    }
    .widgetCard()
  }
}

struct CalendarWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "Calendar", provider: PlainProvider(hourly: true)) { CalendarView(entry: $0) }
      .configurationDisplayName("Calendar")
      .description("This month, and what's coming up: overdue, the next two weeks and today's events.")
      .supportedFamilies([.systemLarge, .systemExtraLarge])
  }
}

// MARK: - 12. At a glance, for the Lock Screen (iPad item 90)

struct GlanceView: View {
  @Environment(\.widgetFamily) var family
  let entry: SnapEntry<CategoryIntent>

  var body: some View {
    let snap = entry.snap
    let now = entry.date
    let cat = entry.config.category?.id
    let tasks = snap.tasks.filter { cat == nil || $0.cat == cat }
    let overdue = tasks.filter { ($0.due.map { $0 < now }) ?? false }.count
    let next = tasks.filter { $0.due != nil && !$0.locked }.sorted { $0.due! < $1.due! }
    Group {
      switch family {
      case .accessoryCircular:
        ZStack {
          AccessoryWidgetBackground()
          VStack(spacing: 0) {
            Text("\(overdue > 0 ? overdue : tasks.count)").font(.title2.bold())
            Text(overdue > 0 ? "late" : "open").font(.caption2)
          }
        }
      case .accessoryInline:
        if let t = next.first {
          Text("\(W.shortDue(t.due!, now: now)) \(t.title)")
        } else {
          Text("\(tasks.count) tasks open")
        }
      default:
        VStack(alignment: .leading, spacing: 1) {
          Text("\(tasks.count) open" + (overdue > 0 ? " · \(overdue) overdue" : "")).font(.headline)
          if next.isEmpty {
            Text(snap.hasData ? "Nothing with a due date" : "Open Task Blocks once").font(.caption)
          }
          ForEach(next.prefix(2), id: \.id) { t in
            Text("\(W.shortDue(t.due!, now: now))  \(t.title)").font(.caption).lineLimit(1)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .containerBackground(for: .widget) {}
    .widgetURL(W.link("home"))
  }
}

struct GlanceWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(kind: "Glance", intent: CategoryIntent.self, provider: SnapProvider<CategoryIntent>()) {
      GlanceView(entry: $0)
    }
    .configurationDisplayName("At a glance")
    .description("For the Lock Screen: how many tasks are open or overdue, and what's due next.")
    .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
  }
}

// MARK: - All of them

@main
struct TaskBlocksWidgets: WidgetBundle {
  var body: some Widget {
    TaskListWidget()
    SummaryWidget()
    FocusWidget()
    ChecklistWidget()
    MonthWidget()
    BoardWidget()
    MatrixWidget()
    WorkedWidget()
    ChartWidget()
    QuickAddWidget()
    CalendarWidget()
    GlanceWidget()
  }
}
