package app.taskblocks

import android.Manifest
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/**
 * The app's one activity. Besides running Flutter it handles the few things that need Android
 * directly: text shared from other apps, the phone's calendars and reading text from a photo.
 */
class MainActivity : FlutterActivity() {
  private var shared: Map<String, Any?>? = null
  private var permissionResult: MethodChannel.Result? = null

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    takeShared(intent)
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.taskblocks/native").setMethodCallHandler {
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
                    "end" to it.end,
                )
              })
        }
        "recognizeText" -> recognizeText(call.argument<String>("path")!!, result)
        "readScreen" -> readScreen(call.argument<String>("path")!!, result)
        "setPlaces" ->
            result.success(
                PlaceStore.save(
                    this, call.argument<String>("places")!!, call.argument<Boolean>("summary") ?: false, call.argument<String>("dir")!!))
        // Item 102: Do not disturb during focus rounds. Without access, opens the page to grant it.
        "dndAllowed" -> result.success(getSystemService(NotificationManager::class.java).isNotificationPolicyAccessGranted)
        "askDnd" -> {
          try {
            startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS))
          } catch (e: Exception) {}
          result.success(null)
        }
        "setDnd" -> {
          val nm = getSystemService(NotificationManager::class.java)
          if (!nm.isNotificationPolicyAccessGranted) {
            result.success(false)
          } else {
            nm.setInterruptionFilter(
                if (call.argument<Boolean>("on") == true) NotificationManager.INTERRUPTION_FILTER_PRIORITY
                else NotificationManager.INTERRUPTION_FILTER_ALL)
            result.success(true)
          }
        }
        "batteryUnrestricted" ->
            result.success(getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(packageName))
        "askBatteryUnrestricted" -> {
          try {
            startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName")))
          } catch (e: Exception) {
            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
          }
          result.success(null)
        }
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
    shared = mapOf("text" to text, "subject" to intent.getStringExtra(Intent.EXTRA_SUBJECT), "voice" to isNote)
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

  /**
   * Item 111: a photo of a calendar on a screen, read word by word with where each word is, for
   * working out meeting times from their places. The photo is turned upright and saved again,
   * so the app can look at its colours with the same coordinates.
   */
  private fun readScreen(path: String, result: MethodChannel.Result) {
    Thread {
      try {
        val turn = when (ExifInterface(path).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
          ExifInterface.ORIENTATION_ROTATE_90 -> 90f
          ExifInterface.ORIENTATION_ROTATE_180 -> 180f
          ExifInterface.ORIENTATION_ROTATE_270 -> 270f
          else -> 0f
        }
        var bmp = BitmapFactory.decodeFile(path) ?: throw Exception("Could not open the photo")
        if (turn != 0f) {
          bmp = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, Matrix().apply { postRotate(turn) }, true)
        }
        val out = File(cacheDir, "work_screen.jpg")
        FileOutputStream(out).use { bmp.compress(Bitmap.CompressFormat.JPEG, 92, it) }
        val w = bmp.width
        val h = bmp.height
        bmp.recycle()
        // Read the upright copy, so the words' places are exactly those of the colours read
        // from it (no question of how the photo's turn is handled).
        runOnUiThread {
          try {
            TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
                .process(InputImage.fromFilePath(this, Uri.fromFile(out)))
                .addOnSuccessListener { text ->
                  try {
                    val words = ArrayList<Map<String, Any>>()
                    for (block in text.textBlocks) for (line in block.lines) {
                      val lr = line.boundingBox ?: continue
                      // Each word's own box when ML Kit gives it, otherwise the line split up by
                      // the length of its words.
                      val before = words.size
                      try {
                        for (el in line.elements) {
                          val r = el.boundingBox ?: continue
                          words.add(mapOf("t" to el.text, "l" to r.left, "top" to r.top, "r" to r.right, "b" to r.bottom))
                        }
                      } catch (e: Throwable) {
                        while (words.size > before) words.removeAt(words.size - 1)
                      }
                      if (words.size == before) words.addAll(splitLine(line.text, lr))
                    }
                    result.success(mapOf("path" to out.absolutePath, "width" to w, "height" to h, "words" to words))
                  } catch (e: Throwable) {
                    result.error("readScreen", "words: ${e.message}", null)
                  }
                }
                .addOnFailureListener { e -> result.error("readScreen", "reading: ${e.message}", null) }
          } catch (e: Throwable) {
            result.error("readScreen", "starting: ${e.message}", null)
          }
        }
      } catch (e: Throwable) {
        runOnUiThread { result.error("readScreen", "photo: ${e.message}", null) }
      }
    }.start()
  }

  /** A line's words with boxes shared out along the line by how many letters each has. */
  private fun splitLine(text: String, r: android.graphics.Rect): List<Map<String, Any>> {
    val parts = text.split(Regex("\\s+")).filter { it.isNotEmpty() }
    val chars = parts.sumOf { it.length } + (parts.size - 1).coerceAtLeast(0)
    if (chars == 0) return emptyList()
    val per = (r.right - r.left).toDouble() / chars
    var x = r.left.toDouble()
    val out = ArrayList<Map<String, Any>>()
    for (p in parts) {
      val w = p.length * per
      out.add(mapOf("t" to p, "l" to x.toInt(), "top" to r.top, "r" to (x + w).toInt(), "b" to r.bottom))
      x += w + per
    }
    return out
  }
}
