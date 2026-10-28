package com.jeff.task_blocks

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService

/** Supplies the rows of [TaskListWidget]. */
class TaskListService : RemoteViewsService() {
  override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
      Factory(applicationContext, intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, 0))

  class Factory(private val c: Context, private val widgetId: Int) : RemoteViewsFactory {
    private var items: List<WidgetTask> = emptyList()

    override fun onCreate() {}

    override fun onDataSetChanged() {
      items = WidgetData.tasks(c, widgetId)
    }

    override fun onDestroy() {}

    override fun getCount(): Int = items.size

    override fun getViewAt(position: Int): RemoteViews {
      val v = RemoteViews(c.packageName, R.layout.widget_row)
      val t = items.getOrNull(position) ?: return v
      v.setInt(R.id.row, "setBackgroundColor", WidgetData.color(c, t))
      v.setTextViewText(R.id.row_title, (if (t.star) "★ " else "") + t.title)
      val due = t.due
      v.setTextViewText(R.id.row_due, if (due == null) "" else WidgetData.dueLabel(due))
      if (t.locked) {
        v.setImageViewResource(R.id.row_tick, R.drawable.ic_widget_lock)
      } else {
        v.setImageViewResource(R.id.row_tick, R.drawable.ic_widget_box)
        v.setOnClickFillInIntent(R.id.row_tick, Intent().putExtra("op", "done").putExtra("id", t.id))
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
