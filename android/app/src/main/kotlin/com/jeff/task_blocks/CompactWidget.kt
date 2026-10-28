package com.jeff.task_blocks

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent

/** Small summary: how many tasks are open and overdue, and the next three due. */
class CompactWidget : AppWidgetProvider() {
  override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
    for (id in ids) update(context, manager, id)
  }

  override fun onDeleted(context: Context, ids: IntArray) = WidgetData.forget(context, ids)

  companion object {
    fun updateAll(c: Context) {
      val m = AppWidgetManager.getInstance(c)
      for (id in m.getAppWidgetIds(ComponentName(c, CompactWidget::class.java))) update(c, m, id)
    }

    fun update(c: Context, m: AppWidgetManager, id: Int) {
      val tasks = WidgetData.tasks(c, id)
      val now = System.currentTimeMillis()
      val overdue = tasks.count { val d = it.due; d != null && d < now }
      val views = RemoteViews(c.packageName, R.layout.widget_compact)
      views.setTextViewText(R.id.c_title, WidgetData.filterLabel(c, WidgetData.filter(c, id)))
      views.setTextViewText(
          R.id.c_counts,
          "${tasks.size} open" + if (overdue > 0) " · $overdue overdue" else "",
      )
      val next = tasks.filter { it.due != null && !it.locked }.sortedBy { it.due }.take(3)
      val lines = intArrayOf(R.id.c_next1, R.id.c_next2, R.id.c_next3)
      for ((i, line) in lines.withIndex()) {
        val t = next.getOrNull(i)
        if (t == null) {
          views.setViewVisibility(line, View.GONE)
        } else {
          views.setViewVisibility(line, View.VISIBLE)
          views.setTextViewText(line, WidgetData.dueLabel(t.due!!) + "  " + t.title)
          views.setTextColor(line, if (t.due < now) 0xFFC62828.toInt() else 0xDD000000.toInt())
        }
      }
      if (next.isEmpty()) {
        views.setViewVisibility(R.id.c_next1, View.VISIBLE)
        views.setTextViewText(R.id.c_next1, "Nothing with a due date")
        views.setTextColor(R.id.c_next1, 0x99000000.toInt())
      }
      views.setOnClickPendingIntent(
          R.id.c_root,
          HomeWidgetLaunchIntent.getActivity(c, MainActivity::class.java, Uri.parse("taskblocks://home")),
      )
      m.updateAppWidget(id, views)
    }
  }
}
