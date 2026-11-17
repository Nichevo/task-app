package app.taskblocks

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import org.json.JSONObject

/**
 * Item 102, part 4: the focus timer on the home screen. 4x3 (the main size): the ring and
 * countdown with Pause, +5 and Stop on the left, the task and its steps (tick them here) on the
 * right, today's focus time and what is next below. Smaller sizes keep the ring and buttons.
 * With no timer running it offers the top task: Start, or Pick another. Item 108: the buttons
 * work the timer without opening the app (FocusOps); "Pick another" and taps on the text open it.
 * The top task follows the widget's own focus mode choice, and the round lengths the mode's.
 */
class FocusTimerWidget : AppWidgetProvider() {
  override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
    val snap = WidgetData.snapshot(context)
    for (id in ids) update(context, manager, id, snap.forWidget(context, id))
  }

  override fun onEnabled(context: Context) = WidgetRefreshJob.schedule(context)

  override fun onDisabled(context: Context) = WidgetRefreshJob.cancelIfNoWidgets(context)

  override fun onDeleted(context: Context, ids: IntArray) = WidgetData.forget(context, ids)

  override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, newOptions: Bundle) =
      onUpdate(context, manager, intArrayOf(id))

  /** Where the timer stands at a moment: the app's timer moved on through the break. */
  data class State(
      val phase: String,
      val round: Int,
      val end: Long?,
      val leftMs: Long,
      val lengthMs: Long,
      val ready: Boolean,
  ) {
    val running: Boolean
      get() = end != null
    val onBreak: Boolean
      get() = phase != "focus"
  }

  companion object {
    private const val GREEN = 0xFF8FE05A.toInt()
    private const val BLUE = 0xFF7CC6F2.toInt()

    /** The app's timer as it would be at [now], had the app moved it on (as AppStore.tickFocus). */
    fun stateAt(f: JSONObject, lengths: IntArray, now: Long): State {
      var phase = f.optString("phase", "focus")
      var round = f.optInt("round", 1)
      var length = f.optLong("length", 1500) * 1000
      var end: Long? = if (f.has("end")) f.optLong("end") else null
      var ready = f.optBoolean("ready")
      val every = lengths[3].coerceAtLeast(1)
      var guard = 0
      while (end != null && now >= end && guard++ < 4) {
        if (phase == "focus") {
          phase = if (round % every == 0) "longBreak" else "shortBreak"
          length = (if (phase == "longBreak") lengths[2] else lengths[1]) * 60_000L
          end += length
        } else {
          phase = "focus"
          round++
          length = lengths[0] * 60_000L
          end = null
          ready = true
        }
      }
      val left = if (end != null) end - now else if (ready && !f.has("left")) length else f.optLong("left", length / 1000) * 1000
      return State(phase, round, end, if (ready) length else left, length, ready)
    }

    fun update(c: Context, m: AppWidgetManager, id: Int, snap: Snapshot) {
      val v = RemoteViews(c.packageName, R.layout.widget_focus_timer)
      val opts = m.getAppWidgetOptions(id)
      val width = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 250)
      val height = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 200)
      val wide = width >= 230
      val tall = height >= 170
      v.setViewVisibility(R.id.ft_right, if (wide) View.VISIBLE else View.GONE)
      // 2x2 and 4x2: a smaller ring, no footer.
      val short = height < 160
      v.setViewVisibility(R.id.ft_foot, if (short) View.GONE else View.VISIBLE)
      v.setViewVisibility(R.id.ft_round, if (short && !wide) View.GONE else View.VISIBLE)
      if (short && Build.VERSION.SDK_INT >= 31) {
        v.setViewLayoutHeight(R.id.ft_ring_box, 64f, android.util.TypedValue.COMPLEX_UNIT_DIP)
        v.setViewLayoutWidth(R.id.ft_ring_box, 64f, android.util.TypedValue.COMPLEX_UNIT_DIP)
        v.setTextViewTextSize(R.id.ft_clock, android.util.TypedValue.COMPLEX_UNIT_SP, 15f)
      }
      val now = System.currentTimeMillis()
      val f = FocusOps.timer(c, snap)
      val lengths = snap.focusLengths
      val stepRows = intArrayOf(R.id.ft_s1, R.id.ft_s2, R.id.ft_s3, R.id.ft_s4)
      fun link(q: String) = HomeWidgetLaunchIntent.getActivity(c, MainActivity::class.java, Uri.parse("taskblocks://focus$q"))
      val buttons = intArrayOf(R.id.ft_b1, R.id.ft_b2, R.id.ft_b3)
      fun button(i: Int, label: String?, q: String) {
        if (label == null) {
          v.setViewVisibility(buttons[i], View.GONE)
          return
        }
        v.setViewVisibility(buttons[i], View.VISIBLE)
        v.setTextViewText(buttons[i], label)
        // "?op=start&id=..": done right here; "?op=pick" (and anything else) opens the app.
        val parsed = Uri.parse("x://f$q")
        val op = parsed.getQueryParameter("op")
        v.setOnClickPendingIntent(
            buttons[i], if (op == null || op == "pick") link(q) else FocusOps.opIntent(c, id, op, parsed.getQueryParameter("id")))
      }
      if (f == null) {
        // Idle: the top task, ready to start.
        val t = FocusWidget.pick(snap.tasks)
        v.setImageViewBitmap(R.id.ft_ring, ring(1f, GREEN))
        v.setChronometer(R.id.ft_clock, SystemClock.elapsedRealtime() + lengths[0] * 60_000L, null, false)
        v.setTextViewText(R.id.ft_round, "${lengths[0]} min round")
        v.setTextViewText(R.id.ft_title, t?.title ?: "Nothing to focus on")
        val today = t?.let { focusToday(snap, it.id) } ?: 0
        v.setTextViewText(R.id.ft_sub, if (today > 0) "focused ${minutes(today)} today" else "Top task · ready when you are")
        if (t != null) {
          button(0, "▶ Start", "?op=start&id=" + Uri.encode(t.id))
          button(1, "Pick another", "?op=pick")
        } else {
          button(0, null, "")
          button(1, "Pick a task", "?op=pick")
        }
        button(2, null, "")
        fillSteps(c, v, id, t?.id, t?.steps?.map { Triple(it.id, it.title, it.done) } ?: emptyList(), null, stepRows, tall)
        v.setTextViewText(R.id.ft_foot, footer(snap, t?.id))
        v.setOnClickPendingIntent(R.id.ft_text, link(if (t == null) "?op=pick" else "?op=start&id=" + Uri.encode(t.id)))
        m.updateAppWidget(id, v)
        return
      }
      val s = stateAt(f, lengths, now)
      val colour = if (s.onBreak) BLUE else GREEN
      val frac = if (s.lengthMs <= 0) 0f else (s.leftMs.toFloat() / s.lengthMs).coerceIn(0f, 1f)
      v.setImageViewBitmap(R.id.ft_ring, ring(frac, colour))
      if (Build.VERSION.SDK_INT >= 24) v.setChronometerCountDown(R.id.ft_clock, true)
      v.setChronometer(R.id.ft_clock, SystemClock.elapsedRealtime() + s.leftMs, null, s.running)
      v.setTextViewText(
          R.id.ft_round,
          when {
            s.ready -> "Ready for round ${s.round}"
            s.onBreak -> (if (s.phase == "longBreak") "Long break" else "Short break")
            s.running -> "Round ${s.round} of ${lengths[3]}"
            else -> "Round ${s.round} · paused"
          })
      val taskId = f.optString("task")
      v.setTextViewText(R.id.ft_title, f.optString("title"))
      val today = f.optInt("today")
      v.setTextViewText(R.id.ft_sub, if (today > 0) "focused ${minutes(today)} today" else "focusing")
      when {
        s.ready -> {
          button(0, "▶ Round ${s.round}", "?op=resume")
          button(1, null, "")
        }
        s.onBreak -> {
          button(0, "Skip break", "?op=skip")
          button(1, "+5", "?op=add")
        }
        s.running -> {
          button(0, "❚❚ Pause", "?op=pause")
          button(1, "+5", "?op=add")
        }
        else -> {
          button(0, "▶ Resume", "?op=resume")
          button(1, "+5", "?op=add")
        }
      }
      button(2, "Stop", "?op=stop")
      val arr = f.optJSONArray("steps")
      val steps =
          if (arr == null) emptyList()
          else (0 until arr.length()).map {
            val o = arr.getJSONObject(it)
            // Ticked on a widget since counts as ticked.
            val sid = o.optString("id")
            Triple(sid, o.optString("title"), o.optBoolean("done") || snap.task(taskId)?.steps?.any { s -> s.id == sid && s.done } == true)
          }
      fillSteps(c, v, id, taskId, steps, f.optString("step").ifEmpty { null }, stepRows, tall)
      v.setTextViewText(R.id.ft_foot, footer(snap, taskId))
      v.setOnClickPendingIntent(R.id.ft_text, link(""))
      v.setOnClickPendingIntent(R.id.ft_ring_box, link(""))
      m.updateAppWidget(id, v)
      // Redraw the ring each minute, and as the phase ends.
      if (s.running) scheduleRedraw(c, minOf(s.end!! + 500, now + 60_000))
    }

    private fun fillSteps(
        c: Context,
        v: RemoteViews,
        widgetId: Int,
        taskId: String?,
        steps: List<Triple<String, String, Boolean>>,
        current: String?,
        rows: IntArray,
        tall: Boolean,
    ) {
      // The open steps first, the one this session is on at the top.
      val ordered = steps.sortedWith(compareBy({ it.third }, { it.first != current }))
      for ((i, row) in rows.withIndex()) {
        val s = ordered.getOrNull(i)
        if (s == null || !tall || taskId == null) {
          v.setViewVisibility(row, View.GONE)
          continue
        }
        v.setViewVisibility(row, View.VISIBLE)
        v.setTextViewText(row, (if (s.third) "☑ " else "☐ ") + s.second + if (s.first == current) "  ←" else "")
        if (!s.third) v.setOnClickPendingIntent(row, WidgetActionActivity.action(c, widgetId * 10 + i, "step", taskId, mapOf("step" to s.first)))
      }
    }

    fun focusToday(snap: Snapshot, id: String): Int {
      val arr = snap.root.optJSONArray("tasks") ?: return 0
      for (i in 0 until arr.length()) {
        val o = arr.getJSONObject(i)
        if (o.optString("id") == id) return o.optInt("focusToday")
      }
      return 0
    }

    /** "Today 1 h 10 · next: Reply to supplier, Weekly timesheet" */
    private fun footer(snap: Snapshot, current: String?): String {
      var total = 0
      val arr = snap.root.optJSONArray("tasks")
      if (arr != null) for (i in 0 until arr.length()) total += arr.getJSONObject(i).optInt("focusToday")
      val next = snap.tasks.filter { it.id != current && !it.locked }.take(2).joinToString(", ") { it.title }
      return listOfNotNull(if (total > 0) "Today ${minutes(total)}" else null, if (next.isEmpty()) null else "next: $next")
          .joinToString(" · ")
    }

    fun minutes(m: Int): String = if (m < 60) "$m min" else if (m % 60 == 0) "${m / 60} h" else "${m / 60} h ${"%02d".format(m % 60)}"

    /** The ring: what is left of the phase, clockwise from the top. */
    private fun ring(left: Float, colour: Int): Bitmap {
      val size = 240
      val b = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
      val canvas = Canvas(b)
      val p = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 18f
        strokeCap = Paint.Cap.ROUND
      }
      val r = RectF(14f, 14f, size - 14f, size - 14f)
      p.color = 0xFF214545.toInt()
      canvas.drawArc(r, 0f, 360f, false, p)
      p.color = colour
      if (left > 0f) canvas.drawArc(r, -90f, 360f * left, false, p)
      return b
    }

    private fun scheduleRedraw(c: Context, at: Long) {
      val am = c.getSystemService(Context.ALARM_SERVICE) as AlarmManager
      val ids = AppWidgetManager.getInstance(c).getAppWidgetIds(ComponentName(c, FocusTimerWidget::class.java))
      val intent =
          Intent(c, FocusTimerWidget::class.java).apply {
            action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
          }
      var flags = PendingIntent.FLAG_UPDATE_CURRENT
      if (Build.VERSION.SDK_INT >= 23) flags = flags or PendingIntent.FLAG_IMMUTABLE
      val pi = PendingIntent.getBroadcast(c, 7702, intent, flags)
      try {
        if (Build.VERSION.SDK_INT >= 31 && !am.canScheduleExactAlarms()) am.set(AlarmManager.RTC, at, pi)
        else am.setExact(AlarmManager.RTC, at, pi)
      } catch (e: SecurityException) {
        am.set(AlarmManager.RTC, at, pi)
      }
    }
  }
}
