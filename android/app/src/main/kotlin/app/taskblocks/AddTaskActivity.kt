package app.taskblocks

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import org.json.JSONArray
import org.json.JSONObject

/**
 * Item 48B: lets other Android apps (Tasker, Automate, MacroDroid…) add a task without opening
 * Task Blocks. The task waits in the widgets' store and the app adds it the next time it opens
 * or comes back to the front, the same way as a file in the Dropbox inbox folder.
 *
 * Send either an intent with action `app.taskblocks.ADD_TASK` and extras, or open
 * `taskblocks://push?title=…` with the same names as query parameters:
 * title (or android.intent.extra.TEXT), notes, due, category, starred, steps, source, ref, url;
 * or one extra `json` holding a task, or a list of tasks, in the inbox file format.
 * `quiet=true` skips the "Added" message; `open=true` opens the app afterwards.
 * Format details: docs/PUSH_TASKS.md.
 */
class AddTaskActivity : Activity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    val (tasks, error) = read(intent)
    val quiet = flag("quiet")
    if (tasks.isEmpty()) {
      if (!quiet) Toast.makeText(this, "Task Blocks: ${error ?: "no task title"}, nothing added", Toast.LENGTH_LONG).show()
    } else {
      val prefs = WidgetData.prefs(this)
      val queue =
          try {
            JSONArray(prefs.getString(KEY, null) ?: "[]")
          } catch (e: Exception) {
            JSONArray()
          }
      for (t in tasks) queue.put(t)
      prefs.edit().putString(KEY, queue.toString()).apply()
      if (!quiet) {
        val what = if (tasks.size == 1) tasks[0].optString("title") else "${tasks.size} tasks"
        Toast.makeText(this, "Added to Task Blocks: $what", Toast.LENGTH_SHORT).show()
      }
      if (flag("open")) {
        startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
      }
    }
    finish()
  }

  private fun value(name: String): String? {
    val uri = intent.data
    val fromUri = if (uri != null && uri.isHierarchical) uri.getQueryParameter(name) else null
    @Suppress("DEPRECATION") val extra = intent.extras?.get(name)
    return fromUri ?: extra?.toString()
  }

  private fun flag(name: String): Boolean = value(name)?.lowercase() in setOf("true", "1", "yes")

  /** The tasks sent, or why there are none. */
  private fun read(intent: Intent?): Pair<List<JSONObject>, String?> {
    if (intent == null) return emptyList<JSONObject>() to null
    val json = value("json")
    if (json != null) {
      return try {
        val text = json.trim()
        val list =
            if (text.startsWith("[")) {
              val a = JSONArray(text)
              (0 until a.length()).map { a.getJSONObject(it) }
            } else {
              listOf(JSONObject(text))
            }
        list.filter { it.optString("title").isNotBlank() } to "no task title"
      } catch (e: Exception) {
        emptyList<JSONObject>() to "the json extra isn't a task"
      }
    }
    val title = value("title") ?: intent.getStringExtra(Intent.EXTRA_TEXT)
    if (title.isNullOrBlank()) return emptyList<JSONObject>() to null
    val o = JSONObject().put("title", title.trim())
    for (k in listOf("notes", "due", "category", "source", "ref", "url")) {
      value(k)?.takeIf { it.isNotBlank() }?.let { o.put(k, it.trim()) }
    }
    if (flag("starred")) o.put("starred", true)
    // Steps: a list extra, or one string with a line (or ";") per step.
    val stepList = intent.getStringArrayListExtra("steps") ?: intent.getStringArrayExtra("steps")?.toList()
    val steps = stepList ?: value("steps")?.split('\n', ';')
    val clean = steps?.map { it.trim() }?.filter { it.isNotEmpty() } ?: emptyList()
    if (clean.isNotEmpty()) o.put("steps", JSONArray(clean))
    if (!o.has("source")) o.put("source", "intent")
    return listOf(o) to null
  }

  companion object {
    /** Read and cleared by lib/home_widgets.dart (takePushed). */
    const val KEY = "pushed_tasks"
  }
}
