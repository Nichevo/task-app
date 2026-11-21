package app.taskblocks

import android.app.Activity
import android.app.AlertDialog
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle

/**
 * Asks what a newly placed widget should show and how it should look. Also runs again when
 * the widget is reconfigured (long-press on it).
 */
class WidgetConfigActivity : Activity() {
  private var widgetId = AppWidgetManager.INVALID_APPWIDGET_ID

  /** Item 108: the focus mode question comes last, for widgets that list tasks, when there are modes. */
  private var modes: List<Triple<String, String, Int>> = emptyList()
  private var modeAsked = false

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    widgetId =
        intent?.extras?.getInt(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
            ?: AppWidgetManager.INVALID_APPWIDGET_ID
    setResult(RESULT_CANCELED, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId))
    if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
      finish()
      return
    }
    val provider = AppWidgetManager.getInstance(this).getAppWidgetInfo(widgetId)?.provider?.className ?: ""
    val snap = WidgetData.snapshot(this)
    if (provider.substringAfterLast('.') in modeWidgets) modes = WidgetMode.list(snap.root).filter { it.first != "all" }
    when {
      provider.endsWith("FocusTimerWidget") -> done()
      provider.endsWith("ChecklistWidget") -> pickTask(snap)
      provider.endsWith("QuickAddWidget") -> pickCategory(snap)
      provider.endsWith("NowDoingWidget") -> pickNow(snap)
      provider.endsWith("WorkedTodayWidget") -> pickWorked(snap)
      provider.endsWith("BoardSummaryWidget") ||
          provider.endsWith("StageListWidget") ||
          provider.endsWith("BoardStepsWidget") ||
          provider.endsWith("MatrixWidget") ||
          provider.endsWith("AddedDoneWidget") -> pickCategoryFilter(snap)
      provider.endsWith("BurnDownWidget") -> pickBurn(snap)
      provider.endsWith("TodayWidget") || provider.endsWith("DayPlanWidget") || provider.endsWith("StatsWidget") ||
          provider.endsWith("MonthWidget") ||
          provider.endsWith("CalendarWidget") ||
          provider.substringAfterLast('.') in weekWidgets ->
          pickLook(showRows = false)
      else -> pickFilter(snap, showRows = !provider.endsWith("CompactWidget") && !provider.endsWith("FocusWidget"))
    }
  }

  private fun done() {
    if (!modeAsked && modes.isNotEmpty()) {
      modeAsked = true
      pickMode()
      return
    }
    WidgetData.refreshAll(this)
    setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId))
    finish()
  }

  /** Item 108: follow the focus mode in force, always show everything, or always one mode. */
  private fun pickMode() {
    val keys = mutableListOf<String?>(null, "all")
    val labels = mutableListOf("Follow the focus mode that is on", "Always everything (ignore focus modes)")
    for ((id, name, _) in modes) {
      keys.add(id)
      labels.add("Always as in $name")
    }
    val now = WidgetData.modePin(this, widgetId)
    AlertDialog.Builder(this)
        .setTitle("Focus mode for this widget")
        .setSingleChoiceItems(labels.toTypedArray(), keys.indexOf(now).coerceAtLeast(0)) { d, which ->
          WidgetData.setModePin(this, widgetId, keys[which])
          d.dismiss()
          done()
        }
        .setOnCancelListener { done() }
        .show()
  }

  private fun pickFilter(snap: Snapshot, showRows: Boolean) {
    val keys = mutableListOf("all", "soon", "star", "overdue")
    val labels = mutableListOf("All tasks", "Due soon (no date or next 30 days)", "Starred only", "Overdue only")
    for ((id, name) in snap.categories) {
      keys.add("cat:$id")
      labels.add("Category: $name")
      keys.add("cat:$id+soon")
      labels.add("Category: $name, due soon")
    }
    AlertDialog.Builder(this)
        .setTitle("Show in this widget")
        .setItems(labels.toTypedArray()) { _, which ->
          WidgetData.setFilter(this, widgetId, keys[which])
          pickLook(showRows)
        }
        .setOnCancelListener { done() }
        .show()
  }

  private fun pickLook(showRows: Boolean) {
    val keys = mutableListOf("light", "dark", "clear")
    val labels = mutableListOf("Light background", "Dark background", "See-through background")
    if (showRows) {
      keys.addAll(listOf("light+compact", "dark+compact", "clear+compact"))
      labels.addAll(listOf("Light, compact rows", "Dark, compact rows", "See-through, compact rows"))
    }
    AlertDialog.Builder(this)
        .setTitle("How should it look?")
        .setItems(labels.toTypedArray()) { _, which ->
          val k = keys[which]
          WidgetData.setLook(this, widgetId, k.removeSuffix("+compact"), k.endsWith("+compact"))
          done()
        }
        .setOnCancelListener { done() }
        .show()
  }

  private fun pickTask(snap: Snapshot) {
    val tasks = snap.tasks.filter { it.steps.isNotEmpty() }
    if (tasks.isEmpty()) {
      AlertDialog.Builder(this)
          .setTitle("No checklists yet")
          .setMessage("Add steps to a task in the app first, then place this widget.")
          .setPositiveButton("OK") { _, _ -> finish() }
          .setOnCancelListener { finish() }
          .show()
      return
    }
    AlertDialog.Builder(this)
        .setTitle("Which checklist?")
        .setItems(tasks.map { "${it.title} (${it.steps.count { s -> s.done }}/${it.steps.size})" }.toTypedArray()) { _, which ->
          WidgetData.setFilter(this, widgetId, "task:" + tasks[which].id)
          pickLook(showRows = false)
        }
        .setOnCancelListener { finish() }
        .show()
  }

  /** Board and matrix widgets: everything, or one category. */
  private fun pickCategoryFilter(snap: Snapshot) {
    if (snap.categories.isEmpty()) {
      WidgetData.setFilter(this, widgetId, "all")
      pickLook(showRows = false)
      return
    }
    val keys = mutableListOf("all")
    val labels = mutableListOf("All categories")
    for ((id, name) in snap.categories) {
      keys.add("cat:$id")
      labels.add("Only $name")
    }
    AlertDialog.Builder(this)
        .setTitle("Show in this widget")
        .setItems(labels.toTypedArray()) { _, which ->
          WidgetData.setFilter(this, widgetId, keys[which])
          pickLook(showRows = false)
        }
        .setOnCancelListener { done() }
        .show()
  }

  /** Burn-down: everything, one category, or (item 86) one task that has its own burn-down. */
  private fun pickBurn(snap: Snapshot) {
    val burn = snap.root.optJSONObject("burn")
    val keys = mutableListOf("all")
    val labels = mutableListOf("All categories")
    for ((id, name) in snap.categories) {
      keys.add("cat:$id")
      labels.add("Only $name")
    }
    for (t in snap.all) {
      if (burn?.has("task:" + t.id) != true) continue
      keys.add("task:" + t.id)
      labels.add("Task: ${t.title}")
    }
    if (keys.size == 1) {
      WidgetData.setFilter(this, widgetId, "all")
      pickLook(showRows = false)
      return
    }
    AlertDialog.Builder(this)
        .setTitle("Show in this widget")
        .setItems(labels.toTypedArray()) { _, which ->
          WidgetData.setFilter(this, widgetId, keys[which])
          pickLook(showRows = false)
        }
        .setOnCancelListener { done() }
        .show()
  }

  /** Worked today (items 75 and 78): one category, everything, or the habits. */
  private fun pickWorked(snap: Snapshot) {
    val keys = mutableListOf("habits", "all")
    val labels = mutableListOf("Habits", "All open tasks")
    for ((id, name) in snap.categories) {
      keys.add("cat:$id")
      labels.add("Tasks in $name")
    }
    AlertDialog.Builder(this)
        .setTitle("Show in this widget")
        .setItems(labels.toTypedArray()) { _, which ->
          WidgetData.setFilter(this, widgetId, keys[which])
          pickLook(showRows = false)
        }
        .setOnCancelListener { done() }
        .show()
  }

  /** Now doing: the task longest in a stage, or one board task. */
  private fun pickNow(snap: Snapshot) {
    val keys = mutableListOf<String>()
    val labels = mutableListOf<String>()
    for (s in snap.stages.dropLast(1)) {
      keys.add("stage:" + s.id)
      labels.add("The task longest in ${s.name}")
    }
    for (t in snap.all.filter { it.stage != null }) {
      keys.add("task:" + t.id)
      labels.add("Always: ${t.title}")
    }
    if (keys.isEmpty()) {
      WidgetData.setFilter(this, widgetId, "all")
      pickLook(showRows = false)
      return
    }
    AlertDialog.Builder(this)
        .setTitle("Which task?")
        .setItems(labels.toTypedArray()) { _, which ->
          WidgetData.setFilter(this, widgetId, keys[which])
          pickLook(showRows = false)
        }
        .setOnCancelListener { done() }
        .show()
  }

  private fun pickCategory(snap: Snapshot) {
    val keys = mutableListOf("all")
    val labels = mutableListOf("No category (ask each time)")
    for ((id, name) in snap.categories) {
      keys.add("cat:$id")
      labels.add("Straight into: $name")
    }
    AlertDialog.Builder(this)
        .setTitle("New tasks go…")
        .setItems(labels.toTypedArray()) { _, which ->
          WidgetData.setFilter(this, widgetId, keys[which])
          done()
        }
        .setOnCancelListener { done() }
        .show()
  }

  companion object {
    /** Item 115: the week widgets ask only how they look, then the focus mode. */
    val weekWidgets = setOf("WeekMonthWidget", "BusyMonthWidget", "WeekBoardWidget", "BusyBoardWidget", "WeekLoadWidget", "WeekDayWidget")

    /** Item 108: widgets that list tasks, so can have a focus mode of their own. */
    val modeWidgets =
        setOf(
            "TaskListWidget", "CompactWidget", "TodayWidget", "FocusWidget", "CalendarWidget", "DayPlanWidget",
            "BoardSummaryWidget", "StageListWidget", "NowDoingWidget", "BoardStepsWidget", "MatrixWidget",
            "WorkedTodayWidget", "FocusTimerWidget",
            // Item 115.
            "WeekMonthWidget", "BusyMonthWidget", "WeekBoardWidget", "BusyBoardWidget", "WeekLoadWidget", "WeekDayWidget")
  }
}
