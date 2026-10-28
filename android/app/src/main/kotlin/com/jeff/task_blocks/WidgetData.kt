package com.jeff.task_blocks

import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import org.json.JSONArray
import org.json.JSONObject

/** A task as the widgets see it (written by the Flutter app, see lib/home_widgets.dart). */
data class WidgetTask(
    val id: String,
    val title: String,
    val cat: String?,
    val start: Long,
    val due: Long?,
    val locked: Boolean,
    val star: Boolean,
)

/** Reads the task list the app shares with the widgets, and records ticks made on them. */
object WidgetData {
  // Same store the home_widget plugin writes to.
  private const val PREFS = "HomeWidgetPreferences"
  private const val DAY = 86_400_000L

  private fun prefs(c: Context): SharedPreferences =
      c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

  private fun root(c: Context): JSONObject =
      try {
        JSONObject(prefs(c).getString("widget_data", null) ?: "{}")
      } catch (e: Exception) {
        JSONObject()
      }

  private fun doneArray(c: Context): JSONArray =
      try {
        JSONArray(prefs(c).getString("widget_done", null) ?: "[]")
      } catch (e: Exception) {
        JSONArray()
      }

  /** What a widget shows: "all", "soon" or "cat:<category id>". */
  fun filter(c: Context, widgetId: Int): String =
      prefs(c).getString("filter_$widgetId", "all") ?: "all"

  fun setFilter(c: Context, widgetId: Int, f: String) {
    prefs(c).edit().putString("filter_$widgetId", f).apply()
  }

  fun forget(c: Context, widgetIds: IntArray) {
    val e = prefs(c).edit()
    for (id in widgetIds) e.remove("filter_$id")
    e.apply()
  }

  fun categories(c: Context): List<Pair<String, String>> {
    val a = root(c).optJSONArray("categories") ?: JSONArray()
    return (0 until a.length()).map {
      val o = a.getJSONObject(it)
      o.getString("id") to o.optString("name")
    }
  }

  fun filterLabel(c: Context, f: String): String {
    if (f == "soon") return "Due soon"
    if (f.startsWith("cat:")) {
      val id = f.substring(4)
      return categories(c).firstOrNull { it.first == id }?.second ?: "Tasks"
    }
    return "Tasks"
  }

  fun tasks(c: Context, widgetId: Int): List<WidgetTask> {
    val arr = root(c).optJSONArray("tasks") ?: JSONArray()
    val doneArr = doneArray(c)
    val done = (0 until doneArr.length()).map { doneArr.getJSONObject(it).optString("id") }.toSet()
    val f = filter(c, widgetId)
    val now = System.currentTimeMillis()
    val out = ArrayList<WidgetTask>()
    for (i in 0 until arr.length()) {
      val o = arr.getJSONObject(i)
      val due: Long? = if (o.isNull("due")) null else o.optLong("due")
      val cat: String? = if (o.isNull("cat")) null else o.optString("cat")
      val t =
          WidgetTask(
              o.optString("id"),
              o.optString("title"),
              cat,
              o.optLong("start"),
              due,
              o.optBoolean("locked"),
              o.optBoolean("star"),
          )
      if (done.contains(t.id)) continue
      if (f == "soon" && due != null && due > now + 30 * DAY) continue
      if (f.startsWith("cat:") && cat != f.substring(4)) continue
      out.add(t)
    }
    return out
  }

  /** Same green-to-red colour as the app (lib/widgets/task_colors.dart). */
  fun color(c: Context, t: WidgetTask): Int {
    if (t.locked) return Color.rgb(0xD5, 0xD5, 0xD5)
    val r = root(c)
    val now = System.currentTimeMillis()
    val hoursToRed = r.optDouble("hoursToRed", 72.0)
    val byDue = r.optBoolean("colourByDue", true)
    val due = t.due
    val age = (now - t.start) / 3_600_000.0
    val span = if (byDue && due != null) (due - t.start) / 3_600_000.0 else hoursToRed
    val p = if (span <= 0) 1.0 else (age / span).coerceIn(0.0, 1.0)
    return Color.HSVToColor(floatArrayOf((120 * (1 - p)).toFloat(), 0.6f, 0.88f))
  }

  fun dueLabel(due: Long): String =
      SimpleDateFormat("EEE d MMM", Locale.getDefault()).format(Date(due))

  /** Hides a task ticked on a widget; the app archives it next time it opens. */
  fun markDone(c: Context, id: String) {
    val arr = doneArray(c)
    arr.put(JSONObject().put("id", id).put("at", System.currentTimeMillis()))
    prefs(c).edit().putString("widget_done", arr.toString()).apply()
  }

  fun refreshAll(c: Context) {
    TaskListWidget.updateAll(c)
    CompactWidget.updateAll(c)
  }
}
