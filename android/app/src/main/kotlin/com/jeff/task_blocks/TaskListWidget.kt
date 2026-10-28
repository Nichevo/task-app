package com.jeff.task_blocks

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent

/** Scrolling list of coloured tasks with tick boxes and a + button. */
class TaskListWidget : AppWidgetProvider() {
  override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
    for (id in ids) update(context, manager, id)
    manager.notifyAppWidgetViewDataChanged(ids, R.id.widget_list)
  }

  override fun onDeleted(context: Context, ids: IntArray) = WidgetData.forget(context, ids)

  companion object {
    fun updateAll(c: Context) {
      val m = AppWidgetManager.getInstance(c)
      val ids = m.getAppWidgetIds(ComponentName(c, TaskListWidget::class.java))
      for (id in ids) update(c, m, id)
      m.notifyAppWidgetViewDataChanged(ids, R.id.widget_list)
    }

    fun update(c: Context, m: AppWidgetManager, id: Int) {
      val views = RemoteViews(c.packageName, R.layout.widget_list)
      views.setTextViewText(R.id.widget_title, WidgetData.filterLabel(c, WidgetData.filter(c, id)))
      val service =
          Intent(c, TaskListService::class.java).apply {
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
            // Makes the intent unique per widget so each gets its own list.
            data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
          }
      @Suppress("DEPRECATION") views.setRemoteAdapter(R.id.widget_list, service)
      views.setEmptyView(R.id.widget_list, R.id.widget_empty)
      views.setPendingIntentTemplate(R.id.widget_list, WidgetActionActivity.template(c))
      views.setOnClickPendingIntent(
          R.id.widget_add,
          HomeWidgetLaunchIntent.getActivity(c, MainActivity::class.java, Uri.parse("taskblocks://add")),
      )
      views.setOnClickPendingIntent(
          R.id.widget_title,
          HomeWidgetLaunchIntent.getActivity(c, MainActivity::class.java, Uri.parse("taskblocks://home")),
      )
      m.updateAppWidget(id, views)
    }
  }
}
