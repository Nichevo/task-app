package com.jeff.task_blocks

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent

/** Scrolling list of coloured tasks with tick boxes, snooze buttons and a + button. */
open class TaskListWidget : AppWidgetProvider() {
  /** What this widget lists; the Today widget overrides it. */
  open fun filterFor(c: Context, id: Int): String = WidgetData.filter(c, id)

  override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
    val snap = WidgetData.snapshot(context)
    for (id in ids) update(context, manager, id, snap, filterFor(context, id))
    manager.notifyAppWidgetViewDataChanged(ids, R.id.widget_list)
  }

  override fun onEnabled(context: Context) = WidgetRefreshJob.schedule(context)

  override fun onDisabled(context: Context) = WidgetRefreshJob.cancelIfNoWidgets(context)

  override fun onDeleted(context: Context, ids: IntArray) = WidgetData.forget(context, ids)

  companion object {
    fun updateAll(c: Context) {
      val m = AppWidgetManager.getInstance(c)
      val ids = m.getAppWidgetIds(ComponentName(c, TaskListWidget::class.java))
      if (ids.isEmpty()) return
      val snap = WidgetData.snapshot(c)
      for (id in ids) update(c, m, id, snap, WidgetData.filter(c, id))
      m.notifyAppWidgetViewDataChanged(ids, R.id.widget_list)
    }

    fun update(c: Context, m: AppWidgetManager, id: Int, snap: Snapshot, filter: String) {
      val views = RemoteViews(c.packageName, R.layout.widget_list)
      val look = WidgetData.look(c, id)
      look.apply(views, R.id.widget_root, intArrayOf(R.id.widget_title), intArrayOf(R.id.widget_empty))
      views.setInt(R.id.widget_add, "setColorFilter", look.ink)
      views.setTextViewText(R.id.widget_title, WidgetData.filterLabel(c, snap, filter))
      val service =
          Intent(c, TaskListService::class.java).apply {
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
            putExtra("filter", filter)
            putExtra("compact", look.compact)
            // Makes the intent unique per widget so each gets its own list.
            data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
          }
      @Suppress("DEPRECATION") views.setRemoteAdapter(R.id.widget_list, service)
      views.setEmptyView(R.id.widget_list, R.id.widget_empty)
      views.setPendingIntentTemplate(R.id.widget_list, WidgetActionActivity.template(c))
      val addUri =
          if (filter.startsWith("cat:")) "taskblocks://add?cat=" + Uri.encode(filter.removePrefix("cat:").removeSuffix("+soon"))
          else "taskblocks://add"
      views.setOnClickPendingIntent(
          R.id.widget_add,
          HomeWidgetLaunchIntent.getActivity(c, MainActivity::class.java, Uri.parse(addUri)),
      )
      views.setOnClickPendingIntent(
          R.id.widget_title,
          HomeWidgetLaunchIntent.getActivity(c, MainActivity::class.java, Uri.parse("taskblocks://home")),
      )
      m.updateAppWidget(id, views)
    }
  }
}

/** Overdue tasks, tasks due today and today's calendar events. */
class TodayWidget : TaskListWidget() {
  override fun filterFor(c: Context, id: Int): String = "today"

  companion object {
    fun updateAll(c: Context) {
      val m = AppWidgetManager.getInstance(c)
      val ids = m.getAppWidgetIds(ComponentName(c, TodayWidget::class.java))
      if (ids.isEmpty()) return
      val snap = WidgetData.snapshot(c)
      for (id in ids) update(c, m, id, snap, "today")
      m.notifyAppWidgetViewDataChanged(ids, R.id.widget_list)
    }
  }
}
