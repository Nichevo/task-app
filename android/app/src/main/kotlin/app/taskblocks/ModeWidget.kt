package app.taskblocks

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.text.SpannableString
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/**
 * Item 102: the focus mode in force, as a coloured chip; tapping it opens the app's mode picker.
 * Item 108: made two rows tall or more, it has a button for each mode (Everything first) that
 * switches straight away, until the schedule next changes, without opening the app.
 */
class ModeWidget : AppWidgetProvider() {
  override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
    val snap = WidgetData.snapshot(context)
    for (id in ids) update(context, manager, id, snap.forWidget(context, id))
    // The app's update reaches the quick settings tile through here too.
    ModeTileService.refresh(context)
  }

  override fun onDeleted(context: Context, ids: IntArray) = WidgetData.forget(context, ids)

  /** Redrawn every 15 minutes, so a scheduled change shows without opening the app. */
  override fun onEnabled(context: Context) = WidgetRefreshJob.schedule(context)

  override fun onDisabled(context: Context) = WidgetRefreshJob.cancelIfNoWidgets(context)

  override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, newOptions: android.os.Bundle) =
      onUpdate(context, manager, intArrayOf(id))

  companion object {
    fun update(c: Context, m: AppWidgetManager, id: Int, snap: Snapshot) {
      val v = RemoteViews(c.packageName, R.layout.widget_mode)
      val mode = snap.currentMode
      v.setTextViewText(R.id.mode_name, mode?.name ?: "Everything")
      v.setInt(R.id.mode_dot, "setColorFilter", mode?.colour ?: 0xFF006A6A.toInt())
      val until = mode?.until?.let { untilText(it) }
      val hidden = snap.hiddenByMode
      val sub =
          listOfNotNull(until, if (hidden > 0) "$hidden resting" else null).joinToString(" · ").ifEmpty { "Tap to change" }
      v.setTextViewText(R.id.mode_sub, sub)
      v.setViewVisibility(R.id.mode_sub, View.VISIBLE)
      v.setOnClickPendingIntent(
          R.id.mode_top, HomeWidgetLaunchIntent.getActivity(c, MainActivity::class.java, Uri.parse("taskblocks://mode")))
      // Item 108: the mode buttons, when there is room for them.
      val height = m.getAppWidgetOptions(id).getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 40)
      val modes = WidgetMode.list(snap.root)
      val chips = intArrayOf(R.id.mode_c1, R.id.mode_c2, R.id.mode_c3, R.id.mode_c4, R.id.mode_c5)
      val show = height >= 90 && modes.size > 1
      v.setViewVisibility(R.id.mode_chips, if (show) View.VISIBLE else View.GONE)
      if (show) {
        // Five fit; with more, the last button opens the picker.
        val shown = if (modes.size > chips.size) modes.take(chips.size - 1) else modes
        val current = mode?.id ?: "all"
        for ((i, chip) in chips.withIndex()) {
          val md = shown.getOrNull(i)
          if (md == null) {
            if (i == shown.size && modes.size > chips.size) {
              v.setViewVisibility(chip, View.VISIBLE)
              v.setTextViewText(chip, "More…")
              v.setInt(chip, "setBackgroundResource", R.drawable.widget_button_outline)
              v.setTextColor(chip, 0xDD000000.toInt())
              v.setOnClickPendingIntent(
                  chip, HomeWidgetLaunchIntent.getActivity(c, MainActivity::class.java, Uri.parse("taskblocks://mode")))
            } else {
              v.setViewVisibility(chip, View.GONE)
            }
            continue
          }
          val (mid, name, colour) = md
          val on = mid == current
          v.setViewVisibility(chip, View.VISIBLE)
          val label = SpannableString("● $name")
          if (!on) label.setSpan(ForegroundColorSpan(colour), 0, 1, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
          v.setTextViewText(chip, label)
          v.setInt(chip, "setBackgroundResource", if (on) R.drawable.widget_button_bg else R.drawable.widget_button_outline)
          v.setTextColor(chip, if (on) 0xFFFFFFFF.toInt() else 0xDD000000.toInt())
          v.setOnClickPendingIntent(chip, FocusOps.modeIntent(c, id, i, mid))
        }
      }
      m.updateAppWidget(id, v)
    }

    /** "to 17:00" today, "till Mon" later. */
    fun untilText(ms: Long): String {
      val now = Calendar.getInstance()
      val at = Calendar.getInstance().apply { timeInMillis = ms }
      val sameDay = now.get(Calendar.YEAR) == at.get(Calendar.YEAR) && now.get(Calendar.DAY_OF_YEAR) == at.get(Calendar.DAY_OF_YEAR)
      return if (sameDay) "to " + SimpleDateFormat("HH:mm", Locale.getDefault()).format(at.time)
      else "till " + SimpleDateFormat("EEE", Locale.getDefault()).format(at.time)
    }
  }
}

/**
 * Item 102: a quick settings tile showing the focus mode in force; tapping it opens the app's
 * mode picker. Lit while a mode other than Everything is on.
 */
class ModeTileService : TileService() {
  override fun onStartListening() {
    super.onStartListening()
    val tile = qsTile ?: return
    val mode = WidgetData.snapshot(this).currentMode
    val on = mode != null && mode.id != "all"
    tile.label = if (on) mode!!.name else "Focus mode"
    if (Build.VERSION.SDK_INT >= 29) {
      tile.subtitle = if (on) mode!!.until?.let { ModeWidget.untilText(it) } ?: "On" else "Everything"
    }
    tile.state = if (on) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
    tile.updateTile()
  }

  @SuppressLint("StartActivityAndCollapseDeprecated")
  override fun onClick() {
    super.onClick()
    val intent =
        Intent(this, MainActivity::class.java).apply {
          action = HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION
          data = Uri.parse("taskblocks://mode")
          addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
    if (Build.VERSION.SDK_INT >= 34) {
      startActivityAndCollapse(PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))
    } else {
      @Suppress("DEPRECATION") startActivityAndCollapse(intent)
    }
  }

  companion object {
    /** Asks the system to redraw the tile (after the app shares a new mode). */
    fun refresh(c: Context) {
      try {
        requestListeningState(c, ComponentName(c, ModeTileService::class.java))
      } catch (e: Exception) {
        // Not added to the quick settings panel.
      }
    }
  }
}
