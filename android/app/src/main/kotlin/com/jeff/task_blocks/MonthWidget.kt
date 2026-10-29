package com.jeff.task_blocks

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/** A small month grid with a dot on each day that has a task due. Tap a day to open it. */
class MonthWidget : AppWidgetProvider() {
  override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
    for (id in ids) update(context, manager, id)
    manager.notifyAppWidgetViewDataChanged(ids, R.id.month_grid)
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
      val ids = m.getAppWidgetIds(ComponentName(c, MonthWidget::class.java))
      if (ids.isEmpty()) return
      for (id in ids) update(c, m, id)
      m.notifyAppWidgetViewDataChanged(ids, R.id.month_grid)
    }

    fun update(c: Context, m: AppWidgetManager, id: Int) {
      val views = RemoteViews(c.packageName, R.layout.widget_month)
      val look = WidgetData.look(c, id)
      val dayNames = intArrayOf(R.id.d1, R.id.d2, R.id.d3, R.id.d4, R.id.d5, R.id.d6, R.id.d7)
      look.apply(views, R.id.month_root, intArrayOf(R.id.month_title), dayNames)
      views.setTextViewText(R.id.month_title, SimpleDateFormat("MMMM", Locale.getDefault()).format(Calendar.getInstance().time))
      val service =
          Intent(c, MonthService::class.java).apply {
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
            putExtra("theme", look.theme)
            data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
          }
      @Suppress("DEPRECATION") views.setRemoteAdapter(R.id.month_grid, service)
      views.setPendingIntentTemplate(R.id.month_grid, WidgetActionActivity.template(c))
      views.setOnClickPendingIntent(
          R.id.month_title,
          HomeWidgetLaunchIntent.getActivity(c, MainActivity::class.java, Uri.parse("taskblocks://day")),
      )
      m.updateAppWidget(id, views)
    }
  }
}

/** The 42 cells of [MonthWidget]. */
class MonthService : RemoteViewsService() {
  override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
      Factory(applicationContext, intent.getStringExtra("theme") ?: "light")

  class Factory(private val c: Context, private val theme: String) : RemoteViewsFactory {
    private var cells: List<Cell> = emptyList()

    data class Cell(val day: Int, val key: String, val inMonth: Boolean, val today: Boolean, val due: Int, val faded: Boolean)

    override fun onCreate() {}

    override fun onDataSetChanged() {
      val snap = WidgetData.snapshot(c)
      val cal = Calendar.getInstance()
      val todayKey = key(cal)
      val month = cal.get(Calendar.MONTH)
      cal.set(Calendar.DAY_OF_MONTH, 1)
      // Back to the Monday on or before the 1st.
      val back = (cal.get(Calendar.DAY_OF_WEEK) + 5) % 7
      cal.add(Calendar.DAY_OF_MONTH, -back)
      val out = ArrayList<Cell>()
      for (i in 0 until 42) {
        val k = key(cal)
        val d = snap.dueDays[k]
        out.add(Cell(cal.get(Calendar.DAY_OF_MONTH), k, cal.get(Calendar.MONTH) == month, k == todayKey, d?.first ?: 0, d?.second ?: false))
        cal.add(Calendar.DAY_OF_MONTH, 1)
      }
      cells = out
    }

    private fun key(cal: Calendar): String =
        String.format(Locale.US, "%04d-%02d-%02d", cal.get(Calendar.YEAR), cal.get(Calendar.MONTH) + 1, cal.get(Calendar.DAY_OF_MONTH))

    override fun onDestroy() {}

    override fun getCount(): Int = cells.size

    override fun getViewAt(position: Int): RemoteViews {
      val v = RemoteViews(c.packageName, R.layout.widget_month_cell)
      val cell = cells.getOrNull(position) ?: return v
      val ink = if (theme == "light") 0xDD000000.toInt() else 0xEEFFFFFF.toInt()
      val faint = if (theme == "light") 0x55000000.toInt() else 0x66FFFFFF.toInt()
      v.setTextViewText(R.id.cell_day, "${cell.day}")
      v.setTextColor(R.id.cell_day, if (cell.inMonth) ink else faint)
      v.setInt(R.id.cell_day, "setBackgroundResource", if (cell.today) R.drawable.widget_today_ring else 0)
      v.setViewVisibility(R.id.cell_dot, if (cell.due > 0) View.VISIBLE else View.INVISIBLE)
      v.setInt(R.id.cell_dot, "setColorFilter", if (cell.faded) faint else 0xFF2E7D32.toInt())
      v.setOnClickFillInIntent(R.id.cell_root, Intent().putExtra("op", "day").putExtra("d", cell.key))
      return v
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = true
  }
}
