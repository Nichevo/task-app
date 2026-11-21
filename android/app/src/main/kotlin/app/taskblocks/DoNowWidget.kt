package app.taskblocks

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import org.json.JSONArray

/**
 * Item 114 C: "Do now", the What should I do now? pick on the home screen. The app works out a
 * few picks ("doNow" in the widget data) each time anything changes; Next goes through them.
 */
class DoNowWidget : AppWidgetProvider() {
  override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
    val snap = WidgetData.snapshot(context)
    for (id in ids) update(context, manager, id, snap)
  }

  override fun onReceive(context: Context, intent: Intent) {
    if (intent.action == ACTION_NEXT) {
      val id = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, -1)
      if (id >= 0) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.edit().putInt("i$id", prefs.getInt("i$id", 0) + 1).apply()
        update(context, AppWidgetManager.getInstance(context), id, WidgetData.snapshot(context))
      }
      return
    }
    super.onReceive(context, intent)
  }

  override fun onEnabled(context: Context) = WidgetRefreshJob.schedule(context)

  override fun onDisabled(context: Context) = WidgetRefreshJob.cancelIfNoWidgets(context)

  override fun onDeleted(context: Context, ids: IntArray) {
    val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
    for (id in ids) prefs.remove("i$id")
    prefs.apply()
  }

  /** Redraws straight away when the launcher resizes the widget (e.g. folding the phone). */
  override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, newOptions: android.os.Bundle) =
      onUpdate(context, manager, intArrayOf(id))

  companion object {
    const val ACTION_NEXT = "app.taskblocks.DO_NOW_NEXT"
    private const val PREFS = "do_now_widget"

    fun updateAll(c: Context) {
      val m = AppWidgetManager.getInstance(c)
      val ids = m.getAppWidgetIds(ComponentName(c, DoNowWidget::class.java))
      if (ids.isEmpty()) return
      val snap = WidgetData.snapshot(c)
      for (id in ids) update(c, m, id, snap)
    }

    private fun open(c: Context, uri: String): PendingIntent =
        HomeWidgetLaunchIntent.getActivity(c, MainActivity::class.java, Uri.parse(uri))

    fun update(c: Context, m: AppWidgetManager, id: Int, snap: Snapshot) {
      val views = RemoteViews(c.packageName, R.layout.widget_do_now)
      val look = WidgetData.look(c, id)
      val dn = snap.root.optJSONObject("doNow")
      val picks = dn?.optJSONArray("picks") ?: JSONArray()
      views.setOnClickPendingIntent(R.id.dn_text, open(c, "taskblocks://now"))
      if (picks.length() == 0) {
        look.apply(views, R.id.dn_root, intArrayOf(R.id.dn_title), intArrayOf(R.id.dn_head, R.id.dn_meta))
        views.setTextViewText(R.id.dn_head, "Do now")
        views.setTextViewText(R.id.dn_title, if (dn == null) "Turned off in Settings" else "Nothing to suggest")
        views.setTextViewText(R.id.dn_meta, "")
        views.setViewVisibility(R.id.dn_buttons, View.GONE)
        m.updateAppWidget(id, views)
        return
      }
      val prefs = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      val p = picks.getJSONObject(Math.floorMod(prefs.getInt("i$id", 0), picks.length()))
      views.setInt(R.id.dn_root, "setBackgroundColor", p.optLong("color", 0xFF93E05BL).toInt())
      for (v in intArrayOf(R.id.dn_title)) views.setTextColor(v, 0xDD000000.toInt())
      for (v in intArrayOf(R.id.dn_head, R.id.dn_meta)) views.setTextColor(v, 0xAA000000.toInt())
      views.setTextViewText(R.id.dn_head, dn.optString("head", "Do now"))
      views.setTextViewText(R.id.dn_title, p.optString("title"))
      views.setTextViewText(R.id.dn_meta, p.optString("meta"))
      views.setViewVisibility(R.id.dn_buttons, View.VISIBLE)
      val step = p.optString("step", "")
      views.setOnClickPendingIntent(
          R.id.dn_focus,
          open(c, "taskblocks://focus?op=start&id=${Uri.encode(p.optString("id"))}" + if (step.isEmpty()) "" else "&step=${Uri.encode(step)}"),
      )
      views.setOnClickPendingIntent(R.id.dn_open, open(c, "taskblocks://open?id=${Uri.encode(p.optString("id"))}"))
      val next = Intent(c, DoNowWidget::class.java).setAction(ACTION_NEXT).putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
      views.setOnClickPendingIntent(
          R.id.dn_next,
          PendingIntent.getBroadcast(c, id, next, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE),
      )
      views.setViewVisibility(R.id.dn_next, if (picks.length() > 1) View.VISIBLE else View.GONE)
      m.updateAppWidget(id, views)
    }
  }
}
