package app.taskblocks

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import org.json.JSONArray
import org.json.JSONObject

/**
 * Item 108: the Focus timer widget's buttons and the Focus mode widget's mode buttons, worked
 * without opening the app. The widget moves its own copy of the timer on ('focus_local') and
 * notes each press ('widget_focus'); the app does the same presses, in order, when it next opens
 * (AppStore.applyPending) and then forgets the copy. Until then the widget also sets the round's
 * end alarm, the ongoing countdown notification and Do not disturb, as the app would.
 */
object FocusOps {
  const val ACTION_OP = "app.taskblocks.FOCUS_OP"
  const val ACTION_END = "app.taskblocks.FOCUS_END"
  const val ACTION_MODE = "app.taskblocks.MODE_PICK"

  // The app's notification ids (Reminders.focusEndId, focusOngoingId in lib/reminders.dart).
  private const val END_ID = -950000001
  private const val ONGOING_ID = -950000002

  private fun flags(): Int {
    var f = PendingIntent.FLAG_UPDATE_CURRENT
    if (Build.VERSION.SDK_INT >= 23) f = f or PendingIntent.FLAG_IMMUTABLE
    return f
  }

  /** A button that does [op] (start, pause, resume, add, skip, stop) on the timer. */
  fun opIntent(c: Context, widgetId: Int, op: String, taskId: String? = null): PendingIntent {
    val i =
        Intent(c, FocusOpReceiver::class.java).apply {
          action = ACTION_OP
          // Unique per widget and button, so each keeps its own extras.
          data = Uri.parse("taskblocks-op://focus/$widgetId/$op")
          putExtra("op", op)
          if (taskId != null) putExtra("task", taskId)
        }
    return PendingIntent.getBroadcast(c, 7800 + widgetId * 8 + op.hashCode() % 8, i, flags())
  }

  /** A button that switches to focus mode [modeId] ("all" = Everything). */
  fun modeIntent(c: Context, widgetId: Int, slot: Int, modeId: String): PendingIntent {
    val i =
        Intent(c, FocusOpReceiver::class.java).apply {
          action = ACTION_MODE
          data = Uri.parse("taskblocks-op://mode/$widgetId/$slot")
          putExtra("mode", modeId)
        }
    return PendingIntent.getBroadcast(c, 8800 + widgetId * 8 + slot, i, flags())
  }

  /** The timer the widgets show: their own copy after a press the app hasn't seen, else the app's. Null = none. */
  fun timer(c: Context, snap: Snapshot): JSONObject? {
    val local = WidgetData.prefs(c).getString("focus_local", null)
    if (!local.isNullOrEmpty()) {
      try {
        val o = JSONObject(local)
        return if (o.optBoolean("stopped")) null else o
      } catch (e: Exception) {}
    }
    return snap.root.optJSONObject("focusTimer")
  }

  /** [f] moved on to [now], as FocusTimerWidget.stateAt and AppStore.tickFocus do, in the same form. */
  fun settle(f: JSONObject, lengths: IntArray, now: Long): JSONObject {
    val s = FocusTimerWidget.stateAt(f, lengths, now)
    val o = JSONObject(f.toString())
    o.put("phase", s.phase)
    o.put("round", s.round)
    o.put("length", s.lengthMs / 1000)
    if (s.end != null) {
      o.put("end", s.end)
      o.remove("left")
    } else {
      o.remove("end")
      o.put("left", s.leftMs / 1000)
    }
    if (s.ready) o.put("ready", true) else o.remove("ready")
    return o
  }

  /** One button press on the Focus timer widget. */
  fun apply(c: Context, op: String, taskId: String?) {
    val snap = WidgetData.snapshot(c)
    val lengths = snap.focusLengths
    val now = System.currentTimeMillis()
    val cur = timer(c, snap)?.let { settle(it, lengths, now) }
    val next: JSONObject? =
        when (op) {
          "start" -> {
            val t = snap.task(taskId ?: return) ?: return
            JSONObject().apply {
              put("task", t.id)
              put("title", t.title)
              put("steps", JSONArray().apply { for (s in t.steps) put(JSONObject().put("id", s.id).put("title", s.title).put("done", s.done)) })
              put("phase", "focus")
              put("round", 1)
              put("length", lengths[0] * 60L)
              put("end", now + lengths[0] * 60_000L)
              put("today", FocusTimerWidget.focusToday(snap, t.id))
            }
          }
          "pause" -> {
            val f = cur ?: return
            if (f.has("end")) {
              f.put("left", ((f.getLong("end") - now) / 1000).coerceAtLeast(0))
              f.remove("end")
            }
            f
          }
          "resume" -> {
            val f = cur ?: return
            if (!f.has("end")) {
              f.put("end", now + f.optLong("left", f.optLong("length", 1500)) * 1000)
              f.remove("left")
              f.remove("ready")
            }
            f
          }
          "add" -> {
            val f = cur ?: return
            val length = f.optLong("length", 1500)
            if (f.has("end")) f.put("end", f.getLong("end") + 300_000L) else f.put("left", f.optLong("left", length) + 300)
            f.put("length", length + 300)
            f
          }
          "skip" -> {
            val f = cur ?: return
            if (f.optString("phase") == "focus" && f.has("end")) return
            if (f.optString("phase") != "focus") f.put("round", f.optInt("round", 1) + 1)
            f.put("phase", "focus")
            f.put("length", lengths[0] * 60L)
            f.put("end", now + lengths[0] * 60_000L)
            f.remove("left")
            f.remove("ready")
            f
          }
          "stop" -> if (cur == null) return else null
          else -> return
        }
    val press = JSONObject().put("op", op).put("at", now)
    if (op == "start") press.put("task", taskId)
    WidgetData.append(c, "widget_focus", press)
    save(c, next)
    after(c, snap, next)
  }

  private fun save(c: Context, f: JSONObject?) {
    WidgetData.prefs(c).edit().putString("focus_local", (f ?: JSONObject().put("stopped", true)).toString()).apply()
  }

  /** Redraws the timer widgets and sets the end alarm, the countdown notification and Do not disturb. */
  private fun after(c: Context, snap: Snapshot, f: JSONObject?) {
    redraw(c)
    notifications(c, f)
    dnd(c, snap, f)
  }

  fun redraw(c: Context) {
    val m = AppWidgetManager.getInstance(c)
    val ids = m.getAppWidgetIds(ComponentName(c, FocusTimerWidget::class.java))
    if (ids.isEmpty()) return
    val snap = WidgetData.snapshot(c)
    for (id in ids) FocusTimerWidget.update(c, m, id, snap.forWidget(c, id))
  }

  /** The alarm for the end of the round or break, set by the widget (the app's own is cancelled). */
  private fun endAlarm(c: Context, end: Long?): PendingIntent {
    val i =
        Intent(c, FocusOpReceiver::class.java).apply {
          action = ACTION_END
          if (end != null) putExtra("end", end)
        }
    return PendingIntent.getBroadcast(c, 7799, i, flags())
  }

  private fun notifications(c: Context, f: JSONObject?) {
    val am = c.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    val nm = c.getSystemService(NotificationManager::class.java)
    // The app's end-of-round alarm (flutter_local_notifications keeps it under the same id).
    try {
      val app = Intent().setClassName(c, "com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver")
      var noCreate = PendingIntent.FLAG_NO_CREATE
      if (Build.VERSION.SDK_INT >= 23) noCreate = noCreate or PendingIntent.FLAG_IMMUTABLE
      PendingIntent.getBroadcast(c, END_ID, app, noCreate)?.let {
        am.cancel(it)
        it.cancel()
      }
    } catch (e: Exception) {}
    am.cancel(endAlarm(c, null))
    if (f == null) {
      nm.cancel(ONGOING_ID)
      return
    }
    channels(nm)
    ongoing(c, nm, f)
    if (f.has("end")) {
      val end = f.getLong("end")
      val pi = endAlarm(c, end)
      try {
        if (Build.VERSION.SDK_INT >= 31 && !am.canScheduleExactAlarms()) am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, end, pi)
        else am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, end, pi)
      } catch (e: SecurityException) {
        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, end, pi)
      }
    }
  }

  private fun channels(nm: NotificationManager) {
    if (Build.VERSION.SDK_INT < 26) return
    if (nm.getNotificationChannel("focus") == null) {
      nm.createNotificationChannel(
          NotificationChannel("focus", "Focus timer", NotificationManager.IMPORTANCE_LOW).apply {
            description = "The countdown while the focus timer runs"
          })
    }
    if (nm.getNotificationChannel("focusEnd") == null) {
      nm.createNotificationChannel(
          NotificationChannel("focusEnd", "Focus timer: round and break ends", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "When a focus round or break is over"
          })
    }
  }

  @Suppress("DEPRECATION")
  private fun builder(c: Context, channel: String): Notification.Builder =
      if (Build.VERSION.SDK_INT >= 26) Notification.Builder(c, channel) else Notification.Builder(c)

  private fun openTimer(c: Context): PendingIntent =
      HomeWidgetLaunchIntent.getActivity(c, MainActivity::class.java, Uri.parse("taskblocks://focus"))

  /** The countdown in the notification shade, as the app shows it (Reminders.showFocus). */
  private fun ongoing(c: Context, nm: NotificationManager, f: JSONObject) {
    val running = f.has("end")
    val phase = f.optString("phase", "focus")
    val what =
        when (phase) {
          "focus" -> "Round ${f.optInt("round", 1)}"
          "longBreak" -> "Long break"
          else -> "Short break"
        }
    val title = f.optString("title")
    val step = f.optString("step").ifEmpty { null }?.let { id ->
      val arr = f.optJSONArray("steps") ?: return@let null
      (0 until arr.length()).map { arr.getJSONObject(it) }.firstOrNull { it.optString("id") == id }?.optString("title")
    }
    val left = f.optLong("left", f.optLong("length", 1500))
    val b =
        builder(c, "focus")
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(if (running) "$what · $title" else "$what · paused · $title")
            .setContentText(step ?: if (running) "Tap to open the timer" else "%02d:%02d left".format(left / 60, left % 60))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(openTimer(c))
            .setShowWhen(running)
    if (running) {
      b.setWhen(f.getLong("end")).setUsesChronometer(true)
      if (Build.VERSION.SDK_INT >= 24) b.setChronometerCountDown(true)
    }
    try {
      nm.notify(ONGOING_ID, b.build())
    } catch (e: Exception) {}
  }

  /** Do not disturb in focus rounds, when the app is set to (and allowed to) turn it on. */
  private fun dnd(c: Context, snap: Snapshot, f: JSONObject?) {
    if (!snap.root.optBoolean("focusDnd")) return
    val nm = c.getSystemService(NotificationManager::class.java)
    if (Build.VERSION.SDK_INT < 23 || !nm.isNotificationPolicyAccessGranted) return
    val on = f != null && f.has("end") && f.optString("phase", "focus") == "focus"
    try {
      nm.setInterruptionFilter(if (on) NotificationManager.INTERRUPTION_FILTER_PRIORITY else NotificationManager.INTERRUPTION_FILTER_ALL)
    } catch (e: Exception) {}
  }

  /** The widget's alarm went off: the round or break set on the widget is over. */
  fun ended(c: Context, end: Long) {
    val local = WidgetData.prefs(c).getString("focus_local", null)
    // The app has caught up since, and set its own alarm.
    if (local.isNullOrEmpty()) return
    val before =
        try {
          JSONObject(local)
        } catch (e: Exception) {
          return
        }
    if (before.optBoolean("stopped")) return
    val snap = WidgetData.snapshot(c)
    val lengths = snap.focusLengths
    val was = settle(before, lengths, (if (end > 0) end else System.currentTimeMillis()) - 1000)
    val now = settle(before, lengths, System.currentTimeMillis())
    save(c, now)
    val nm = c.getSystemService(NotificationManager::class.java)
    channels(nm)
    val round = was.optInt("round", 1)
    val title = was.optString("title")
    val text =
        if (was.optString("phase", "focus") == "focus") {
          val long = round % lengths[3].coerceAtLeast(1) == 0
          "Time for a break" to "Round $round on \"$title\" is done. ${if (long) lengths[2] else lengths[1]} minutes off."
        } else {
          "Break's over" to "Ready for round ${round + 1} on \"$title\"?"
        }
    try {
      nm.notify(
          END_ID,
          builder(c, "focusEnd")
              .setSmallIcon(R.drawable.ic_notification)
              .setContentTitle(text.first)
              .setContentText(text.second)
              .setAutoCancel(true)
              .setContentIntent(openTimer(c))
              .build())
    } catch (e: Exception) {}
    after(c, snap, now)
  }

  /** A mode picked on the Focus mode widget: shown on the widgets at once, applied by the app when it opens. */
  fun pickMode(c: Context, id: String) {
    val snap = WidgetData.snapshot(c)
    // Until the mode in force would next change by itself (the app works it out exactly).
    WidgetData.pickMode(c, id, stretchEnd(snap.root, System.currentTimeMillis()))
    WidgetData.refreshAll(c)
    ModeTileService.refresh(c)
  }

  /** When the app's mode timeline next changes mode after [now]; null if it doesn't. */
  private fun stretchEnd(root: JSONObject, now: Long): Long? {
    val line = root.optJSONArray("modeLine") ?: return null
    for (i in 0 until line.length()) {
      val s = line.optJSONArray(i) ?: continue
      if (s.optLong(0) > now || now >= s.optLong(1)) continue
      var end = s.optLong(1)
      for (k in i + 1 until line.length()) {
        val n = line.optJSONArray(k) ?: break
        if (n.optString(2) != s.optString(2)) return end
        end = n.optLong(1)
      }
      return null
    }
    return null
  }
}

/** Item 108: the presses on the Focus timer and Focus mode widgets, and the widget's round-end alarm. */
class FocusOpReceiver : BroadcastReceiver() {
  override fun onReceive(c: Context, i: Intent) {
    when (i.action) {
      FocusOps.ACTION_OP -> FocusOps.apply(c, i.getStringExtra("op") ?: return, i.getStringExtra("task"))
      FocusOps.ACTION_END -> FocusOps.ended(c, i.getLongExtra("end", 0))
      FocusOps.ACTION_MODE -> FocusOps.pickMode(c, i.getStringExtra("mode") ?: return)
    }
  }
}
