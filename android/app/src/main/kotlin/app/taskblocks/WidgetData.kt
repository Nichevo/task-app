package app.taskblocks

import android.Manifest
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.graphics.Color
import android.provider.CalendarContract
import android.widget.RemoteViews
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import org.json.JSONArray
import org.json.JSONObject

/** A checklist step as the widgets see it; [stage] is set when it is on the board. */
data class WidgetStep(
    val id: String,
    val title: String,
    val done: Boolean,
    val stage: String? = null,
    val since: Long? = null,
)

/** A Kanban stage (item 68). */
data class WidgetStage(val id: String, val name: String, val colour: Int?, val limit: Int?)

/** A task (or, in the Today widget, a calendar event) as the widgets see it. */
data class WidgetTask(
    val id: String,
    val title: String,
    val cat: String?,
    val start: Long,
    val due: Long?,
    val locked: Boolean,
    val star: Boolean,
    val steps: List<WidgetStep> = emptyList(),
    val event: Boolean = false,
    /** Board stage id, when on the board. */
    val stage: String? = null,
    val since: Long? = null,
    /** Matrix box id: do, decide, delegate, delete. */
    val box: String? = null,
    val snoozed: Boolean = false,
    /** Item 75: days (yyyy-MM-dd) ticked as worked on, in the last fortnight. */
    val worked: Set<String> = emptySet(),
)

/** Everything the app last shared with the widgets (see lib/home_widgets.dart), parsed once. */
class Snapshot(
    val root: JSONObject,
    done: Set<String>,
    snoozed: Set<String>,
    steps: Set<String>,
    moves: Map<String, Pair<String, Long>> = emptyMap(),
    /** Item 75: "taskId/yyyy-MM-dd" -> ticked or unticked on the widget, not yet seen by the app. */
    workedTicks: Map<String, Boolean> = emptyMap(),
) {
  val hoursToRed = root.optDouble("hoursToRed", 72.0)
  val byDue = root.optBoolean("colourByDue", true)
  val categories: List<Pair<String, String>>

  /** Open tasks that aren't snoozed: what the list widgets show. */
  val tasks: List<WidgetTask>

  /** Every open task the app sent, snoozed board tasks too. */
  val all: List<WidgetTask>
  val stages: List<WidgetStage>
  val boxes: Map<String, String>

  /** yyyy-MM-dd -> (tasks due, only future repeats). */
  val dueDays: Map<String, Pair<Int, Boolean>>
  val doneThisWeek: Int
  val streak: Int

  init {
    val cats = root.optJSONArray("categories") ?: JSONArray()
    categories =
        (0 until cats.length()).map {
          val o = cats.getJSONObject(it)
          o.getString("id") to o.optString("name")
        }
    val arr = root.optJSONArray("tasks") ?: JSONArray()
    val out = ArrayList<WidgetTask>()
    for (i in 0 until arr.length()) {
      val o = arr.getJSONObject(i)
      val id = o.optString("id")
      if (done.contains(id) || snoozed.contains(id)) continue
      val stepArr = o.optJSONArray("steps") ?: JSONArray()
      val stepList =
          (0 until stepArr.length()).map {
            val s = stepArr.getJSONObject(it)
            val sid = s.optString("id")
            val moved = moves["$id/$sid"]
            WidgetStep(
                sid,
                s.optString("title"),
                s.optBoolean("done") || steps.contains("$id/$sid"),
                moved?.first ?: s.optString("stage").ifEmpty { null },
                moved?.second ?: if (s.has("since")) s.optLong("since") else null,
            )
          }
      val moved = moves[id]
      val wArr = o.optJSONArray("worked") ?: JSONArray()
      val worked = (0 until wArr.length()).map { wArr.getString(it) }.toMutableSet()
      for ((k, on) in workedTicks) {
        if (!k.startsWith("$id/")) continue
        val day = k.removePrefix("$id/")
        if (on) worked.add(day) else worked.remove(day)
      }
      out.add(
          WidgetTask(
              id,
              o.optString("title"),
              if (o.isNull("cat")) null else o.optString("cat"),
              o.optLong("start"),
              if (o.isNull("due")) null else o.optLong("due"),
              o.optBoolean("locked"),
              o.optBoolean("star"),
              stepList,
              stage = moved?.first ?: o.optString("stage").ifEmpty { null },
              since = moved?.second ?: if (o.has("since")) o.optLong("since") else null,
              box = o.optString("box").ifEmpty { null },
              snoozed = o.optBoolean("snoozed"),
              worked = worked,
          ))
    }
    all = out
    tasks = out.filter { !it.snoozed }
    val stageArr = root.optJSONArray("stages") ?: JSONArray()
    stages =
        (0 until stageArr.length()).map {
          val o = stageArr.getJSONObject(it)
          WidgetStage(
              o.optString("id"),
              o.optString("name"),
              if (o.has("colour")) o.optLong("colour").toInt() else null,
              if (o.has("limit")) o.optInt("limit") else null,
          )
        }
    val boxObj = root.optJSONObject("boxes") ?: JSONObject()
    boxes = boxObj.keys().asSequence().associateWith { boxObj.optString(it) }
    val days = root.optJSONObject("dueDays") ?: JSONObject()
    dueDays =
        days.keys().asSequence().associateWith {
          val d = days.getJSONObject(it)
          d.optInt("n") to d.optBoolean("faded")
        }
    val stats = root.optJSONObject("stats") ?: JSONObject()
    doneThisWeek = stats.optInt("week")
    streak = stats.optInt("streak")
  }

  fun categoryName(id: String?): String? = categories.firstOrNull { it.first == id }?.second

  fun task(id: String): WidgetTask? = all.firstOrNull { it.id == id }

  fun stage(id: String?): WidgetStage? = stages.firstOrNull { it.id == id }

  /** The stage after [id], or null at the end. */
  fun nextStage(id: String?): WidgetStage? {
    val i = stages.indexOfFirst { it.id == id }
    return if (i < 0) null else stages.getOrNull(i + 1)
  }

  /** Board tasks in [stageId], for an "all" or "cat:<id>" filter. */
  fun boardTasks(stageId: String, f: String): List<WidgetTask> =
      all.filter { it.stage == stageId && WidgetData.inCategory(it, f) }

  /** Board steps in [stageId], each with its task. */
  fun boardSteps(stageId: String, f: String): List<Pair<WidgetTask, WidgetStep>> =
      all.filter { WidgetData.inCategory(it, f) }.flatMap { t -> t.steps.filter { it.stage == stageId }.map { t to it } }
}

/** How a widget looks: background and row size, chosen when it is placed. */
data class Look(val theme: String, val compact: Boolean) {
  val ink: Int
    get() = if (theme == "light") 0xDD000000.toInt() else 0xEEFFFFFF.toInt()

  val faint: Int
    get() = if (theme == "light") 0x99000000.toInt() else 0xAAFFFFFF.toInt()

  val background: Int
    get() =
        when (theme) {
          "dark" -> R.drawable.widget_bg_dark
          "clear" -> R.drawable.widget_bg_clear
          else -> R.drawable.widget_bg
        }

  /** Applies the background to [root] and the text colours to the given TextViews. */
  fun apply(views: RemoteViews, root: Int, inkIds: IntArray = IntArray(0), faintIds: IntArray = IntArray(0)) {
    views.setInt(root, "setBackgroundResource", background)
    for (id in inkIds) views.setTextColor(id, ink)
    for (id in faintIds) views.setTextColor(id, faint)
  }
}

/** Reads what the app shares with the widgets, and records what was done on them. */
object WidgetData {
  // Same store the home_widget plugin writes to.
  private const val PREFS = "HomeWidgetPreferences"
  const val DAY = 86_400_000L

  fun prefs(c: Context): SharedPreferences = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

  private fun array(c: Context, key: String): JSONArray =
      try {
        JSONArray(prefs(c).getString(key, null) ?: "[]")
      } catch (e: Exception) {
        JSONArray()
      }

  private fun ids(c: Context, key: String, field: String): Set<String> {
    val a = array(c, key)
    return (0 until a.length()).map { a.getJSONObject(it).optString(field) }.toSet()
  }

  fun snapshot(c: Context): Snapshot {
    val root =
        try {
          JSONObject(prefs(c).getString("widget_data", null) ?: "{}")
        } catch (e: Exception) {
          JSONObject()
        }
    val stepsArr = array(c, "widget_steps")
    val steps =
        (0 until stepsArr.length())
            .map {
              val o = stepsArr.getJSONObject(it)
              o.optString("task") + "/" + o.optString("step")
            }
            .toSet()
    val movesArr = array(c, "widget_moves")
    val moves = HashMap<String, Pair<String, Long>>()
    for (i in 0 until movesArr.length()) {
      val o = movesArr.getJSONObject(i)
      val key = if (o.has("step")) o.optString("task") + "/" + o.optString("step") else o.optString("task")
      moves[key] = o.optString("stage") to o.optLong("at")
    }
    val workedArr = array(c, "widget_worked")
    val worked = LinkedHashMap<String, Boolean>()
    for (i in 0 until workedArr.length()) {
      val o = workedArr.getJSONObject(i)
      worked[o.optString("id") + "/" + o.optString("day")] = o.optBoolean("on", true)
    }
    return Snapshot(root, ids(c, "widget_done", "id"), ids(c, "widget_snoozed", "id"), steps, moves, worked)
  }

  /** For the board and matrix widgets, whose filter is "all" or "cat:<id>". */
  fun inCategory(t: WidgetTask, f: String): Boolean = !f.startsWith("cat:") || t.cat == f.removePrefix("cat:")

  // --- Per-widget choices ---

  /** What a widget shows: all, soon, star, overdue, today, cat:<id>, cat:<id>+soon, task:<id>. */
  fun filter(c: Context, widgetId: Int): String = prefs(c).getString("filter_$widgetId", "all") ?: "all"

  fun setFilter(c: Context, widgetId: Int, f: String) {
    prefs(c).edit().putString("filter_$widgetId", f).apply()
  }

  fun look(c: Context, widgetId: Int): Look =
      Look(
          prefs(c).getString("look_$widgetId", "light") ?: "light",
          prefs(c).getBoolean("compact_$widgetId", false),
      )

  fun setLook(c: Context, widgetId: Int, theme: String, compact: Boolean) {
    prefs(c).edit().putString("look_$widgetId", theme).putBoolean("compact_$widgetId", compact).apply()
  }

  fun forget(c: Context, widgetIds: IntArray) {
    val e = prefs(c).edit()
    for (id in widgetIds) e.remove("filter_$id").remove("look_$id").remove("compact_$id").remove("stage_$id")
    e.apply()
  }

  /** The stage a stage list widget shows (its arrows and tiles change it). */
  fun shownStage(c: Context, widgetId: Int): String? = prefs(c).getString("stage_$widgetId", null)

  fun setShownStage(c: Context, widgetId: Int, stageId: String) {
    prefs(c).edit().putString("stage_$widgetId", stageId).apply()
  }

  fun filterLabel(c: Context, snap: Snapshot, f: String): String =
      when {
        f == "soon" -> "Due soon"
        f == "star" -> "Starred"
        f == "overdue" -> "Overdue"
        f == "today" -> "Today"
        f.startsWith("cat:") -> {
          val id = f.removePrefix("cat:").removeSuffix("+soon")
          val name = snap.categoryName(id) ?: "Tasks"
          if (f.endsWith("+soon")) "$name · due soon" else name
        }
        f.startsWith("task:") -> snap.task(f.removePrefix("task:"))?.title ?: "Checklist"
        else -> "Tasks"
      }

  /** The tasks a list, summary, today or focus widget shows. */
  fun tasks(c: Context, snap: Snapshot, f: String): List<WidgetTask> {
    val now = System.currentTimeMillis()
    val endOfToday = startOfDay(now) + DAY
    val out = ArrayList<WidgetTask>()
    for (t in snap.tasks) {
      val due = t.due
      val keep =
          when {
            f == "soon" -> due == null || due <= now + 30 * DAY
            f == "star" -> t.star
            f == "overdue" -> due != null && due < now
            f == "today" -> due != null && due < endOfToday
            f.startsWith("cat:") -> {
              val id = f.removePrefix("cat:").removeSuffix("+soon")
              t.cat == id && (!f.endsWith("+soon") || due == null || due <= now + 30 * DAY)
            }
            else -> true
          }
      if (keep) out.add(t)
    }
    if (f == "today") {
      out.sortBy { it.due }
      out.addAll(todayEvents(c))
    }
    return out
  }

  fun startOfDay(ms: Long): Long {
    val cal = Calendar.getInstance()
    cal.timeInMillis = ms
    cal.set(Calendar.HOUR_OF_DAY, 0)
    cal.set(Calendar.MINUTE, 0)
    cal.set(Calendar.SECOND, 0)
    cal.set(Calendar.MILLISECOND, 0)
    return cal.timeInMillis
  }

  /** Today's calendar events, when the app has been allowed to read the calendar. */
  fun todayEvents(c: Context): List<WidgetTask> {
    if (c.checkSelfPermission(Manifest.permission.READ_CALENDAR) != PackageManager.PERMISSION_GRANTED) {
      return emptyList()
    }
    val from = startOfDay(System.currentTimeMillis())
    return try {
      CalendarStore.events(c, from, from + DAY, emptySet()).map {
        WidgetTask("ev:" + it.id, it.title, null, from, it.start, locked = true, star = false, event = true)
      }
    } catch (e: Exception) {
      emptyList()
    }
  }

  /** Same green-to-red colour as the app (lib/widgets/task_colors.dart). */
  fun color(snap: Snapshot, t: WidgetTask): Int {
    if (t.locked) return Color.rgb(0xD5, 0xD5, 0xD5)
    val now = System.currentTimeMillis()
    val due = t.due
    val age = (now - t.start) / 3_600_000.0
    val span = if (snap.byDue && due != null) (due - t.start) / 3_600_000.0 else snap.hoursToRed
    val p = if (span <= 0) 1.0 else (age / span).coerceIn(0.0, 1.0)
    return Color.HSVToColor(floatArrayOf((120 * (1 - p)).toFloat(), 0.6f, 0.88f))
  }

  fun dueLabel(due: Long): String {
    val today = startOfDay(System.currentTimeMillis())
    return when {
      due in today until today + DAY -> SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(due))
      due in today + DAY until today + 2 * DAY -> "Tomorrow"
      else -> SimpleDateFormat("EEE d MMM", Locale.getDefault()).format(Date(due))
    }
  }

  // --- Things done on a widget, for the app to apply ---

  private fun append(c: Context, key: String, o: JSONObject) {
    val arr = array(c, key)
    arr.put(o)
    prefs(c).edit().putString(key, arr.toString()).apply()
  }

  /** Hides a task ticked on a widget; the app archives it next time it opens. */
  fun markDone(c: Context, id: String) =
      append(c, "widget_done", JSONObject().put("id", id).put("at", System.currentTimeMillis()))

  /** Hides a task snoozed on a widget until tomorrow 8am; the app snoozes it next time it opens. */
  fun markSnoozed(c: Context, id: String) {
    val cal = Calendar.getInstance()
    cal.timeInMillis = startOfDay(System.currentTimeMillis()) + DAY
    cal.set(Calendar.HOUR_OF_DAY, 8)
    append(c, "widget_snoozed", JSONObject().put("id", id).put("until", cal.timeInMillis))
  }

  /** Moves a board task, or one of its board steps, to [stageId] (item 68). */
  fun markMove(c: Context, taskId: String, stepId: String?, stageId: String) {
    val o = JSONObject().put("task", taskId).put("stage", stageId).put("at", System.currentTimeMillis())
    if (stepId != null) o.put("step", stepId)
    append(c, "widget_moves", o)
  }

  /** How long something has been in its stage: "5 h", "3 days". */
  fun spell(since: Long?): String {
    if (since == null) return ""
    val h = (System.currentTimeMillis() - since) / 3_600_000L
    return when {
      h < 1 -> "under an hour"
      h < 24 -> "$h h"
      h < 48 -> "1 day"
      else -> "${h / 24} days"
    }
  }

  /** Item 75: ticks (or unticks) [day] as a day [taskId] was worked on. */
  fun markWorked(c: Context, taskId: String, day: String, on: Boolean) =
      append(c, "widget_worked", JSONObject().put("id", taskId).put("day", day).put("on", on))

  /** Today as yyyy-MM-dd, the way the app writes days. */
  fun todayKey(): String = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())

  /** Ticks a checklist step on a widget. */
  fun markStep(c: Context, taskId: String, stepId: String) =
      append(c, "widget_steps", JSONObject().put("task", taskId).put("step", stepId))

  // --- Refreshing ---

  val providers =
      listOf(
          TaskListWidget::class.java,
          CompactWidget::class.java,
          TodayWidget::class.java,
          FocusWidget::class.java,
          ChecklistWidget::class.java,
          StatsWidget::class.java,
          MonthWidget::class.java,
          QuickAddWidget::class.java,
          BoardSummaryWidget::class.java,
          StageListWidget::class.java,
          NowDoingWidget::class.java,
          BoardStepsWidget::class.java,
          MatrixWidget::class.java,
          WorkedTodayWidget::class.java,
          AddedDoneWidget::class.java,
          BurnDownWidget::class.java,
      )

  fun refreshAll(c: Context) {
    val m = AppWidgetManager.getInstance(c)
    for (p in providers) {
      val ids = m.getAppWidgetIds(ComponentName(c, p))
      if (ids.isEmpty()) continue
      val intent = android.content.Intent(c, p)
      intent.action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
      intent.putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
      c.sendBroadcast(intent)
    }
  }

  /** Whether any of our widgets is on a home screen. */
  fun anyWidgets(c: Context): Boolean {
    val m = AppWidgetManager.getInstance(c)
    return providers.any { m.getAppWidgetIds(ComponentName(c, it)).isNotEmpty() }
  }
}
