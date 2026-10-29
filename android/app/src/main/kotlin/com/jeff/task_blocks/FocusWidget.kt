package com.jeff.task_blocks

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent

/** One big block for the top task: the first starred one, else the next due, else the first. */
class FocusWidget : AppWidgetProvider() {
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
      val ids = m.getAppWidgetIds(ComponentName(c, FocusWidget::class.java))
      if (ids.isEmpty()) return
      val snap = WidgetData.snapshot(c)
      for (id in ids) update(c, m, id, snap)
    }

    fun pick(tasks: List<WidgetTask>): WidgetTask? {
      val open = tasks.filter { !it.locked }
      return open.firstOrNull { it.star }
          ?: open.filter { it.due != null }.minByOrNull { it.due!! }
          ?: open.firstOrNull()
    }

    fun update(c: Context, m: AppWidgetManager, id: Int, snap: Snapshot) {
      val views = RemoteViews(c.packageName, R.layout.widget_focus)
      val look = WidgetData.look(c, id)
      val t = pick(WidgetData.tasks(c, snap, WidgetData.filter(c, id)))
      if (t == null) {
        views.setInt(R.id.f_root, "setBackgroundResource", look.background)
        views.setTextColor(R.id.f_title, look.faint)
        views.setTextViewText(R.id.f_title, "All done")
        views.setTextViewText(R.id.f_due, "")
        views.setViewVisibility(R.id.f_tick, View.GONE)
      } else {
        views.setInt(R.id.f_root, "setBackgroundColor", WidgetData.color(snap, t))
        views.setTextColor(R.id.f_title, 0xDD000000.toInt())
        views.setTextViewText(R.id.f_title, (if (t.star) "★ " else "") + t.title)
        val due = t.due
        views.setTextViewText(
            R.id.f_due,
            when {
              due == null -> ""
              due < System.currentTimeMillis() -> "Overdue · " + WidgetData.dueLabel(due)
              else -> "Due " + WidgetData.dueLabel(due)
            })
        views.setViewVisibility(R.id.f_tick, View.VISIBLE)
        views.setOnClickPendingIntent(R.id.f_tick, WidgetActionActivity.action(c, id, "done", t.id))
        views.setOnClickPendingIntent(R.id.f_text, WidgetActionActivity.action(c, id, "open", t.id))
      }
      if (t == null) {
        views.setOnClickPendingIntent(
            R.id.f_root,
            HomeWidgetLaunchIntent.getActivity(c, MainActivity::class.java, Uri.parse("taskblocks://home")),
        )
      }
      m.updateAppWidget(id, views)
    }
  }
}

/** Done this week and the current streak. */
class StatsWidget : AppWidgetProvider() {
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
      val ids = m.getAppWidgetIds(ComponentName(c, StatsWidget::class.java))
      if (ids.isEmpty()) return
      val snap = WidgetData.snapshot(c)
      for (id in ids) update(c, m, id, snap)
    }

    fun update(c: Context, m: AppWidgetManager, id: Int, snap: Snapshot) {
      val views = RemoteViews(c.packageName, R.layout.widget_stats)
      val look = WidgetData.look(c, id)
      look.apply(views, R.id.s_root, intArrayOf(R.id.s_week, R.id.s_streak), intArrayOf(R.id.s_week_label, R.id.s_streak_label))
      views.setTextViewText(R.id.s_week, "${snap.doneThisWeek}")
      views.setTextViewText(R.id.s_streak, "${snap.streak}")
      views.setTextViewText(R.id.s_streak_label, if (snap.streak == 1) "day streak" else "day streak")
      views.setOnClickPendingIntent(
          R.id.s_root,
          HomeWidgetLaunchIntent.getActivity(c, MainActivity::class.java, Uri.parse("taskblocks://stats")),
      )
      m.updateAppWidget(id, views)
    }
  }
}

/** The steps of one task, tickable from the home screen. */
class ChecklistWidget : AppWidgetProvider() {
  override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
    val snap = WidgetData.snapshot(context)
    for (id in ids) update(context, manager, id, snap)
    manager.notifyAppWidgetViewDataChanged(ids, R.id.widget_list)
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
      val ids = m.getAppWidgetIds(ComponentName(c, ChecklistWidget::class.java))
      if (ids.isEmpty()) return
      val snap = WidgetData.snapshot(c)
      for (id in ids) update(c, m, id, snap)
      m.notifyAppWidgetViewDataChanged(ids, R.id.widget_list)
    }

    fun update(c: Context, m: AppWidgetManager, id: Int, snap: Snapshot) {
      val views = RemoteViews(c.packageName, R.layout.widget_checklist)
      val look = WidgetData.look(c, id)
      look.apply(views, R.id.widget_root, intArrayOf(R.id.widget_title), intArrayOf(R.id.widget_empty))
      val taskId = WidgetData.filter(c, id).removePrefix("task:")
      val t = snap.task(taskId)
      val progress = if (t == null || t.steps.isEmpty()) "" else "  ${t.steps.count { it.done }}/${t.steps.size}"
      views.setTextViewText(R.id.widget_title, (t?.title ?: "Checklist") + progress)
      val service =
          Intent(c, ChecklistService::class.java).apply {
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
            putExtra("task", taskId)
            data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
          }
      @Suppress("DEPRECATION") views.setRemoteAdapter(R.id.widget_list, service)
      views.setEmptyView(R.id.widget_list, R.id.widget_empty)
      views.setPendingIntentTemplate(R.id.widget_list, WidgetActionActivity.template(c))
      views.setOnClickPendingIntent(
          R.id.widget_title,
          HomeWidgetLaunchIntent.getActivity(
              c, MainActivity::class.java, Uri.parse("taskblocks://open?id=" + Uri.encode(taskId))),
      )
      m.updateAppWidget(id, views)
    }
  }
}

/** Rows of [ChecklistWidget]. */
class ChecklistService : android.widget.RemoteViewsService() {
  override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
      Factory(applicationContext, intent.getStringExtra("task") ?: "")

  class Factory(private val c: Context, private val taskId: String) : RemoteViewsFactory {
    private var steps: List<WidgetStep> = emptyList()

    override fun onCreate() {}

    override fun onDataSetChanged() {
      steps = WidgetData.snapshot(c).task(taskId)?.steps ?: emptyList()
    }

    override fun onDestroy() {}

    override fun getCount(): Int = steps.size

    override fun getViewAt(position: Int): RemoteViews {
      val v = RemoteViews(c.packageName, R.layout.widget_check_row)
      val s = steps.getOrNull(position) ?: return v
      v.setImageViewResource(R.id.row_tick, if (s.done) R.drawable.ic_widget_box_checked else R.drawable.ic_widget_box)
      v.setTextViewText(R.id.row_title, s.title)
      v.setInt(R.id.row_title, "setPaintFlags", if (s.done) android.graphics.Paint.STRIKE_THRU_TEXT_FLAG or android.graphics.Paint.ANTI_ALIAS_FLAG else android.graphics.Paint.ANTI_ALIAS_FLAG)
      if (!s.done) {
        v.setOnClickFillInIntent(R.id.row, Intent().putExtra("op", "step").putExtra("id", taskId).putExtra("step", s.id))
      } else {
        v.setOnClickFillInIntent(R.id.row, Intent().putExtra("op", "open").putExtra("id", taskId))
      }
      return v
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = false
  }
}
