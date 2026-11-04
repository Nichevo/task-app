import SwiftUI
import WidgetKit

// Item 79, step 0: a test widget that proves the app and the widget can share data on the iPad
// when it is sideloaded with a free Apple ID. It shows how many tasks are open, the first few,
// and which shared group it found. The real widgets replace it in the next step.

struct TestEntry: TimelineEntry {
  let date: Date
  let group: String?
  let open: Int?
  let titles: [String]
}

struct TestProvider: TimelineProvider {
  func placeholder(in context: Context) -> TestEntry {
    TestEntry(date: Date(), group: AppGroup.projectName, open: 3, titles: ["Buy milk", "Call the bank", "Book the car in"])
  }

  func getSnapshot(in context: Context, completion: @escaping (TestEntry) -> Void) {
    completion(context.isPreview ? placeholder(in: context) : load())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<TestEntry>) -> Void) {
    // The app asks for a redraw whenever its tasks change; this hourly one is a fallback.
    completion(Timeline(entries: [load()], policy: .after(Date().addingTimeInterval(3600))))
  }

  private func load() -> TestEntry {
    guard let group = AppGroup.id else {
      return TestEntry(date: Date(), group: nil, open: nil, titles: [])
    }
    guard
      let raw = UserDefaults(suiteName: group)?.string(forKey: "widget_data"),
      let json = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
      let tasks = json["tasks"] as? [[String: Any]]
    else {
      return TestEntry(date: Date(), group: group, open: nil, titles: [])
    }
    let open = tasks.filter { ($0["snoozed"] as? Bool) != true }
    return TestEntry(
      date: Date(), group: group, open: open.count,
      titles: open.prefix(5).compactMap { $0["title"] as? String })
  }
}

struct TestView: View {
  @Environment(\.widgetFamily) var family
  let entry: TestEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Task Blocks").font(.headline)
      if entry.group == nil {
        Text("No shared storage. The build was signed without the app group.")
          .font(.caption).foregroundStyle(.red)
      } else if let open = entry.open {
        Text("\(open) open tasks").font(.title2).bold()
        ForEach(Array(entry.titles.prefix(family == .systemSmall ? 2 : 5).enumerated()), id: \.offset) { _, t in
          Text(t).font(.caption).lineLimit(1)
        }
      } else {
        Text("Open Task Blocks once so it can share your tasks.").font(.caption)
      }
      Spacer(minLength: 0)
      if family != .systemSmall {
        Text("Shared group: \(entry.group ?? "none")")
          .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .containerBackground(.fill.tertiary, for: .widget)
  }
}

@main
struct TaskBlocksWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "TaskBlocksWidget", provider: TestProvider()) { entry in
      TestView(entry: entry)
    }
    .configurationDisplayName("Task Blocks test")
    .description("Checks that widgets can see your tasks.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}
