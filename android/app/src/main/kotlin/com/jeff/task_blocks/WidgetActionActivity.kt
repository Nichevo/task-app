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
 * Invisible activity behind taps on list widget rows: ticks a task off (without opening the
 * app) or opens it in the app.
 */
class WidgetActionActivity : Activity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    val id = intent.getStringExtra("id")
    if (id != null) {
      when (intent.getStringExtra("op")) {
        "done" -> {
          WidgetData.markDone(this, id)
          WidgetData.refreshAll(this)
        }
        "open" ->
            startActivity(
                Intent(this, MainActivity::class.java).apply {
                  action = HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION
                  data = Uri.parse("taskblocks://open?id=" + Uri.encode(id))
                  addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                })
      }
    }
    finish()
  }

  companion object {
    /** Template the list rows fill in with "op" and "id". */
    fun template(c: Context): PendingIntent {
      var flags = PendingIntent.FLAG_UPDATE_CURRENT
      if (Build.VERSION.SDK_INT >= 31) flags = flags or PendingIntent.FLAG_MUTABLE
      return PendingIntent.getActivity(c, 1, Intent(c, WidgetActionActivity::class.java), flags)
    }
  }
}
