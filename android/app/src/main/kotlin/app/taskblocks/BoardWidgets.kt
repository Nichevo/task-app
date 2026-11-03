package app.taskblocks

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.text.SpannableString
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import es.antonborri.home_widget.HomeWidgetLaunchIntent

/*
 * Item 68: the Kanban board and matrix widgets. Moves made here are queued like ticks
 * (WidgetData.markMove) and recorded by the app as board moves made "Widget".
 */

/** What every widget provider does the same way. */
abstract class BaseWidget : AppWidgetProvider() {
  abstract fun draw(c: Context, m: AppWidgetManager, id: Int, snap: Snapshot)

  /** The collection inside the widget, if it has one, so its rows are reloaded too. */
  open val listId: Int? = null

  override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
    val snap = WidgetData.snapshot(context)
    for (id in ids) draw(context, manager, id, snap)
    listId?.let { manager.notifyAppWidgetViewDataChanged(ids, it) }
  }

  override fun onEnabled(context: Context) = WidgetRefreshJob.schedule(context)

  override fun onDisabled(context: Context) = WidgetRefreshJob.cancelIfNoWidgets(context)

  override fun onDeleted(context: Context, ids: IntArray) = WidgetData.forget(context, ids)

  /** Redraws straight away when the launcher resizes the widget (e.g. folding the phone). */
  override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, newOptions: android.os.Bundle) =
      onUpdate(context, manager, intArrayOf(id))
}

/** Shared drawing helpers for the board widgets. */
object BoardLook {
  private val tiles = intArrayOf(0xFFE3EEF9.toInt(), 0xFFE6F4E7.toInt(), 0xFFFFE8A8.toInt(), 0xFFFDE3DC.toInt(), 0xFFEEEEF2.toInt())
  val AMBER = 0xFFE65100.toInt()
  val BLUE = 0xFF1A5FB4.toInt()

  /** A light tile colour for a stage: its own colour washed out, else one from a set. */
  fun tile(stage: WidgetStage, index: Int): Int {
    val c = stage.colour ?: return tiles[index % tiles.size]
    fun mix(v: Int) = v + ((255 - v) * 0.75).toInt()
    return Color.rgb(mix(Color.red(c)), mix(Color.green(c)), mix(Color.blue(c)))
  }

  /** Colours a rounded background (Android 12+), or fills it square on older phones. */
  fun tint(views: RemoteViews, id: Int, colour: Int) {
    if (Build.VERSION.SDK_INT >= 31) {
      views.setColorStateList(id, "setBackgroundTintList", ColorStateList.valueOf(colour))
    } else {
      views.setInt(id, "setBackgroundColor", colour)
    }
  }

  fun over(snap: Snapshot, s: WidgetStage, f: String): Boolean {
    val limit = s.limit ?: return false
    return snap.boardTasks(s.id, f).size > limit
  }

  /** The row of stage tiles with counts. [onTap] gives each tile's action. */
  fun tilesRow(
      c: Context,
      views: RemoteViews,
      snap: Snapshot,
      f: String,
      selected: String?,
      onTap: (WidgetStage) -> android.app.PendingIntent,
  ) {
    views.removeAllViews(R.id.b_tiles)
    for ((i, s) in snap.stages.withIndex()) {
      val tile = RemoteViews(c.packageName, R.layout.widget_stage_tile)
      tint(tile, R.id.tile, tile(s, i))
      val n = snap.boardTasks(s.id, f).size
      val steps = snap.boardSteps(s.id, f).size
      tile.setTextViewText(R.id.tile_count, if (steps > 0) "$n·$steps" else "$n")
      tile.setTextViewText(R.id.tile_name, if (s.id == selected) "• ${s.name}" else s.name)
      val ink = if (over(snap, s, f)) AMBER else if (s.id == selected) BLUE else 0xFF1C1C1E.toInt()
      tile.setTextColor(R.id.tile_count, ink)
      tile.setTextColor(R.id.tile_name, if (ink == 0xFF1C1C1E.toInt()) 0xFF3A3A40.toInt() else ink)
      tile.setOnClickPendingIntent(R.id.tile, onTap(s))
      views.addView(R.id.b_tiles, tile)
    }
  }

  /** "overdue 2 days", "due Fri", or nothing. */
  fun dueText(due: Long?): String {
    if (due == null) return ""
    val now = System.currentTimeMillis()
    if (due < now) {
      val days = (WidgetData.startOfDay(now) - WidgetData.startOfDay(due)) / WidgetData.DAY
      return when {
        days <= 0 -> "overdue"
        days == 1L -> "overdue 1 day"
        else -> "overdue $days days"
      }
    }
    return "due " + WidgetData.dueLabel(due)
  }

  fun join(vararg parts: String): String = parts.filter { it.isNotEmpty() }.joinToString(" · ")

  /** A coloured bar before [text], for rows too small for their own bar. */
  fun barred(text: String, colour: Int): CharSequence {
    val s = SpannableString("▌ $text")
    s.setSpan(ForegroundColorSpan(colour), 0, 1, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
    return s
  }

  fun launch(c: Context, uri: String): android.app.PendingIntent =
      HomeWidgetLaunchIntent.getActivity(c, MainActivity::class.java, Uri.parse(uri))

  fun categoryTitle(snap: Snapshot, base: String, f: String): String =
      if (f.startsWith("cat:")) "$base · " + (snap.categoryName(f.removePrefix("cat:")) ?: "category") else base
}

/** Item 68, widget 1: how many tasks are in each stage; a tap opens the board on that stage. */
class BoardSummaryWidget : BaseWidget() {
  override fun draw(c: Context, m: AppWidgetManager, id: Int, snap: Snapshot) {
    val views = RemoteViews(c.packageName, R.layout.widget_board_summary)
    val look = WidgetData.look(c, id)
    val f = WidgetData.filter(c, id)
    look.apply(views, R.id.b_root, intArrayOf(R.id.b_title), intArrayOf(R.id.b_note))
    views.setTextViewText(R.id.b_title, BoardLook.categoryTitle(snap, "Kanban board", f))
    BoardLook.tilesRow(c, views, snap, f, null) { s -> BoardLook.launch(c, "taskblocks://board?stage=" + Uri.encode(s.id)) }
    val over = snap.stages.filter { BoardLook.over(snap, it, f) }
    if (over.isEmpty()) {
      views.setViewVisibility(R.id.b_note, View.GONE)
    } else {
      views.setViewVisibility(R.id.b_note, View.VISIBLE)
      views.setTextViewText(R.id.b_note, over.joinToString("; ") { "${it.name} is over its limit of ${it.limit}" })
    }
    views.setOnClickPendingIntent(R.id.b_title, BoardLook.launch(c, "taskblocks://board"))
    m.updateAppWidget(id, views)
  }
}

/** Item 68, widget 2: the counts, then the cards in one stage, each with an arrow to move it on. */
class StageListWidget : BaseWidget() {
  override val listId: Int = R.id.widget_list

  override fun draw(c: Context, m: AppWidgetManager, id: Int, snap: Snapshot) {
    val views = RemoteViews(c.packageName, R.layout.widget_stage_list)
    val look = WidgetData.look(c, id)
    val f = WidgetData.filter(c, id)
    look.apply(views, R.id.widget_root, intArrayOf(R.id.widget_title, R.id.sl_stage), intArrayOf(R.id.widget_empty))
    views.setTextViewText(R.id.widget_title, BoardLook.categoryTitle(snap, "Kanban board", f))
    views.setOnClickPendingIntent(R.id.widget_title, BoardLook.launch(c, "taskblocks://board"))
    val stages = snap.stages
    if (stages.isEmpty()) {
      views.setTextViewText(R.id.sl_stage, "No stages")
      m.updateAppWidget(id, views)
      return
    }
    val shown = snap.stage(WidgetData.shownStage(c, id)) ?: snap.stage("doing") ?: stages.first()
    val i = stages.indexOf(shown)
    BoardLook.tilesRow(c, views, snap, f, shown.id) { s -> WidgetActionActivity.action(c, id, "showstage", s.id) }
    views.setTextViewText(R.id.sl_stage, "${shown.name} · ${snap.boardTasks(shown.id, f).size}")
    views.setOnClickPendingIntent(R.id.sl_stage, BoardLook.launch(c, "taskblocks://board?stage=" + Uri.encode(shown.id)))
    val prev = stages.getOrNull(i - 1)
    val next = stages.getOrNull(i + 1)
    views.setViewVisibility(R.id.sl_prev, if (prev == null) View.INVISIBLE else View.VISIBLE)
    views.setViewVisibility(R.id.sl_next, if (next == null) View.INVISIBLE else View.VISIBLE)
    if (prev != null) views.setOnClickPendingIntent(R.id.sl_prev, WidgetActionActivity.action(c, id, "showstage", prev.id))
    if (next != null) views.setOnClickPendingIntent(R.id.sl_next, WidgetActionActivity.action(c, id, "showstage", next.id))
    views.setInt(R.id.sl_prev, "setColorFilter", look.ink)
    views.setInt(R.id.sl_next, "setColorFilter", look.ink)
    val service =
        Intent(c, StageListService::class.java).apply {
          putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
          putExtra("stage", shown.id)
          putExtra("filter", f)
          data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
        }
    @Suppress("DEPRECATION") views.setRemoteAdapter(R.id.widget_list, service)
    views.setEmptyView(R.id.widget_list, R.id.widget_empty)
    views.setPendingIntentTemplate(R.id.widget_list, WidgetActionActivity.template(c))
    m.updateAppWidget(id, views)
  }
}

/** Cards of [StageListWidget]. */
class StageListService : RemoteViewsService() {
  override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
      Factory(applicationContext, intent.getStringExtra("stage") ?: "", intent.getStringExtra("filter") ?: "all")

  class Factory(private val c: Context, private val stageId: String, private val filter: String) : RemoteViewsFactory {
    private var snap: Snapshot? = null
    private var items: List<WidgetTask> = emptyList()

    override fun onCreate() {}

    override fun onDataSetChanged() {
      val s = WidgetData.snapshot(c)
      snap = s
      items = s.boardTasks(stageId, filter).sortedBy { it.due ?: Long.MAX_VALUE }
    }

    override fun onDestroy() {}

    override fun getCount(): Int = items.size

    override fun getViewAt(position: Int): RemoteViews {
      val v = RemoteViews(c.packageName, R.layout.widget_card_row)
      val t = items.getOrNull(position) ?: return v
      val s = snap ?: return v
      v.setInt(R.id.row_bar, "setBackgroundColor", WidgetData.color(s, t))
      v.setTextViewText(R.id.row_title, (if (t.star) "★ " else "") + t.title)
      val steps = if (t.steps.isEmpty()) "" else "${t.steps.count { it.done }}/${t.steps.size} steps"
      val here = WidgetData.spell(t.since)
      v.setTextViewText(
          R.id.row_meta,
          BoardLook.join(BoardLook.dueText(t.due), steps, if (here.isEmpty()) "" else "$here here", if (t.snoozed) "snoozed" else ""))
      val next = s.nextStage(stageId)
      if (next == null) {
        v.setViewVisibility(R.id.row_move, View.GONE)
      } else {
        v.setViewVisibility(R.id.row_move, View.VISIBLE)
        v.setContentDescription(R.id.row_move, "Move to ${next.name}")
        v.setOnClickFillInIntent(R.id.row_move, Intent().putExtra("op", "move").putExtra("id", t.id).putExtra("stage", next.id))
      }
      v.setOnClickFillInIntent(R.id.row_text, Intent().putExtra("op", "open").putExtra("id", t.id))
      return v
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = false
  }
}

/**
 * Item 68, widget 3: one board task, the one longest in a chosen stage (In progress unless set
 * otherwise) or one picked when placing the widget. Tick its steps, move it on or finish it.
 */
class NowDoingWidget : BaseWidget() {
  companion object {
    private val stepRows = intArrayOf(R.id.n_step1, R.id.n_step2, R.id.n_step3)
    private val stepTicks = intArrayOf(R.id.n_tick1, R.id.n_tick2, R.id.n_tick3)
    private val stepTexts = intArrayOf(R.id.n_stext1, R.id.n_stext2, R.id.n_stext3)

    /** The stage the widget watches for "stage:<id>" or no choice yet. */
    fun watchedStage(snap: Snapshot, f: String): WidgetStage? =
        snap.stage(f.removePrefix("stage:")) ?: snap.stage("doing") ?: snap.stages.getOrNull(snap.stages.size / 2)

    fun pick(snap: Snapshot, f: String): WidgetTask? {
      if (f.startsWith("task:")) return snap.task(f.removePrefix("task:"))
      val stage = watchedStage(snap, f) ?: return null
      return snap.boardTasks(stage.id, "all").minByOrNull { it.since ?: Long.MAX_VALUE }
    }
  }

  override fun draw(c: Context, m: AppWidgetManager, id: Int, snap: Snapshot) {
    val views = RemoteViews(c.packageName, R.layout.widget_now)
    val look = WidgetData.look(c, id)
    val f = WidgetData.filter(c, id)
    look.apply(views, R.id.n_root, intArrayOf(R.id.n_head, R.id.n_title) + stepTexts, intArrayOf(R.id.n_since, R.id.n_meta, R.id.n_more))
    views.setTextViewText(R.id.n_head, "Now doing")
    val t = pick(snap, f)
    if (t == null) {
      val stage = watchedStage(snap, f)
      views.setTextViewText(R.id.n_since, "")
      views.setTextViewText(R.id.n_title, if (stage == null) "Nothing on the board" else "Nothing in ${stage.name}")
      views.setTextViewText(R.id.n_meta, "Tap to open the board")
      views.setInt(R.id.n_bar, "setBackgroundColor", Color.TRANSPARENT)
      for (r in stepRows) views.setViewVisibility(r, View.GONE)
      views.setViewVisibility(R.id.n_more, View.GONE)
      views.setViewVisibility(R.id.n_buttons, View.GONE)
      views.setOnClickPendingIntent(R.id.n_root, BoardLook.launch(c, "taskblocks://board"))
      m.updateAppWidget(id, views)
      return
    }
    val stage = snap.stage(t.stage)
    views.setTextViewText(
        R.id.n_since,
        if (stage == null) "" else stage.name + if (t.since == null) "" else " for " + WidgetData.spell(t.since))
    views.setTextViewText(R.id.n_title, (if (t.star) "★ " else "") + t.title)
    views.setTextViewText(R.id.n_meta, BoardLook.join(snap.categoryName(t.cat) ?: "", BoardLook.dueText(t.due)))
    views.setInt(R.id.n_bar, "setBackgroundColor", WidgetData.color(snap, t))
    views.setOnClickPendingIntent(R.id.n_text, WidgetActionActivity.action(c, id, "open", t.id))
    val open = t.steps.filter { !it.done }
    for ((i, row) in stepRows.withIndex()) {
      val s = open.getOrNull(i)
      if (s == null) {
        views.setViewVisibility(row, View.GONE)
        continue
      }
      views.setViewVisibility(row, View.VISIBLE)
      views.setTextViewText(stepTexts[i], s.title)
      views.setImageViewResource(stepTicks[i], R.drawable.ic_widget_box)
      views.setOnClickPendingIntent(row, WidgetActionActivity.action(c, id, "step", t.id, mapOf("step" to s.id)))
    }
    val more = open.size - stepRows.size
    val doneSteps = t.steps.size - open.size
    when {
      more > 0 -> {
        views.setViewVisibility(R.id.n_more, View.VISIBLE)
        views.setTextViewText(R.id.n_more, "$more more steps")
      }
      t.steps.isNotEmpty() && open.isEmpty() -> {
        views.setViewVisibility(R.id.n_more, View.VISIBLE)
        views.setTextViewText(R.id.n_more, "All $doneSteps steps ticked")
      }
      else -> views.setViewVisibility(R.id.n_more, View.GONE)
    }
    views.setViewVisibility(R.id.n_buttons, View.VISIBLE)
    val next = snap.nextStage(t.stage)
    if (next == null) {
      views.setViewVisibility(R.id.n_next, View.GONE)
    } else {
      views.setViewVisibility(R.id.n_next, View.VISIBLE)
      views.setTextViewText(R.id.n_next, "Next: ${next.name}")
      views.setOnClickPendingIntent(R.id.n_next, WidgetActionActivity.action(c, id, "move", t.id, mapOf("stage" to next.id)))
    }
    if (t.locked) {
      views.setViewVisibility(R.id.n_done, View.GONE)
    } else {
      views.setViewVisibility(R.id.n_done, View.VISIBLE)
      views.setOnClickPendingIntent(R.id.n_done, WidgetActionActivity.action(c, id, "done", t.id))
    }
    m.updateAppWidget(id, views)
  }
}

/** Item 68, widget 4: only the steps that are on the board, grouped by stage (furthest along first). */
class BoardStepsWidget : BaseWidget() {
  override val listId: Int = R.id.widget_list

  override fun draw(c: Context, m: AppWidgetManager, id: Int, snap: Snapshot) {
    val views = RemoteViews(c.packageName, R.layout.widget_board_steps)
    val look = WidgetData.look(c, id)
    val f = WidgetData.filter(c, id)
    look.apply(views, R.id.widget_root, intArrayOf(R.id.widget_title), intArrayOf(R.id.widget_empty))
    val open = BoardStepsService.rows(snap, f).count { it.second != null }
    views.setTextViewText(R.id.widget_title, BoardLook.categoryTitle(snap, "Steps on the board", f) + " · $open open")
    views.setTextViewText(R.id.widget_empty, "No steps on the board. Turn on \"Steps on the board too\" on a board task.")
    views.setOnClickPendingIntent(R.id.widget_title, BoardLook.launch(c, "taskblocks://board"))
    val service =
        Intent(c, BoardStepsService::class.java).apply {
          putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
          putExtra("filter", f)
          putExtra("ink", look.ink)
          data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
        }
    @Suppress("DEPRECATION") views.setRemoteAdapter(R.id.widget_list, service)
    views.setEmptyView(R.id.widget_list, R.id.widget_empty)
    views.setPendingIntentTemplate(R.id.widget_list, WidgetActionActivity.template(c))
    m.updateAppWidget(id, views)
  }
}

/** Rows of [BoardStepsWidget]: a heading per stage, then its steps. */
class BoardStepsService : RemoteViewsService() {
  companion object {
    /** (stage, null) is a heading; (stage, task and step) a step. The last stage (done) is left out. */
    fun rows(snap: Snapshot, f: String): List<Pair<WidgetStage, Pair<WidgetTask, WidgetStep>?>> {
      val out = ArrayList<Pair<WidgetStage, Pair<WidgetTask, WidgetStep>?>>()
      for (s in snap.stages.dropLast(1).reversed()) {
        val steps = snap.boardSteps(s.id, f).filter { !it.second.done }
        if (steps.isEmpty()) continue
        out.add(s to null)
        for (p in steps) out.add(s to p)
      }
      return out
    }
  }

  override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
      Factory(applicationContext, intent.getStringExtra("filter") ?: "all", intent.getIntExtra("ink", 0xDD000000.toInt()))

  class Factory(private val c: Context, private val filter: String, private val ink: Int) : RemoteViewsFactory {
    private var snap: Snapshot? = null
    private var items: List<Pair<WidgetStage, Pair<WidgetTask, WidgetStep>?>> = emptyList()

    override fun onCreate() {}

    override fun onDataSetChanged() {
      val s = WidgetData.snapshot(c)
      snap = s
      items = rows(s, filter)
    }

    override fun onDestroy() {}

    override fun getCount(): Int = items.size

    override fun getViewAt(position: Int): RemoteViews {
      val (stage, item) = items.getOrNull(position) ?: return RemoteViews(c.packageName, R.layout.widget_step_header)
      val s = snap
      if (item == null || s == null) {
        val h = RemoteViews(c.packageName, R.layout.widget_step_header)
        h.setTextViewText(R.id.row_header, stage.name)
        h.setTextColor(R.id.row_header, ink)
        return h
      }
      val (t, step) = item
      val v = RemoteViews(c.packageName, R.layout.widget_card_row)
      v.setInt(R.id.row_bar, "setBackgroundColor", WidgetData.color(s, t))
      v.setTextViewText(R.id.row_title, step.title)
      val n = t.steps.indexOfFirst { it.id == step.id } + 1
      val here = WidgetData.spell(step.since)
      v.setTextViewText(R.id.row_meta, BoardLook.join(t.title, "step $n", if (here.isEmpty()) "" else "$here here"))
      val next = s.nextStage(stage.id)
      if (next == null) {
        v.setViewVisibility(R.id.row_move, View.GONE)
      } else {
        v.setViewVisibility(R.id.row_move, View.VISIBLE)
        v.setContentDescription(R.id.row_move, "Move to ${next.name}")
        v.setOnClickFillInIntent(
            R.id.row_move,
            Intent().putExtra("op", "move").putExtra("id", t.id).putExtra("step", step.id).putExtra("stage", next.id))
      }
      v.setOnClickFillInIntent(R.id.row_text, Intent().putExtra("op", "open").putExtra("id", t.id))
      return v
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 2

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = false
  }
}

/** Item 68, widget 5: the four matrix boxes with the top tasks in each. */
class MatrixWidget : BaseWidget() {
  companion object {
    val boxes = listOf("do", "decide", "delegate", "delete")
    private val defaults = mapOf("do" to "Do", "decide" to "Decide", "delegate" to "Delegate", "delete" to "Delete")
    private val colours = intArrayOf(0xFFFDE3DC.toInt(), 0xFFE3EEF9.toInt(), 0xFFE6F4E7.toInt(), 0xFFEEEEF2.toInt())
    private val boxIds = intArrayOf(R.id.m_box0, R.id.m_box1, R.id.m_box2, R.id.m_box3)
    private val nameIds = intArrayOf(R.id.m_name0, R.id.m_name1, R.id.m_name2, R.id.m_name3)
    private val listIds = intArrayOf(R.id.m_list0, R.id.m_list1, R.id.m_list2, R.id.m_list3)

    /** Tasks in [box]: the ones with a date first, soonest first. */
    fun tasksIn(snap: Snapshot, box: String, f: String): List<WidgetTask> =
        snap.tasks.filter { it.box == box && WidgetData.inCategory(it, f) }.sortedBy { it.due ?: Long.MAX_VALUE }
  }

  override fun draw(c: Context, m: AppWidgetManager, id: Int, snap: Snapshot) {
    val views = RemoteViews(c.packageName, R.layout.widget_matrix)
    val look = WidgetData.look(c, id)
    val f = WidgetData.filter(c, id)
    look.apply(views, R.id.m_root, intArrayOf(R.id.m_title), intArrayOf(R.id.m_count))
    views.setTextViewText(R.id.m_title, BoardLook.categoryTitle(snap, "Matrix", f))
    views.setOnClickPendingIntent(R.id.m_title, BoardLook.launch(c, "taskblocks://matrix"))
    // Fewer rows when the widget is short.
    val height = m.getAppWidgetOptions(id).getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 250)
    val rows = when {
      height < 200 -> 1
      height < 280 -> 2
      else -> 3
    }
    var total = 0
    for ((i, box) in boxes.withIndex()) {
      val tasks = tasksIn(snap, box, f)
      total += tasks.size
      BoardLook.tint(views, boxIds[i], colours[i])
      views.setTextViewText(nameIds[i], "${snap.boxes[box] ?: defaults[box]} · ${tasks.size}")
      views.setOnClickPendingIntent(boxIds[i], BoardLook.launch(c, "taskblocks://matrix?box=$box"))
      views.removeAllViews(listIds[i])
      for (t in tasks.take(rows)) {
        val row = RemoteViews(c.packageName, R.layout.widget_matrix_row)
        row.setTextViewText(R.id.m_row, BoardLook.barred((if (t.star) "★ " else "") + t.title, WidgetData.color(snap, t)))
        row.setOnClickPendingIntent(R.id.m_row, WidgetActionActivity.action(c, id, "open", t.id))
        views.addView(listIds[i], row)
      }
      if (tasks.size > rows) {
        val row = RemoteViews(c.packageName, R.layout.widget_matrix_row)
        row.setTextViewText(R.id.m_row, "+${tasks.size - rows} more")
        row.setInt(R.id.m_row, "setBackgroundColor", Color.TRANSPARENT)
        row.setTextColor(R.id.m_row, 0xFF5C5C63.toInt())
        row.setOnClickPendingIntent(R.id.m_row, BoardLook.launch(c, "taskblocks://matrix?box=$box"))
        views.addView(listIds[i], row)
      }
    }
    views.setTextViewText(R.id.m_count, if (total == 1) "1 task" else "$total tasks")
    m.updateAppWidget(id, views)
  }
}
