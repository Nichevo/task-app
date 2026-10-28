package com.jeff.task_blocks

import android.app.Activity
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.speech.RecognizerIntent
import android.view.View
import android.widget.RemoteViews
import android.widget.Toast
import es.antonborri.home_widget.HomeWidgetLaunchIntent

/** A + that opens the app ready to type a new task, and a microphone to say one instead. */
class QuickAddWidget : AppWidgetProvider() {
  override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
    val snap = WidgetData.snapshot(context)
    for (id in ids) update(context, manager, id, snap)
  }

  override fun onDeleted(context: Context, ids: IntArray) = WidgetData.forget(context, ids)

  companion object {
    fun updateAll(c: Context) {
      val m = AppWidgetManager.getInstance(c)
      val ids = m.getAppWidgetIds(ComponentName(c, QuickAddWidget::class.java))
      if (ids.isEmpty()) return
      val snap = WidgetData.snapshot(c)
      for (id in ids) update(c, m, id, snap)
    }

    fun update(c: Context, m: AppWidgetManager, id: Int, snap: Snapshot) {
      val views = RemoteViews(c.packageName, R.layout.widget_quick_add)
      val filter = WidgetData.filter(c, id)
      val cat = if (filter.startsWith("cat:")) filter.removePrefix("cat:") else null
      val name = snap.categoryName(cat)
      views.setTextViewText(R.id.quick_label, name ?: "")
      views.setViewVisibility(R.id.quick_label, if (name == null) View.GONE else View.VISIBLE)
      val catQuery = if (cat == null) "" else "?cat=" + Uri.encode(cat)
      views.setOnClickPendingIntent(
          R.id.quick_add,
          HomeWidgetLaunchIntent.getActivity(c, MainActivity::class.java, Uri.parse("taskblocks://add$catQuery")),
      )
      val voice = Intent(c, VoiceAddActivity::class.java).putExtra("cat", cat)
      var flags = PendingIntent.FLAG_UPDATE_CURRENT
      if (Build.VERSION.SDK_INT >= 23) flags = flags or PendingIntent.FLAG_IMMUTABLE
      views.setOnClickPendingIntent(R.id.quick_mic, PendingIntent.getActivity(c, id, voice, flags))
      m.updateAppWidget(id, views)
    }
  }
}

/** Listens for a spoken task and opens the app with it typed in. */
class VoiceAddActivity : Activity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    val intent =
        Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
          putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
          putExtra(RecognizerIntent.EXTRA_PROMPT, "Say the task")
        }
    try {
      @Suppress("DEPRECATION") startActivityForResult(intent, 7)
    } catch (e: Exception) {
      Toast.makeText(this, "Voice input isn't available on this phone", Toast.LENGTH_SHORT).show()
      finish()
    }
  }

  @Deprecated("Deprecated in Java")
  override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
    @Suppress("DEPRECATION") super.onActivityResult(requestCode, resultCode, data)
    val text = data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()
    if (resultCode == RESULT_OK && !text.isNullOrBlank()) {
      val cat = intent.getStringExtra("cat")
      val uri = "taskblocks://add?text=" + Uri.encode(text) + if (cat == null) "" else "&cat=" + Uri.encode(cat)
      startActivity(
          Intent(this, MainActivity::class.java).apply {
            action = HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION
            setData(Uri.parse(uri))
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
          })
    }
    finish()
  }
}
