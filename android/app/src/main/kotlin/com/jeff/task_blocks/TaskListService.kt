package com.jeff.task_blocks

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService

/** Supplies the rows of [TaskListWidget] and [TodayWidget]. */
class TaskListService : RemoteViewsService() {
  override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
      Factory(
          applicationContext,
          intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, 0),
          intent.getStringExtra("filter") ?: "all",
          intent.getBooleanExtra("compact", false),
      )

  class Factory(
      private val c: Context,
      private val widgetId: Int,
      private val filter: String,
      private val compact: Boolean,
  ) : RemoteViewsFactory {
    private var snap: Snapshot? = null
    private var items: List<WidgetTask> = emptyList()

    override fun onCreate() {}

    override fun onDataSetChanged() {
      val s = WidgetData.snapshot(c)
      snap = s
      items = WidgetData.tasks(c, s, filter)
    }

    override fun onDestroy() {}

    override fun getCount(): Int = items.size

    override fun getViewAt(position: Int): RemoteViews {
      val v = RemoteViews(c.packageName, if (compact) R.layout.widget_row_compact else R.layout.widget_row)
      val t = items.getOrNull(position) ?: return v
      val s = snap ?: return v
      v.setInt(R.id.row, "setBackgroundColor", if (t.event) 0xFFE3EEF6.toInt() else WidgetData.color(s, t))
      val prefix = if (t.star) "★ " else ""
      val progress = if (t.steps.isNotEmpty()) "  ${t.steps.count { it.done }}/${t.steps.size}" else ""
      v.setTextViewText(R.id.row_title, prefix + t.title + progress)
      val due = t.due
      v.setTextViewText(R.id.row_due, if (due == null) "" else WidgetData.dueLabel(due))
      v.setTextColor(R.id.row_due, if (due != null && due < System.currentTimeMillis() && !t.event) 0xFF8B0000.toInt() else 0xDD000000.toInt())
      when {
        t.event -> {
          v.setImageViewResource(R.id.row_tick, R.drawable.ic_widget_event)
          v.setViewVisibility(R.id.row_snooze, View.GONE)
          v.setOnClickFillInIntent(R.id.row_text, Intent().putExtra("op", "home"))
          return v
        }
        t.locked -> {
          v.setImageViewResource(R.id.row_tick, R.drawable.ic_widget_lock)
          v.setViewVisibility(R.id.row_snooze, View.GONE)
        }
        else -> {
          v.setImageViewResource(R.id.row_tick, R.drawable.ic_widget_box)
          v.setOnClickFillInIntent(R.id.row_tick, Intent().putExtra("op", "done").putExtra("id", t.id))
          v.setViewVisibility(R.id.row_snooze, View.VISIBLE)
          v.setOnClickFillInIntent(R.id.row_snooze, Intent().putExtra("op", "snooze").putExtra("id", t.id))
        }
      }
      v.setOnClickFillInIntent(R.id.row_text, Intent().putExtra("op", "open").putExtra("id", t.id))
      return v
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = false
  }
}
