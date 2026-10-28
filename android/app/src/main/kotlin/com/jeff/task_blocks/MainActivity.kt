package com.jeff.task_blocks

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * The app's one activity. Besides running Flutter it handles the few things that need Android
 * directly: text shared from other apps, the phone's calendars and reading text from a photo.
 */
class MainActivity : FlutterActivity() {
  private var shared: Map<String, String?>? = null
  private var permissionResult: MethodChannel.Result? = null

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    takeShared(intent)
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.jeff.task_blocks/native").setMethodCallHandler {
        call,
        result ->
      when (call.method) {
        "takeShared" -> {
          result.success(shared)
          shared = null
        }
        "calendarPermission" -> {
          if (checkSelfPermission(Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
          } else {
            permissionResult?.success(false)
            permissionResult = result
            requestPermissions(arrayOf(Manifest.permission.READ_CALENDAR), 41)
          }
        }
        "calendars" ->
            result.success(CalendarStore.calendars(this).map { mapOf("id" to it.id, "name" to it.name, "account" to it.account) })
        "events" -> {
          val from = call.argument<Number>("from")!!.toLong()
          val to = call.argument<Number>("to")!!.toLong()
          val cals = (call.argument<List<String>>("calendars") ?: emptyList()).toSet()
          result.success(
              CalendarStore.events(this, from, to, cals).map {
                mapOf(
                    "id" to it.id,
                    "calendarId" to it.calendarId,
                    "title" to it.title,
                    "start" to it.start,
                    "allDay" to it.allDay,
                    "location" to it.location,
                )
              })
        }
        "recognizeText" -> recognizeText(call.argument<String>("path")!!, result)
        else -> result.notImplemented()
      }
    }
  }

  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    takeShared(intent)
  }

  /** Keeps text from a Share or "note to self" intent until Flutter asks for it. */
  private fun takeShared(intent: Intent?) {
    if (intent == null) return
    val isShare = intent.action == Intent.ACTION_SEND && intent.type?.startsWith("text/") == true
    val isNote = intent.action == "com.google.android.gms.actions.CREATE_NOTE"
    if (!isShare && !isNote) return
    val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: return
    shared = mapOf("text" to text, "subject" to intent.getStringExtra(Intent.EXTRA_SUBJECT))
    // Don't hand the same text over again if the activity is recreated.
    intent.action = Intent.ACTION_MAIN
    intent.removeExtra(Intent.EXTRA_TEXT)
  }

  override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
    super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    if (requestCode == 41) {
      permissionResult?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
      permissionResult = null
    }
  }

  /** Reads the lines of text in a photo on the phone with ML Kit (no upload). */
  private fun recognizeText(path: String, result: MethodChannel.Result) {
    try {
      val image = InputImage.fromFilePath(this, Uri.fromFile(File(path)))
      TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
          .process(image)
          .addOnSuccessListener { text ->
            val lines = ArrayList<String>()
            for (block in text.textBlocks) for (line in block.lines) lines.add(line.text)
            result.success(lines)
          }
          .addOnFailureListener { e -> result.error("ocr", e.message, null) }
    } catch (e: Exception) {
      result.error("ocr", e.message, null)
    }
  }
}
