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
    val snap = WidgetData.snapshot(context)
    for (id in ids) update(context, manager, id, snap)
  }

  override fun onEnabled(context: Context) = WidgetRefreshJob.schedule(context)

  override fun onDisabled(context: Context) = WidgetRefreshJob.cancelIfNoWidgets(context)

  override fun onDeleted(context: Context, ids: IntArray) = WidgetData.forget(context, ids)

  /** Redraws straight away when the launcher resizes the widget (e.g. folding the phone). */
  override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, newOptions: android.os.Bundle) =
      onUpdate(context, manager, intArrayOf(id))

  companion object {
    fun updateAll(c: Context) {
      val m = AppWidgetManager.getInstance(c)
      val ids = m.getAppWidgetIds(ComponentName(c, CompactWidget::class.java))
      if (ids.isEmpty()) return
      val snap = WidgetData.snapshot(c)
      for (id in ids) update(c, m, id, snap)
    }

    fun update(c: Context, m: AppWidgetManager, id: Int, snap: Snapshot) {
      val tasks = WidgetData.tasks(c, snap, WidgetData.filter(c, id))
      val now = System.currentTimeMillis()
      val overdue = tasks.count { val d = it.due; d != null && d < now }
      val views = RemoteViews(c.packageName, R.layout.widget_compact)
      val look = WidgetData.look(c, id)
      val lines = intArrayOf(R.id.c_next1, R.id.c_next2, R.id.c_next3)
      look.apply(views, R.id.c_root, intArrayOf(R.id.c_counts) + lines, intArrayOf(R.id.c_title))
      views.setTextViewText(R.id.c_title, WidgetData.filterLabel(c, snap, WidgetData.filter(c, id)))
      views.setTextViewText(
          R.id.c_counts,
          "${tasks.size} open" + if (overdue > 0) " · $overdue overdue" else "",
      )
      val next = tasks.filter { it.due != null && !it.locked }.sortedBy { it.due }.take(3)
      for ((i, line) in lines.withIndex()) {
        val t = next.getOrNull(i)
        if (t == null) {
          views.setViewVisibility(line, View.GONE)
        } else {
          views.setViewVisibility(line, View.VISIBLE)
          views.setTextViewText(line, WidgetData.dueLabel(t.due!!) + "  " + t.title)
          if (t.due < now) views.setTextColor(line, 0xFFE53935.toInt())
        }
      }
      if (next.isEmpty()) {
        views.setViewVisibility(R.id.c_next1, View.VISIBLE)
        views.setTextViewText(R.id.c_next1, "Nothing with a due date")
        views.setTextColor(R.id.c_next1, look.faint)
      }
      views.setOnClickPendingIntent(
          R.id.c_root,
          HomeWidgetLaunchIntent.getActivity(c, MainActivity::class.java, Uri.parse("taskblocks://home")),
      )
      m.updateAppWidget(id, views)
    }
  }
}
