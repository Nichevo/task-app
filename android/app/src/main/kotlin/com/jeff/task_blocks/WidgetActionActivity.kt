package com.jeff.task_blocks

import android.app.Activity
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import es.antonborri.home_widget.HomeWidgetLaunchIntent

/**
 * Invisible activity behind taps on widget rows: ticks a task off or snoozes it (without
 * opening the app), ticks a checklist step, or opens something in the app.
 */
class WidgetActionActivity : Activity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    val id = intent.getStringExtra("id")
    when (intent.getStringExtra("op")) {
      "done" -> if (id != null) {
            WidgetData.markDone(this, id)
            WidgetData.refreshAll(this)
          }
      "snooze" -> if (id != null) {
            WidgetData.markSnoozed(this, id)
            WidgetData.refreshAll(this)
          }
      "step" -> {
        val step = intent.getStringExtra("step")
        if (id != null && step != null) {
          WidgetData.markStep(this, id, step)
          WidgetData.refreshAll(this)
        }
      }
      "open" -> if (id != null) launch("taskblocks://open?id=" + Uri.encode(id))
      "day" -> launch("taskblocks://day?d=" + Uri.encode(intent.getStringExtra("d") ?: ""))
      "home" -> launch("taskblocks://home")
    }
    finish()
  }

  private fun launch(uri: String) =
      startActivity(
          Intent(this, MainActivity::class.java).apply {
            action = HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION
            data = Uri.parse(uri)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
          })

  companion object {
    private fun flags(): Int {
      var flags = PendingIntent.FLAG_UPDATE_CURRENT
      if (Build.VERSION.SDK_INT >= 31) flags = flags or PendingIntent.FLAG_MUTABLE
      return flags
    }

    /** Template the list rows fill in with "op" and "id". */
    fun template(c: Context): PendingIntent =
        PendingIntent.getActivity(c, 1, Intent(c, WidgetActionActivity::class.java), flags())

    /** A ready-made action for a single button (the Focus widget). */
    fun action(c: Context, widgetId: Int, op: String, id: String): PendingIntent {
      val intent =
          Intent(c, WidgetActionActivity::class.java).apply {
            putExtra("op", op)
            putExtra("id", id)
            data = Uri.parse("taskblocks://action/$widgetId/$op/" + Uri.encode(id))
          }
      var f = PendingIntent.FLAG_UPDATE_CURRENT
      if (Build.VERSION.SDK_INT >= 23) f = f or PendingIntent.FLAG_IMMUTABLE
      return PendingIntent.getActivity(c, 100 + widgetId, intent, f)
    }
  }
}
