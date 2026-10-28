package com.jeff.task_blocks

import android.app.Activity
import android.app.AlertDialog
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle

/** Asks what a newly placed list or summary widget should show. */
class WidgetConfigActivity : Activity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    val id =
        intent?.extras?.getInt(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
            ?: AppWidgetManager.INVALID_APPWIDGET_ID
    val result = Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
    setResult(RESULT_CANCELED, result)
    if (id == AppWidgetManager.INVALID_APPWIDGET_ID) {
      finish()
      return
    }
    val keys = mutableListOf("all", "soon")
    val labels = mutableListOf("All tasks", "Due soon (no date or next 30 days)")
    for ((catId, name) in WidgetData.categories(this)) {
      keys.add("cat:$catId")
      labels.add("Category: $name")
    }

    fun done(filter: String) {
      WidgetData.setFilter(this, id, filter)
      WidgetData.refreshAll(this)
      setResult(RESULT_OK, result)
      finish()
    }

    AlertDialog.Builder(this)
        .setTitle("Show in this widget")
        .setItems(labels.toTypedArray()) { _, which -> done(keys[which]) }
        .setOnCancelListener { done(WidgetData.filter(this, id)) }
        .show()
  }
}
