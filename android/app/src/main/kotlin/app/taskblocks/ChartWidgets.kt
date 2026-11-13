package app.taskblocks

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.graphics.Path
import android.net.Uri
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import org.json.JSONArray
import org.json.JSONObject

/*
 * Item 75: the Worked today widget. Item 77: the Added vs done and burn-down chart widgets,
 * drawn here as pictures from the numbers the app shares (lib/home_widgets.dart), so they stay
 * right without the app running.
 */

private val dayFormat = SimpleDateFormat("yyyy-MM-dd", Locale.US)

private fun dayOffset(key: String, days: Int): String {
  val cal = Calendar.getInstance()
  cal.time = dayFormat.parse(key) ?: return key
  cal.add(Calendar.DAY_OF_MONTH, days)
  return dayFormat.format(cal.time)
}

/** The seven days (yyyy-MM-dd) of this week, Monday first. */
fun thisWeek(): List<String> {
  val cal = Calendar.getInstance()
  val back = (cal.get(Calendar.DAY_OF_WEEK) + 5) % 7 // Monday = 0
  cal.add(Calendar.DAY_OF_MONTH, -back)
  val monday = dayFormat.format(cal.time)
  return (0 until 7).map { dayOffset(monday, it) }
}

/** The category key a chart widget shows: "" for everything. */
private fun chartKey(f: String): String = if (f.startsWith("cat:")) f.removePrefix("cat:") else ""

/** A bitmap the size of the widget's chart area. */
private fun chartBitmap(c: Context, m: AppWidgetManager, id: Int): Bitmap {
  val o = m.getAppWidgetOptions(id)
  val d = c.resources.displayMetrics.density
  val wDp = o.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 250).coerceAtLeast(120)
  val hDp = o.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 180).coerceAtLeast(110)
  val w = (wDp * d).toInt().coerceIn(200, 1200)
  val h = ((hDp - 62) * d).toInt().coerceIn(80, 900)
  return Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
}

private fun paint(colour: Int, width: Float, d: Float) =
    Paint(Paint.ANTI_ALIAS_FLAG).apply {
      color = colour
      strokeWidth = width * d
      style = Paint.Style.STROKE
      strokeJoin = Paint.Join.ROUND
    }

private fun ints(a: JSONArray?): List<Int> = if (a == null) emptyList() else (0 until a.length()).map { a.optInt(it) }

private fun doubles(a: JSONArray?): List<Double> = if (a == null) emptyList() else (0 until a.length()).map { a.optDouble(it) }

/** Item 75: one category's open tasks, a circle on each to tick today as a day worked on it. */
class WorkedTodayWidget : BaseWidget() {
  override val listId: Int = R.id.widget_list

  companion object {
    /** Open tasks in the category, or with the "habits" choice, the habits (due today first). */
    fun tasks(snap: Snapshot, f: String): List<WidgetTask> =
        if (f == "habits") snap.habits.sortedBy { if (it.locked) 1 else 0 }
        else snap.tasks.filter { WidgetData.inCategory(it, f) && !it.locked }
  }

  override fun draw(c: Context, m: AppWidgetManager, id: Int, snap: Snapshot) {
    val views = RemoteViews(c.packageName, R.layout.widget_board_steps)
    val look = WidgetData.look(c, id)
    val f = WidgetData.filter(c, id)
    look.apply(views, R.id.widget_root, intArrayOf(R.id.widget_title), intArrayOf(R.id.widget_empty))
    val list = tasks(snap, f)
    val today = WidgetData.todayKey()
    val n = list.count { it.worked.contains(today) }
    if (f == "habits") {
      // Habits not due today (enough this week already) don't count against today.
      val due = list.count { !it.locked || it.worked.contains(today) }
      views.setTextViewText(R.id.widget_title, "Habits today · $n of $due")
      views.setTextViewText(R.id.widget_empty, "No habits yet. Turn on \"Habit\" on a task in the app.")
      views.setOnClickPendingIntent(R.id.widget_title, BoardLook.launch(c, "taskblocks://habits"))
    } else {
      views.setTextViewText(R.id.widget_title, BoardLook.categoryTitle(snap, "Worked today", f) + " · $n of ${list.size}")
      views.setTextViewText(R.id.widget_empty, "No open tasks here.")
      views.setOnClickPendingIntent(R.id.widget_title, BoardLook.launch(c, "taskblocks://achievements"))
    }
    val service =
        Intent(c, WorkedTodayService::class.java).apply {
          putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
          putExtra("filter", f)
          data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
        }
    @Suppress("DEPRECATION") views.setRemoteAdapter(R.id.widget_list, service)
    views.setEmptyView(R.id.widget_list, R.id.widget_empty)
    views.setPendingIntentTemplate(R.id.widget_list, WidgetActionActivity.template(c))
    m.updateAppWidget(id, views)
  }
}

/** Rows of [WorkedTodayWidget]: the circle, the title, and the week as seven dots. */
class WorkedTodayService : RemoteViewsService() {
  override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
      Factory(applicationContext, intent.getStringExtra("filter") ?: "all")

  class Factory(private val c: Context, private val filter: String) : RemoteViewsFactory {
    private var items: List<WidgetTask> = emptyList()
    private var week: List<String> = emptyList()
    private var today = ""

    override fun onCreate() {}

    override fun onDataSetChanged() {
      items = WorkedTodayWidget.tasks(WidgetData.snapshot(c), filter)
      week = thisWeek()
      today = WidgetData.todayKey()
    }

    override fun onDestroy() {}

    override fun getCount(): Int = items.size

    override fun getViewAt(position: Int): RemoteViews {
      val v = RemoteViews(c.packageName, R.layout.widget_worked_row)
      val t = items.getOrNull(position) ?: return v
      val on = t.worked.contains(today)
      v.setImageViewResource(R.id.row_tick, if (on) R.drawable.ic_widget_circle_done else R.drawable.ic_widget_circle)
      v.setContentDescription(R.id.row_tick, if (on) "Worked on it today, tap to untick" else "Tick: worked on it today")
      v.setTextViewText(R.id.row_title, t.title)
      val dots = week.joinToString("") { d -> if (t.worked.contains(d)) "●" else if (d > today) "·" else "○" }
      val count = week.count { t.worked.contains(it) }
      val extra =
          if (filter == "habits") {
            if (t.streak > 0) "streak ${t.streak} ${t.streakUnit}${if (t.streak == 1) "" else "s"}" else ""
          } else if (count > 0) "$count this week" else ""
      v.setTextViewText(R.id.row_meta, if (extra.isEmpty()) dots else "$dots  $extra")
      v.setOnClickFillInIntent(
          R.id.row_tick, Intent().putExtra("op", "worked").putExtra("id", t.id).putExtra("day", today).putExtra("on", (!on).toString()))
      v.setOnClickFillInIntent(R.id.row_text, Intent().putExtra("op", "open").putExtra("id", t.id))
      return v
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = false
  }
}

/** Item 77: the Statistics page's Added vs done chart for the last 4 weeks, for one category. */
class AddedDoneWidget : BaseWidget() {
  override fun draw(c: Context, m: AppWidgetManager, id: Int, snap: Snapshot) {
    val views = RemoteViews(c.packageName, R.layout.widget_chart)
    val look = WidgetData.look(c, id)
    val f = WidgetData.filter(c, id)
    look.apply(views, R.id.c_root, intArrayOf(R.id.c_title), intArrayOf(R.id.c_note))
    views.setTextViewText(R.id.c_title, BoardLook.categoryTitle(snap, "Added vs done", f))
    val o = snap.root.optJSONObject("addedDone")?.optJSONObject(chartKey(f)) ?: JSONObject()
    val added = ints(o.optJSONArray("added"))
    val done = ints(o.optJSONArray("done"))
    val open = ints(o.optJSONArray("open"))
    val bmp = chartBitmap(c, m, id)
    drawAddedDone(Canvas(bmp), bmp.width.toFloat(), bmp.height.toFloat(), c.resources.displayMetrics.density, added, done, open, look)
    views.setImageViewBitmap(R.id.c_chart, bmp)
    views.setTextViewText(
        R.id.c_note,
        "Last 4 weeks: ${added.sum()} added (blue), ${done.sum()} done (green), ${open.lastOrNull() ?: 0} open now (line)")
    views.setOnClickPendingIntent(R.id.c_root, BoardLook.launch(c, "taskblocks://stats"))
    m.updateAppWidget(id, views)
  }

  private fun drawAddedDone(cv: Canvas, w: Float, h: Float, d: Float, added: List<Int>, done: List<Int>, open: List<Int>, look: Look) {
    val n = maxOf(added.size, 1)
    val pad = 4 * d
    val top = maxOf((added + done).maxOrNull() ?: 0, 1).toFloat()
    val openTop = maxOf(open.maxOrNull() ?: 0, 1).toFloat()
    val slot = (w - 2 * pad) / n
    val bar = (slot * 0.4f).coerceAtLeast(1f)
    val base = h - pad
    val usable = h - 2 * pad
    cv.drawLine(pad, base, w - pad, base, paint(look.faint, 1f, d))
    val blue = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFF5B8DEF.toInt() }
    val green = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFF43A047.toInt() }
    for (i in added.indices) {
      val x = pad + i * slot + slot * 0.1f
      cv.drawRect(x, base - usable * added[i] / top, x + bar, base, blue)
      val dn = done.getOrElse(i) { 0 }
      cv.drawRect(x + bar, base - usable * dn / top, x + 2 * bar, base, green)
    }
    if (open.isNotEmpty()) {
      val path = Path()
      for (i in open.indices) {
        val x = pad + i * slot + slot / 2
        val y = base - usable * open[i] / openTop
        if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
      }
      cv.drawPath(path, paint(0xFFE65100.toInt(), 2f, d))
    }
  }
}

/** Item 77: the Gantt chart's burn-down for one category; a tap opens the chart on it. */
class BurnDownWidget : BaseWidget() {
  override fun draw(c: Context, m: AppWidgetManager, id: Int, snap: Snapshot) {
    val views = RemoteViews(c.packageName, R.layout.widget_chart)
    val look = WidgetData.look(c, id)
    val f = WidgetData.filter(c, id)
    look.apply(views, R.id.c_root, intArrayOf(R.id.c_title), intArrayOf(R.id.c_note))
    // Item 86: set to one task, it shows that task's steps and a tap opens the task.
    val taskId = if (f.startsWith("task:")) f.removePrefix("task:") else null
    if (taskId != null) {
      val name = snap.all.firstOrNull { it.id == taskId }?.title ?: "task"
      views.setTextViewText(R.id.c_title, "Burn-down · $name")
      views.setOnClickPendingIntent(R.id.c_root, BoardLook.launch(c, "taskblocks://open?id=" + Uri.encode(taskId)))
    } else {
      views.setTextViewText(R.id.c_title, BoardLook.categoryTitle(snap, "Burn-down", f))
      views.setOnClickPendingIntent(R.id.c_root, BoardLook.launch(c, "taskblocks://gantt?cat=" + Uri.encode(chartKey(f))))
    }
    val key = if (taskId != null) f else chartKey(f)
    val o = snap.root.optJSONObject("burn")?.optJSONObject(key)
    val bmp = chartBitmap(c, m, id)
    if (o == null) {
      views.setImageViewBitmap(R.id.c_chart, bmp)
      views.setTextViewText(R.id.c_note,
          if (taskId != null) "This task needs two or more steps and a date to finish by."
          else "Nothing with dates on the Gantt chart here yet.")
    } else {
      drawBurn(Canvas(bmp), bmp.width.toFloat(), bmp.height.toFloat(), c.resources.displayMetrics.density, o, look)
      views.setImageViewBitmap(R.id.c_chart, bmp)
      views.setTextViewText(R.id.c_note, o.optString("summary"))
    }
    m.updateAppWidget(id, views)
  }

  private fun days(a: String, b: String): Int {
    val x = dayFormat.parse(a) ?: return 0
    val y = dayFormat.parse(b) ?: return 0
    return Math.round((y.time - x.time) / 86_400_000.0).toInt()
  }

  private fun drawBurn(cv: Canvas, w: Float, h: Float, d: Float, o: JSONObject, look: Look) {
    val from = o.optString("from")
    val end = o.optString("end")
    val total = o.optDouble("total", 0.0).coerceAtLeast(1.0)
    val left = doubles(o.optJSONArray("left"))
    val projected = o.optString("projected").ifEmpty { null }
    val todayIdx = maxOf(left.size - 1, 0)
    val endIdx = days(from, end)
    var lastIdx = maxOf(endIdx, todayIdx)
    if (projected != null) lastIdx = maxOf(lastIdx, minOf(days(from, projected), maxOf(endIdx, 7) * 2))
    val span = maxOf(lastIdx, 1).toFloat()
    val pad = 6 * d
    val cw = w - 2 * pad
    val ch = h - 2 * pad
    fun x(i: Int) = pad + cw * i / span
    fun y(v: Double) = (pad + ch * (1 - v / total)).toFloat()
    cv.drawLine(pad, pad + ch, w - pad, pad + ch, paint(look.faint, 1f, d))
    cv.drawLine(x(todayIdx), pad, x(todayIdx), pad + ch, paint(0x661A5FB4, 1f, d))
    val ideal = paint(look.faint, 1.5f, d).apply { pathEffect = DashPathEffect(floatArrayOf(6 * d, 4 * d), 0f) }
    cv.drawLine(x(0), y(total), x(endIdx), y(0.0), ideal)
    if (left.isNotEmpty()) {
      val path = Path()
      for (i in left.indices) if (i == 0) path.moveTo(x(i), y(left[i])) else path.lineTo(x(i), y(left[i]))
      cv.drawPath(path, paint(0xFF1A5FB4.toInt(), 2.5f, d))
    }
    val now = left.lastOrNull() ?: total
    if (projected != null && now > 0) {
      val p = days(from, projected)
      val late = p > endIdx
      val dots = paint(if (late) 0xFFC62828.toInt() else 0xFF00897B.toInt(), 2f, d).apply {
        pathEffect = DashPathEffect(floatArrayOf(2 * d, 4 * d), 0f)
      }
      val toIdx = minOf(p, lastIdx)
      val toV = if (p <= lastIdx) 0.0 else now * (1 - (lastIdx - todayIdx).toDouble() / maxOf(p - todayIdx, 1))
      cv.drawLine(x(todayIdx), y(now), x(toIdx), y(toV), dots)
    }
  }
}
