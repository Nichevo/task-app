package com.jeff.task_blocks

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent

/** A single + that opens the app ready to type a new task. */
class QuickAddWidget : AppWidgetProvider() {
  override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
    for (id in ids) {
      val views = RemoteViews(context.packageName, R.layout.widget_quick_add)
      views.setOnClickPendingIntent(
          R.id.quick_add,
          HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("taskblocks://add")),
      )
      manager.updateAppWidget(id, views)
    }
  }
}
