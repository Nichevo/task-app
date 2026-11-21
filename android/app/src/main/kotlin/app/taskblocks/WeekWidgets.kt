package app.taskblocks

import android.Manifest
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.net.Uri
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.BackgroundColorSpan
import android.text.style.StyleSpan
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import org.json.JSONObject

/**
 * Item 115: the week and month widgets with two clocks:
 * - A [WeekMonthWidget]: the month with dots, the week's list.
 * - G [BusyMonthWidget]: the month shaded by how busy each day is, the week's list.
 * - B [WeekBoardWidget]: the week as 7 columns (the month a tap away).
 * - H [BusyBoardWidget]: the same with each day shaded by how busy it is.
 * - I [WeekLoadWidget]: one row per day: how full it is and what is on.
 * - J [WeekDayWidget]: 7 shaded day tiles; tap one to list that day, with tick boxes.
 *
 * The app shares the week's tasks, dated steps and work meetings and how busy each day is
 * (lib/week_widgets.dart); the phone's calendar events are added here. Each widget follows its own
 * focus mode choice, like the list widgets.
 */
data class WeekItem(
    val day: String,
    val id: String,
    val step: String?,
    val title: String,
    val task: String?,
    val at: Long?,
    val end: Long?,
    /** "task", "step", "meet" (work meeting) or "event" (phone calendar). */
    val kind: String,
    val minutes: Int,
    val over: Boolean,
) {
  val isEvent: Boolean
    get() = kind == "meet" || kind == "event"
}

/** The week as one widget sees it. */
class WeekView(val snap: Snapshot, val days: List<String>, val items: List<WeekItem>, val busy: Map<String, Int>, val workday: Int) {
  fun on(day: String): List<WeekItem> = items.filter { it.day == day }

  fun minutes(day: String): Int = busy[day] ?: 0

  fun level(day: String): Int = Week.level(minutes(day), workday)
}

object Week {
  private const val DAY = WidgetData.DAY
  val heat = intArrayOf(0xFFEEF2F2.toInt(), 0xFFCFE9DC.toInt(), 0xFF93D3B2.toInt(), 0xFF4FAE83.toInt(), 0xFF1F7A55.toInt())
  const val EVENT = 0xFFE3EBF7.toInt()
  const val TEAL = 0xFF006A6A.toInt()

  fun level(minutes: Int, workday: Int): Int {
    if (minutes <= 0) return 0
    val f = minutes.toDouble() / maxOf(60, workday)
    return if (f < 0.25) 1 else if (f < 0.55) 2 else if (f < 0.85) 3 else 4
  }

  fun inkOn(level: Int): Int = if (level >= 3) 0xFFFFFFFF.toInt() else 0xDD000000.toInt()

  fun key(ms: Long): String = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(ms))

  fun parseKey(k: String): Long =
      try {
        SimpleDateFormat("yyyy-MM-dd", Locale.US).parse(k)!!.time
      } catch (e: Exception) {
        WidgetData.startOfDay(System.currentTimeMillis())
      }

  private fun json(snap: Snapshot): JSONObject = snap.root.optJSONObject("week") ?: JSONObject()

  /** The week for widget [id]: what its focus mode hides is left out, phone events added. */
  fun view(c: Context, id: Int): WeekView {
    val snap = WidgetData.snapshot(c).forWidget(c, id)
    val w = json(snap)
    val dArr = w.optJSONArray("days")
    val days =
        if (dArr != null && dArr.length() > 0) (0 until dArr.length()).map { dArr.optString(it) }
        else (0 until 7).map { key(WidgetData.startOfDay(System.currentTimeMillis()) + it * DAY + DAY / 2) }
    val today = key(System.currentTimeMillis())
    val out = ArrayList<WeekItem>()
    val arr = w.optJSONArray("items")
    if (arr != null) {
      for (i in 0 until arr.length()) {
        val o = arr.getJSONObject(i)
        val kind = o.optString("kind")
        val tid = o.optString("id")
        val step = o.optString("step").ifEmpty { null }
        if (kind == "task" || kind == "step") {
          val t = snap.tasks.firstOrNull { it.id == tid } ?: continue
          if (step != null && t.steps.any { it.id == step && it.done }) continue
        }
        var day = o.optString("day")
        // Overdue things stay on today when the day changes before the app is opened.
        if (day < today && (kind == "task" || kind == "step")) day = today
        if (day < today && !days.contains(day)) continue
        out.add(
            WeekItem(
                day, tid, step, o.optString("title"), o.optString("task").ifEmpty { null },
                if (o.has("at")) o.optLong("at") else null, if (o.has("end")) o.optLong("end") else null,
                kind, o.optInt("min"), o.optBoolean("over") || o.optString("day") < today))
      }
    }
    val busy = HashMap<String, Int>()
    val bObj = w.optJSONObject("busy")
    if (bObj != null) for (k in bObj.keys()) busy[k] = bObj.optInt(k)
    if (days.isNotEmpty()) {
      val from = parseKey(days.first())
      for (e in events(c, from, parseKey(days.last()) + DAY)) {
        out.add(WeekItem(key(e.start), "ev:" + e.id, null, e.title, null, if (e.allDay) null else e.start, if (e.allDay) null else e.end, "event", 0, false))
      }
    }
    // Phone events count as busy too (the app only knows tasks and work meetings).
    val monthFrom = monthStart(0) - 7 * DAY
    for (e in events(c, monthFrom, monthFrom + 84 * DAY)) {
      if (e.allDay) continue
      val k = key(e.start)
      busy[k] = (busy[k] ?: 0) + ((e.end - e.start) / 60_000L).toInt().coerceAtLeast(0)
    }
    out.sortWith(compareBy<WeekItem>({ it.day }, { if (it.over) 0 else 1 }, { it.at ?: Long.MAX_VALUE }))
    return WeekView(snap, days, out, busy, w.optInt("workday", 480))
  }

  private fun events(c: Context, from: Long, to: Long): List<DeviceEvent> {
    if (c.checkSelfPermission(Manifest.permission.READ_CALENDAR) != PackageManager.PERMISSION_GRANTED) return emptyList()
    return try {
      CalendarStore.events(c, from, to, emptySet())
    } catch (e: Exception) {
      emptyList()
    }
  }

  /** The first of this month moved by [offset] months, at local midnight. */
  fun monthStart(offset: Int): Long =
      Calendar.getInstance()
          .apply {
            set(Calendar.DAY_OF_MONTH, 1)
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            add(Calendar.MONTH, offset)
          }
          .timeInMillis

  fun time(c: Context, ms: Long, zone: TimeZone? = null): String {
    val f =
        if (android.text.format.DateFormat.is24HourFormat(c)) SimpleDateFormat("HH:mm", Locale.getDefault())
        else SimpleDateFormat("h:mm a", Locale.getDefault())
    if (zone != null) f.timeZone = zone
    return f.format(Date(ms)).replace(":00 ", " ").lowercase(Locale.getDefault())
  }

  /** "Today · Sun 22" or "Mon 23". */
  fun dayLabel(k: String, long: Boolean = false): String {
    val ms = parseKey(k)
    val name = SimpleDateFormat(if (long) "EEEE d" else "EEE d", Locale.getDefault()).format(Date(ms))
    return if (k == key(System.currentTimeMillis())) "Today · $name" else name
  }

  fun hours(minutes: Int): String {
    if (minutes <= 0) return ""
    val h = minutes / 60.0
    return if (h < 1) "${minutes}m" else if (h == Math.floor(h)) "${h.toInt()} h" else String.format(Locale.US, "%.1f h", h)
  }

  /** The colour of an item's row or chip: the task's age colour, or pale blue for events. */
  fun colour(v: WeekView, i: WeekItem): Int {
    if (i.isEvent) return EVENT
    val t = v.snap.task(i.id) ?: return 0xFFBFE99A.toInt()
    return WidgetData.color(v.snap, t)
  }

  fun subtitle(c: Context, i: WeekItem): String =
      when {
        i.over -> "overdue"
        i.at != null -> time(c, i.at)
        i.kind == "step" -> i.task ?: "step"
        else -> ""
      }

  /** The clock strip: this phone's time and the second city's (or nothing when turned off). */
  fun clocks(c: Context, views: RemoteViews, snap: Snapshot, look: Look) {
    val o = json(snap).optJSONObject("clocks") ?: JSONObject()
    if (!o.optBoolean("on", true)) {
      views.setViewVisibility(R.id.clk_root, View.GONE)
      return
    }
    views.setViewVisibility(R.id.clk_root, View.VISIBLE)
    val home = o.optString("home").ifEmpty { TimeZone.getDefault().id.substringAfterLast('/').replace('_', ' ') }
    views.setTextViewText(R.id.clk_home, home)
    views.setTextViewText(R.id.clk_city, o.optString("city", "Jingzhou"))
    views.setString(R.id.clk_city_time, "setTimeZone", o.optString("zone", "Asia/Shanghai"))
    for (id in intArrayOf(R.id.clk_home_time, R.id.clk_city_time)) views.setTextColor(id, look.ink)
    for (id in intArrayOf(R.id.clk_home, R.id.clk_city)) views.setTextColor(id, look.faint)
  }

  fun launch(c: Context, uri: String): PendingIntent = HomeWidgetLaunchIntent.getActivity(c, MainActivity::class.java, Uri.parse(uri))

  /** A tap that the widget handles itself (flip the month, switch a view, pick a day). */
  fun op(c: Context, widget: Int, op: String, arg: String = ""): PendingIntent {
    val i =
        Intent(c, WeekWidgetReceiver::class.java).apply {
          action = "app.taskblocks.WEEK_OP"
          putExtra("widget", widget)
          putExtra("op", op)
          putExtra("arg", arg)
          data = Uri.parse("taskblocks-week://$widget/$op/$arg")
        }
    return PendingIntent.getBroadcast(c, (widget * 31 + op.hashCode() * 7 + arg.hashCode()), i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
  }

  fun service(c: Context, cls: Class<*>, id: Int, extras: Map<String, String> = emptyMap()): Intent =
      Intent(c, cls).apply {
        putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
        for ((k, v) in extras) putExtra(k, v)
        data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
      }

  /** A small bar: how much of the working day is booked. */
  fun bar(minutes: Int, workday: Int, dark: Boolean): Bitmap {
    val w = 96
    val h = 16
    val b = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
    val cv = Canvas(b)
    val p = Paint(Paint.ANTI_ALIAS_FLAG)
    p.color = if (dark) 0x33FFFFFF else heat[0]
    cv.drawRoundRect(RectF(0f, 0f, w.toFloat(), h.toFloat()), 8f, 8f, p)
    val f = (minutes.toDouble() / maxOf(60, workday)).coerceIn(0.0, 1.0)
    if (f > 0) {
      p.color = heat[level(minutes, workday).coerceAtLeast(1)]
      cv.drawRoundRect(RectF(0f, 0f, maxOf(h.toFloat(), (w * f).toFloat()), h.toFloat()), 8f, 8f, p)
    }
    return b
  }

  fun prefs(c: Context) = WidgetData.prefs(c)

  fun monthOffset(c: Context, id: Int): Int = prefs(c).getInt("wmoff_$id", 0)

  /** Every week widget, to redraw after the app shares new data or a day starts. */
  val providers =
      listOf(
          WeekMonthWidget::class.java,
          BusyMonthWidget::class.java,
          WeekBoardWidget::class.java,
          BusyBoardWidget::class.java,
          WeekLoadWidget::class.java,
          WeekDayWidget::class.java,
      )

  fun update(c: Context, cls: Class<*>, ids: IntArray) {
    val m = AppWidgetManager.getInstance(c)
    val p = cls.getDeclaredConstructor().newInstance() as WeekWidgetBase
    p.onUpdate(c, m, ids)
  }
}

/** Handles the taps the week widgets deal with themselves. */
class WeekWidgetReceiver : BroadcastReceiver() {
  override fun onReceive(c: Context, intent: Intent) {
    val id = intent.getIntExtra("widget", 0)
    val arg = intent.getStringExtra("arg") ?: ""
    val e = Week.prefs(c).edit()
    when (intent.getStringExtra("op")) {
      "prev" -> e.putInt("wmoff_$id", Week.monthOffset(c, id) - 1)
      "next" -> e.putInt("wmoff_$id", Week.monthOffset(c, id) + 1)
      "today" -> e.putInt("wmoff_$id", 0)
      "toggle" -> e.putBoolean("wbmonth_$id", !Week.prefs(c).getBoolean("wbmonth_$id", false))
      "pick" -> e.putString("wjday_$id", arg).putLong("wjday_at_$id", System.currentTimeMillis())
    }
    e.apply()
    val m = AppWidgetManager.getInstance(c)
    val cls = m.getAppWidgetInfo(id)?.provider?.className ?: return
    val p = Week.providers.firstOrNull { it.name == cls } ?: return
    Week.update(c, p, intArrayOf(id))
  }
}

/** What all six share: refresh, resize and clean-up. */
abstract class WeekWidgetBase : AppWidgetProvider() {
  abstract fun draw(c: Context, m: AppWidgetManager, id: Int)

  abstract val lists: IntArray

  override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
    for (id in ids) {
      try {
        draw(context, manager, id)
      } catch (e: Exception) {
        android.util.Log.e("WeekWidgets", "draw failed", e)
      }
    }
    for (l in lists) manager.notifyAppWidgetViewDataChanged(ids, l)
  }

  override fun onEnabled(context: Context) = WidgetRefreshJob.schedule(context)

  override fun onDisabled(context: Context) = WidgetRefreshJob.cancelIfNoWidgets(context)

  override fun onDeleted(context: Context, ids: IntArray) {
    WidgetData.forget(context, ids)
    val e = Week.prefs(context).edit()
    for (id in ids) e.remove("wmoff_$id").remove("wbmonth_$id").remove("wjday_$id").remove("wjday_at_$id")
    e.apply()
  }

  override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, newOptions: android.os.Bundle) =
      onUpdate(context, manager, intArrayOf(id))
}

/** A: this month with dots on busy days, and the week's list. */
open class WeekMonthWidget : WeekWidgetBase() {
  open val heat = false
  override val lists = intArrayOf(R.id.wm_grid, R.id.wm_list)

  override fun draw(c: Context, m: AppWidgetManager, id: Int) {
    val views = RemoteViews(c.packageName, R.layout.widget_week_month)
    val look = WidgetData.look(c, id)
    val names = intArrayOf(R.id.wm_d1, R.id.wm_d2, R.id.wm_d3, R.id.wm_d4, R.id.wm_d5, R.id.wm_d6, R.id.wm_d7)
    look.apply(views, R.id.wm_root, intArrayOf(R.id.wm_title, R.id.wm_week), names + R.id.wm_empty)
    for (b in intArrayOf(R.id.wm_add, R.id.wm_prev, R.id.wm_next)) views.setInt(b, "setColorFilter", look.ink)
    Week.clocks(c, views, WidgetData.snapshot(c), look)
    val off = Week.monthOffset(c, id)
    views.setTextViewText(R.id.wm_title, SimpleDateFormat(if (off == 0) "MMMM" else "MMM yyyy", Locale.getDefault()).format(Date(Week.monthStart(off))))
    @Suppress("DEPRECATION")
    views.setRemoteAdapter(R.id.wm_grid, Week.service(c, WeekMonthService::class.java, id, mapOf("theme" to look.theme, "heat" to heat.toString())))
    views.setPendingIntentTemplate(R.id.wm_grid, WidgetActionActivity.template(c))
    @Suppress("DEPRECATION")
    views.setRemoteAdapter(R.id.wm_list, Week.service(c, WeekListService::class.java, id, mapOf("theme" to look.theme)))
    views.setEmptyView(R.id.wm_list, R.id.wm_empty)
    views.setPendingIntentTemplate(R.id.wm_list, WidgetActionActivity.template(c))
    views.setOnClickPendingIntent(R.id.wm_prev, Week.op(c, id, "prev"))
    views.setOnClickPendingIntent(R.id.wm_next, Week.op(c, id, "next"))
    views.setOnClickPendingIntent(R.id.wm_title, Week.op(c, id, "today"))
    views.setOnClickPendingIntent(R.id.wm_week, Week.launch(c, "taskblocks://day"))
    views.setOnClickPendingIntent(R.id.wm_add, Week.launch(c, "taskblocks://add"))
    m.updateAppWidget(id, views)
  }
}

/** G: as A, with the month shaded by how busy each day is. */
class BusyMonthWidget : WeekMonthWidget() {
  override val heat = true
}

/** B: the week as 7 columns; the month button swaps in the month. */
open class WeekBoardWidget : WeekWidgetBase() {
  open val heat = false
  override val lists = intArrayOf(R.id.wb_grid)

  override fun draw(c: Context, m: AppWidgetManager, id: Int) {
    val views = RemoteViews(c.packageName, R.layout.widget_week_board)
    val look = WidgetData.look(c, id)
    val names = intArrayOf(R.id.wb_d1, R.id.wb_d2, R.id.wb_d3, R.id.wb_d4, R.id.wb_d5, R.id.wb_d6, R.id.wb_d7)
    look.apply(views, R.id.wb_root, intArrayOf(R.id.wb_title), names + R.id.wb_toggle)
    views.setInt(R.id.wb_add, "setColorFilter", look.ink)
    val snap = WidgetData.snapshot(c)
    Week.clocks(c, views, snap, look)
    val month = Week.prefs(c).getBoolean("wbmonth_$id", false)
    val v = Week.view(c, id)
    val title =
        if (month) SimpleDateFormat("MMMM yyyy", Locale.getDefault()).format(Date())
        else if (v.days.isEmpty()) ""
        else {
          val a = Week.parseKey(v.days.first())
          val b = Week.parseKey(v.days.last())
          SimpleDateFormat("d", Locale.getDefault()).format(Date(a)) + " – " + SimpleDateFormat("d MMMM", Locale.getDefault()).format(Date(b))
        }
    views.setTextViewText(R.id.wb_title, title)
    views.setTextViewText(R.id.wb_toggle, if (month) "▤ week" else "▦ month")
    views.setViewVisibility(R.id.wb_names, if (month) View.VISIBLE else View.GONE)
    views.setInt(R.id.wb_grid, "setNumColumns", if (month) 7 else maxOf(1, v.days.size))
    val service =
        if (month) Week.service(c, WeekMonthService::class.java, id, mapOf("theme" to look.theme, "heat" to heat.toString(), "rows" to "6"))
        else Week.service(c, WeekBoardService::class.java, id, mapOf("theme" to look.theme, "heat" to heat.toString()))
    @Suppress("DEPRECATION") views.setRemoteAdapter(R.id.wb_grid, service)
    views.setPendingIntentTemplate(R.id.wb_grid, WidgetActionActivity.template(c))
    views.setOnClickPendingIntent(R.id.wb_toggle, Week.op(c, id, "toggle"))
    views.setOnClickPendingIntent(R.id.wb_title, Week.launch(c, "taskblocks://day"))
    views.setOnClickPendingIntent(R.id.wb_add, Week.launch(c, "taskblocks://add"))
    m.updateAppWidget(id, views)
  }
}

/** H: as B, with each day shaded by how busy it is and the hours it adds up to. */
class BusyBoardWidget : WeekBoardWidget() {
  override val heat = true
}

/** I: one row per day: how full it is and what is on. */
class WeekLoadWidget : WeekWidgetBase() {
  override val lists = intArrayOf(R.id.wl_list)

  override fun draw(c: Context, m: AppWidgetManager, id: Int) {
    val views = RemoteViews(c.packageName, R.layout.widget_week_load)
    val look = WidgetData.look(c, id)
    look.apply(views, R.id.wl_root, intArrayOf(R.id.wl_title))
    views.setInt(R.id.wl_add, "setColorFilter", look.ink)
    Week.clocks(c, views, WidgetData.snapshot(c), look)
    @Suppress("DEPRECATION")
    views.setRemoteAdapter(R.id.wl_list, Week.service(c, WeekLoadService::class.java, id, mapOf("theme" to look.theme)))
    views.setPendingIntentTemplate(R.id.wl_list, WidgetActionActivity.template(c))
    views.setOnClickPendingIntent(R.id.wl_title, Week.launch(c, "taskblocks://day"))
    views.setOnClickPendingIntent(R.id.wl_add, Week.launch(c, "taskblocks://add"))
    m.updateAppWidget(id, views)
  }
}

/** J: 7 shaded day tiles; tap one to list that day below, with tick boxes. */
class WeekDayWidget : WeekWidgetBase() {
  override val lists = intArrayOf(R.id.wj_list)

  companion object {
    val tiles = intArrayOf(R.id.wj_t1, R.id.wj_t2, R.id.wj_t3, R.id.wj_t4, R.id.wj_t5, R.id.wj_t6, R.id.wj_t7)

    /** The day picked on widget [id]: back to today once the pick is from an earlier day. */
    fun picked(c: Context, id: Int, days: List<String>): String {
      val p = Week.prefs(c)
      val k = p.getString("wjday_$id", null)
      val at = p.getLong("wjday_at_$id", 0L)
      val today = Week.key(System.currentTimeMillis())
      return if (k != null && days.contains(k) && Week.key(at) == today) k else days.firstOrNull { it >= today } ?: days.firstOrNull() ?: today
    }
  }

  override fun draw(c: Context, m: AppWidgetManager, id: Int) {
    val views = RemoteViews(c.packageName, R.layout.widget_week_day)
    val look = WidgetData.look(c, id)
    look.apply(views, R.id.wj_root, intArrayOf(R.id.wj_title), intArrayOf(R.id.wj_empty))
    views.setInt(R.id.wj_add, "setColorFilter", look.ink)
    Week.clocks(c, views, WidgetData.snapshot(c), look)
    val v = Week.view(c, id)
    val day = picked(c, id, v.days)
    val today = Week.key(System.currentTimeMillis())
    for ((i, t) in tiles.withIndex()) {
      val k = v.days.getOrNull(i)
      if (k == null) {
        views.setViewVisibility(t, View.GONE)
        continue
      }
      views.setViewVisibility(t, View.VISIBLE)
      val lvl = v.level(k)
      val ms = Week.parseKey(k)
      val sb = SpannableStringBuilder()
      sb.append(SimpleDateFormat("EEE", Locale.getDefault()).format(Date(ms))).append("\n")
      val s = sb.length
      sb.append(SimpleDateFormat("d", Locale.getDefault()).format(Date(ms)))
      sb.setSpan(StyleSpan(android.graphics.Typeface.BOLD), s, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
      sb.setSpan(android.text.style.RelativeSizeSpan(1.35f), s, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
      val h = Week.hours(v.minutes(k))
      if (h.isNotEmpty()) sb.append("\n").append(h)
      views.setTextViewText(t, sb)
      views.setInt(t, "setBackgroundColor", if (k == day) Week.TEAL else Week.heat[lvl])
      views.setTextColor(t, if (k == day || lvl >= 3) 0xFFFFFFFF.toInt() else 0xDD000000.toInt())
      views.setOnClickPendingIntent(t, Week.op(c, id, "pick", k))
    }
    val mins = v.minutes(day)
    val free = maxOf(0, v.workday - mins)
    val head = Week.dayLabel(day, long = true).removePrefix("Today · ").let { if (day == today) "Today · $it" else it }
    views.setTextViewText(
        R.id.wj_title,
        if (mins > 0) "$head · ${Week.hours(mins)} booked, ${Week.hours(free).ifEmpty { "no time" }} free" else head)
    @Suppress("DEPRECATION")
    views.setRemoteAdapter(R.id.wj_list, Week.service(c, WeekListService::class.java, id, mapOf("theme" to look.theme, "day" to day)))
    views.setEmptyView(R.id.wj_list, R.id.wj_empty)
    views.setPendingIntentTemplate(R.id.wj_list, WidgetActionActivity.template(c))
    views.setOnClickPendingIntent(R.id.wj_title, Week.launch(c, "taskblocks://day?d=" + Uri.encode(day)))
    views.setOnClickPendingIntent(R.id.wj_add, Week.launch(c, "taskblocks://add"))
    m.updateAppWidget(id, views)
  }
}

/** The month grid of A, G and the board's month view: dots, or shaded by how busy. */
class WeekMonthService : RemoteViewsService() {
  override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
      Factory(
          applicationContext,
          intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, 0),
          intent.getStringExtra("theme") ?: "light",
          intent.getStringExtra("heat") == "true",
      )

  class Factory(private val c: Context, private val id: Int, private val theme: String, private val heat: Boolean) : RemoteViewsFactory {
    data class Cell(val day: Int, val key: String, val inMonth: Boolean, val today: Boolean, val inWeek: Boolean, val level: Int, val due: Boolean)

    private var cells: List<Cell> = emptyList()

    override fun onCreate() {}

    override fun onDataSetChanged() {
      val v = Week.view(c, id)
      val cal = Calendar.getInstance()
      cal.timeInMillis = Week.monthStart(Week.monthOffset(c, id))
      val month = cal.get(Calendar.MONTH)
      cal.add(Calendar.DAY_OF_MONTH, -((cal.get(Calendar.DAY_OF_WEEK) + 5) % 7))
      val today = Week.key(System.currentTimeMillis())
      val out = ArrayList<Cell>()
      for (i in 0 until 42) {
        val k = Week.key(cal.timeInMillis)
        val dueN = v.snap.dueDays[k]?.first ?: 0
        val any = dueN > 0 || v.items.any { it.day == k } || v.minutes(k) > 0
        out.add(Cell(cal.get(Calendar.DAY_OF_MONTH), k, cal.get(Calendar.MONTH) == month, k == today, v.days.contains(k), v.level(k), any))
        cal.add(Calendar.DAY_OF_MONTH, 1)
      }
      cells = out
    }

    override fun onDestroy() {}

    override fun getCount(): Int = cells.size

    override fun getViewAt(position: Int): RemoteViews {
      val v = RemoteViews(c.packageName, R.layout.widget_month_cell_small)
      val cell = cells.getOrNull(position) ?: return v
      val dark = theme != "light"
      val ink = if (dark) 0xEEFFFFFF.toInt() else 0xDD000000.toInt()
      val faint = if (dark) 0x66FFFFFF else 0x55000000
      v.setTextViewText(R.id.cell_day, "${cell.day}")
      when {
        heat && cell.inMonth -> {
          v.setViewVisibility(R.id.cell_bg, View.VISIBLE)
          v.setInt(R.id.cell_bg, "setColorFilter", if (cell.level == 0 && dark) 0x22FFFFFF else Week.heat[cell.level])
          v.setTextColor(R.id.cell_day, if (cell.level == 0 && dark) ink else Week.inkOn(cell.level))
          v.setViewVisibility(R.id.cell_dot, View.GONE)
        }
        else -> {
          v.setViewVisibility(R.id.cell_bg, if (cell.inWeek || cell.today) View.VISIBLE else View.INVISIBLE)
          v.setInt(R.id.cell_bg, "setColorFilter", if (cell.today) Week.TEAL else if (dark) 0x33FFFFFF else 0xFFE1EFEE.toInt())
          v.setTextColor(R.id.cell_day, if (cell.today) 0xFFFFFFFF.toInt() else if (cell.inMonth) ink else faint)
          v.setViewVisibility(R.id.cell_dot, if (cell.due && cell.inMonth && !cell.today) View.VISIBLE else View.INVISIBLE)
          v.setInt(R.id.cell_dot, "setColorFilter", 0xFF2E7D32.toInt())
        }
      }
      if (heat && !cell.inMonth) {
        v.setViewVisibility(R.id.cell_bg, View.INVISIBLE)
        v.setTextColor(R.id.cell_day, faint)
      }
      // Today: a red ring on the shaded month (its shade still shows how busy it is).
      if (heat && cell.today) v.setInt(R.id.cell_root, "setBackgroundResource", R.drawable.widget_today_ring_red)
      v.setOnClickFillInIntent(R.id.cell_root, Intent().putExtra("op", "day").putExtra("d", cell.key))
      return v
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = true
  }
}

/** The week's list (A, G) or one day's (J): day headings, then tasks, steps and events. */
class WeekListService : RemoteViewsService() {
  override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
      Factory(applicationContext, intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, 0), intent.getStringExtra("day"))

  class Factory(private val c: Context, private val id: Int, private val onlyDay: String?) : RemoteViewsFactory {
    private var view: WeekView? = null

    /** A heading (String) or an item. */
    private var rows: List<Any> = emptyList()

    override fun onCreate() {}

    override fun onDataSetChanged() {
      val v = Week.view(c, id)
      view = v
      val out = ArrayList<Any>()
      if (onlyDay != null) {
        // J picks its day when it draws; read it again in case it changed since.
        val day = WeekDayWidget.picked(c, id, v.days)
        out.addAll(v.on(day))
      } else {
        for (d in v.days) {
          val on = v.on(d)
          if (on.isEmpty()) continue
          val mins = v.minutes(d)
          out.add(Week.dayLabel(d) + if (d != Week.key(System.currentTimeMillis()) && mins >= 60) " · ${Week.hours(mins)} booked" else "")
          out.addAll(on)
        }
      }
      rows = out
    }

    override fun onDestroy() {}

    override fun getCount(): Int = rows.size

    override fun getViewAt(position: Int): RemoteViews {
      val r = rows.getOrNull(position) ?: return RemoteViews(c.packageName, R.layout.widget_week_head)
      val v = view ?: return RemoteViews(c.packageName, R.layout.widget_week_head)
      if (r is String) {
        val h = RemoteViews(c.packageName, R.layout.widget_week_head)
        h.setTextViewText(R.id.wk_head, r)
        h.setTextColor(R.id.wk_head, if (r.startsWith("Today")) Week.TEAL else 0xAA556666.toInt())
        return h
      }
      val i = r as WeekItem
      val row = RemoteViews(c.packageName, R.layout.widget_week_item)
      row.setInt(R.id.wi_row, "setBackgroundColor", if (i.over) 0xFFF2B0AA.toInt() else Week.colour(v, i))
      row.setTextViewText(R.id.wi_title, if (i.kind == "step" && i.task != null) "${i.title} · ${i.task}" else i.title)
      row.setTextViewText(R.id.wi_time, Week.subtitle(c, i).let { if (i.kind == "step" && !i.over && i.at == null) "" else it })
      if (i.isEvent) {
        row.setImageViewResource(R.id.wi_tick, R.drawable.ic_widget_event)
        row.setOnClickFillInIntent(R.id.wi_text, Intent().putExtra("op", "day").putExtra("d", i.day))
        row.setOnClickFillInIntent(R.id.wi_tick, Intent().putExtra("op", "day").putExtra("d", i.day))
        return row
      }
      row.setImageViewResource(R.id.wi_tick, R.drawable.ic_widget_box)
      row.setOnClickFillInIntent(
          R.id.wi_tick,
          if (i.step != null) Intent().putExtra("op", "step").putExtra("id", i.id).putExtra("step", i.step)
          else Intent().putExtra("op", "done").putExtra("id", i.id))
      row.setOnClickFillInIntent(R.id.wi_text, Intent().putExtra("op", "open").putExtra("id", i.id))
      return row
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 2

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = false
  }
}

/** B and H: the 7 columns, laid out row by row (the day headings first, then each day's nth item). */
class WeekBoardService : RemoteViewsService() {
  override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
      Factory(applicationContext, intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, 0), intent.getStringExtra("heat") == "true")

  class Factory(private val c: Context, private val id: Int, private val heat: Boolean) : RemoteViewsFactory {
    private var view: WeekView? = null

    /** Day keys for the headings, then items (null = an empty space in a shorter column). */
    private var cells: List<Any?> = emptyList()
    private var cols = 7

    override fun onCreate() {}

    override fun onDataSetChanged() {
      val v = Week.view(c, id)
      view = v
      cols = maxOf(1, v.days.size)
      val per = v.days.map { v.on(it) }
      val rows = minOf(6, per.maxOfOrNull { it.size } ?: 0)
      val out = ArrayList<Any?>()
      out.addAll(v.days)
      for (r in 0 until rows) {
        for ((d, list) in per.withIndex()) {
          // The last row shows "+N" when a day has more than fits.
          if (r == rows - 1 && list.size > rows) out.add("+${list.size - rows + 1}|${v.days[d]}") else out.add(list.getOrNull(r))
        }
      }
      cells = out
    }

    override fun onDestroy() {}

    override fun getCount(): Int = cells.size

    override fun getViewAt(position: Int): RemoteViews {
      val v = view ?: return RemoteViews(c.packageName, R.layout.widget_board_cell)
      val x = cells.getOrNull(position)
      val today = Week.key(System.currentTimeMillis())
      if (position < cols && x is String) {
        val d = RemoteViews(c.packageName, R.layout.widget_board_day)
        val ms = Week.parseKey(x)
        val lvl = v.level(x)
        d.setTextViewText(R.id.bd_name, SimpleDateFormat("EEE", Locale.getDefault()).format(Date(ms)))
        d.setTextViewText(R.id.bd_num, SimpleDateFormat("d", Locale.getDefault()).format(Date(ms)))
        d.setTextViewText(R.id.bd_sub, if (heat) Week.hours(v.minutes(x)) else "•".repeat(minOf(3, v.on(x).size)))
        val bg = if (x == today && !heat) Week.TEAL else if (heat) Week.heat[lvl] else 0xFFEEF4F4.toInt()
        d.setInt(R.id.bd_root, "setBackgroundColor", bg)
        val ink = if ((x == today && !heat) || (heat && lvl >= 3)) 0xFFFFFFFF.toInt() else 0xDD000000.toInt()
        for (t in intArrayOf(R.id.bd_name, R.id.bd_num, R.id.bd_sub)) d.setTextColor(t, ink)
        if (heat && x == today) d.setInt(R.id.bd_name, "setBackgroundResource", R.drawable.widget_today_ring_red)
        d.setOnClickFillInIntent(R.id.bd_root, Intent().putExtra("op", "day").putExtra("d", x))
        return d
      }
      val cell = RemoteViews(c.packageName, R.layout.widget_board_cell)
      when (x) {
        null -> {
          cell.setInt(R.id.bc_root, "setBackgroundColor", 0)
          cell.setTextViewText(R.id.bc_title, "")
          cell.setTextViewText(R.id.bc_sub, "")
          cell.setViewVisibility(R.id.bc_sub, View.GONE)
        }
        is String -> {
          val (more, day) = x.split("|").let { it[0] to it.getOrElse(1) { "" } }
          cell.setInt(R.id.bc_root, "setBackgroundColor", 0)
          cell.setTextViewText(R.id.bc_title, more)
          cell.setTextColor(R.id.bc_title, 0x99000000.toInt())
          cell.setViewVisibility(R.id.bc_sub, View.GONE)
          cell.setOnClickFillInIntent(R.id.bc_root, Intent().putExtra("op", "day").putExtra("d", day))
        }
        is WeekItem -> {
          cell.setInt(R.id.bc_root, "setBackgroundColor", if (x.over) 0xFFF2B0AA.toInt() else Week.colour(v, x))
          cell.setTextViewText(R.id.bc_title, x.title)
          cell.setTextColor(R.id.bc_title, if (x.isEvent) 0xFF1F3D6B.toInt() else 0xDD000000.toInt())
          val sub = Week.subtitle(c, x)
          cell.setTextViewText(R.id.bc_sub, sub)
          cell.setViewVisibility(R.id.bc_sub, if (sub.isEmpty()) View.GONE else View.VISIBLE)
          cell.setOnClickFillInIntent(
              R.id.bc_root,
              if (x.isEvent) Intent().putExtra("op", "day").putExtra("d", x.day) else Intent().putExtra("op", "open").putExtra("id", x.id))
        }
      }
      return cell
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 2

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = false
  }
}

/** I: a row per day: its name, a bar for how full it is, and its things as coloured chips. */
class WeekLoadService : RemoteViewsService() {
  override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
      Factory(applicationContext, intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, 0), intent.getStringExtra("theme") ?: "light")

  class Factory(private val c: Context, private val id: Int, private val theme: String) : RemoteViewsFactory {
    private var view: WeekView? = null

    override fun onCreate() {}

    override fun onDataSetChanged() {
      view = Week.view(c, id)
    }

    override fun onDestroy() {}

    override fun getCount(): Int = view?.days?.size ?: 0

    override fun getViewAt(position: Int): RemoteViews {
      val row = RemoteViews(c.packageName, R.layout.widget_load_row)
      val v = view ?: return row
      val k = v.days.getOrNull(position) ?: return row
      val today = k == Week.key(System.currentTimeMillis())
      val dark = theme != "light"
      row.setTextViewText(R.id.lr_day, if (today) "TODAY" else SimpleDateFormat("EEE d", Locale.getDefault()).format(Date(Week.parseKey(k))))
      row.setTextColor(R.id.lr_day, if (today) Week.TEAL else if (dark) 0xCCFFFFFF.toInt() else 0xAA000000.toInt())
      row.setImageViewBitmap(R.id.lr_bar, Week.bar(v.minutes(k), v.workday, dark))
      val sb = SpannableStringBuilder()
      for (i in v.on(k)) {
        if (sb.isNotEmpty()) sb.append("  ")
        val s = sb.length
        sb.append(" ").append(i.title)
        val sub = Week.subtitle(c, i).let { if (i.kind == "step") "" else it }
        if (sub.isNotEmpty()) sb.append(" ").append(sub)
        sb.append(" ")
        sb.setSpan(BackgroundColorSpan(if (i.over) 0xFFF2B0AA.toInt() else Week.colour(v, i)), s, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        sb.setSpan(StyleSpan(android.graphics.Typeface.BOLD), s, s + 1 + i.title.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        sb.setSpan(android.text.style.ForegroundColorSpan(if (i.isEvent) 0xFF1F3D6B.toInt() else 0xDD000000.toInt()), s, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
      }
      row.setTextViewText(R.id.lr_items, sb)
      row.setOnClickFillInIntent(R.id.lr_root, Intent().putExtra("op", "day").putExtra("d", k))
      return row
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = false
  }
}
