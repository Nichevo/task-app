import AppIntents
import WidgetKit

// Item 79: the choices made in "Edit Widget" (press and hold a widget). The lists come from the
// tasks, categories and stages the app last shared.

struct CategoryEntity: AppEntity {
  let id: String
  let name: String

  static var typeDisplayRepresentation: TypeDisplayRepresentation { "Category" }
  static var defaultQuery: CategoryQuery { CategoryQuery() }
  var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct CategoryQuery: EntityQuery {
  func all() -> [CategoryEntity] { Snapshot.load().categories.map { CategoryEntity(id: $0.id, name: $0.name) } }
  func entities(for identifiers: [String]) async throws -> [CategoryEntity] {
    all().filter { identifiers.contains($0.id) }
  }
  func suggestedEntities() async throws -> [CategoryEntity] { all() }
}

struct StageEntity: AppEntity {
  let id: String
  let name: String

  static var typeDisplayRepresentation: TypeDisplayRepresentation { "Stage" }
  static var defaultQuery: StageQuery { StageQuery() }
  var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct StageQuery: EntityQuery {
  func all() -> [StageEntity] { Snapshot.load().stages.map { StageEntity(id: $0.id, name: $0.name) } }
  func entities(for identifiers: [String]) async throws -> [StageEntity] {
    all().filter { identifiers.contains($0.id) }
  }
  func suggestedEntities() async throws -> [StageEntity] { all() }
}

struct TaskEntity: AppEntity {
  let id: String
  let title: String

  static var typeDisplayRepresentation: TypeDisplayRepresentation { "Task" }
  static var defaultQuery: TaskQuery { TaskQuery() }
  var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct TaskQuery: EntityQuery {
  /** Tasks with steps first, as the checklist widget is the main use. */
  func all() -> [TaskEntity] {
    let tasks = Snapshot.load().all
    return (tasks.filter { !$0.steps.isEmpty } + tasks.filter { $0.steps.isEmpty }).map {
      TaskEntity(id: $0.id, title: $0.title)
    }
  }
  func entities(for identifiers: [String]) async throws -> [TaskEntity] {
    all().filter { identifiers.contains($0.id) }
  }
  func suggestedEntities() async throws -> [TaskEntity] { all() }
}

// MARK: - Choices

enum ListShow: String, AppEnum {
  case all, soon, starred, overdue, today

  static var typeDisplayRepresentation: TypeDisplayRepresentation { "Show" }
  static var caseDisplayRepresentations: [ListShow: DisplayRepresentation] {
    [
      .all: "All open tasks", .soon: "Due in the next 30 days or no date", .starred: "Starred",
      .overdue: "Overdue", .today: "Today (overdue and due today)",
    ]
  }
}

enum SummaryMode: String, AppEnum {
  case counts, stats

  static var typeDisplayRepresentation: TypeDisplayRepresentation { "Show" }
  static var caseDisplayRepresentations: [SummaryMode: DisplayRepresentation] {
    [.counts: "Open and overdue, next 3 due", .stats: "Done this week and streak"]
  }
}

enum FocusMode: String, AppEnum {
  case top, now

  static var typeDisplayRepresentation: TypeDisplayRepresentation { "Show" }
  static var caseDisplayRepresentations: [FocusMode: DisplayRepresentation] {
    [.top: "Top task (starred, then soonest due)", .now: "Now doing (longest in a board stage)"]
  }
}

enum ChecklistMode: String, AppEnum {
  case task, board

  static var typeDisplayRepresentation: TypeDisplayRepresentation { "Show" }
  static var caseDisplayRepresentations: [ChecklistMode: DisplayRepresentation] {
    [.task: "The steps of one task", .board: "Steps on the board, by stage"]
  }
}

enum BoardMode: String, AppEnum {
  case summary, stage

  static var typeDisplayRepresentation: TypeDisplayRepresentation { "Show" }
  static var caseDisplayRepresentations: [BoardMode: DisplayRepresentation] {
    [.summary: "How many in each stage", .stage: "The cards in one stage"]
  }
}

enum WorkedMode: String, AppEnum {
  case tasks, habits

  static var typeDisplayRepresentation: TypeDisplayRepresentation { "Show" }
  static var caseDisplayRepresentations: [WorkedMode: DisplayRepresentation] {
    [.tasks: "Open tasks", .habits: "Habits"]
  }
}

enum ChartMode: String, AppEnum {
  case addedDone, burnDown

  static var typeDisplayRepresentation: TypeDisplayRepresentation { "Chart" }
  static var caseDisplayRepresentations: [ChartMode: DisplayRepresentation] {
    [.addedDone: "Added vs done (last 4 weeks)", .burnDown: "Burn-down (Gantt chart)"]
  }
}

// MARK: - One configuration per widget kind

struct TaskListIntent: WidgetConfigurationIntent {
  static var title: LocalizedStringResource { "Task list" }
  @Parameter(title: "Show", default: .all) var show: ListShow
  @Parameter(title: "Category") var category: CategoryEntity?
  init() {}
}

struct SummaryIntent: WidgetConfigurationIntent {
  static var title: LocalizedStringResource { "Summary" }
  @Parameter(title: "Show", default: .counts) var mode: SummaryMode
  @Parameter(title: "Category") var category: CategoryEntity?
  init() {}
}

struct FocusIntent: WidgetConfigurationIntent {
  static var title: LocalizedStringResource { "Focus" }
  @Parameter(title: "Show", default: .top) var mode: FocusMode
  @Parameter(title: "Category (top task)") var category: CategoryEntity?
  @Parameter(title: "Stage (now doing)") var stage: StageEntity?
  init() {}
}

struct ChecklistIntent: WidgetConfigurationIntent {
  static var title: LocalizedStringResource { "Checklist" }
  @Parameter(title: "Show", default: .task) var mode: ChecklistMode
  @Parameter(title: "Task") var task: TaskEntity?
  @Parameter(title: "Category (board steps)") var category: CategoryEntity?
  init() {}
}

struct BoardIntent: WidgetConfigurationIntent {
  static var title: LocalizedStringResource { "Kanban board" }
  @Parameter(title: "Show", default: .summary) var mode: BoardMode
  @Parameter(title: "Stage") var stage: StageEntity?
  @Parameter(title: "Category") var category: CategoryEntity?
  init() {}
}

struct CategoryIntent: WidgetConfigurationIntent {
  static var title: LocalizedStringResource { "Category" }
  @Parameter(title: "Category") var category: CategoryEntity?
  init() {}
}

struct WorkedIntent: WidgetConfigurationIntent {
  static var title: LocalizedStringResource { "Worked today" }
  @Parameter(title: "Show", default: .tasks) var mode: WorkedMode
  @Parameter(title: "Category") var category: CategoryEntity?
  init() {}
}

struct ChartIntent: WidgetConfigurationIntent {
  static var title: LocalizedStringResource { "Chart" }
  @Parameter(title: "Chart", default: .addedDone) var mode: ChartMode
  @Parameter(title: "Category") var category: CategoryEntity?
  // Item 86: a burn-down of one task's steps instead of a category.
  @Parameter(title: "Task (burn-down)") var task: TaskEntity?
  init() {}
}
