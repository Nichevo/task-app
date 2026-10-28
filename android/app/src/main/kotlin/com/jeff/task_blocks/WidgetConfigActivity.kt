package com.jeff.task_blocks

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
    when {
      provider.endsWith("ChecklistWidget") -> pickTask(snap)
      provider.endsWith("QuickAddWidget") -> pickCategory(snap)
      provider.endsWith("TodayWidget") || provider.endsWith("StatsWidget") || provider.endsWith("MonthWidget") ->
          pickLook(showRows = false)
      else -> pickFilter(snap, showRows = !provider.endsWith("CompactWidget") && !provider.endsWith("FocusWidget"))
    }
  }

  private fun done() {
    WidgetData.refreshAll(this)
    setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId))
    finish()
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
}
