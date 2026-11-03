package app.taskblocks

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import java.io.File
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import org.json.JSONArray
import org.json.JSONObject

/**
 * Place reminders (item 33). The app hands over its saved places (lib/places.dart); Android's
 * geofencing watches them, also while the app is closed, and wakes [PlaceReceiver] on arriving
 * or leaving. The receiver reads the saved task list (tasks.json) and shows the reminders.
 */
object PlaceStore {
  private const val TAG = "PlaceStore"
  private const val PREFS = "place_reminders"

  fun prefs(ctx: Context) = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

  /** Saves what the app sent and (re)registers the geofences. False if Android refused. */
  fun save(ctx: Context, placesJson: String, summary: Boolean, dir: String): Boolean {
    prefs(ctx).edit().putString("places", placesJson).putBoolean("summary", summary).putString("dir", dir).apply()
    return register(ctx)
  }

  fun places(ctx: Context): List<JSONObject> {
    val arr = try {
      JSONArray(prefs(ctx).getString("places", "[]"))
    } catch (e: Exception) {
      JSONArray()
    }
    return (0 until arr.length()).map { arr.getJSONObject(it) }
  }

  private fun pendingIntent(ctx: Context): PendingIntent {
    val intent = Intent(ctx, PlaceReceiver::class.java).setAction("app.taskblocks.PLACE")
    // Geofencing fills in the event, so the intent must be mutable.
    val flags = PendingIntent.FLAG_UPDATE_CURRENT or
        (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
    return PendingIntent.getBroadcast(ctx, 7, intent, flags)
  }

  /** Registers every saved place (after a change, a reboot or an app update). */
  fun register(ctx: Context): Boolean {
    val client = LocationServices.getGeofencingClient(ctx)
    val pi = pendingIntent(ctx)
    client.removeGeofences(pi)
    val places = places(ctx)
    if (places.isEmpty()) return true
    val fine = ctx.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
    val background = Build.VERSION.SDK_INT < 29 ||
        ctx.checkSelfPermission(Manifest.permission.ACCESS_BACKGROUND_LOCATION) == PackageManager.PERMISSION_GRANTED
    if (!fine || !background) return false
    val fences = places.map {
      Geofence.Builder()
          .setRequestId(it.getString("id"))
          .setCircularRegion(it.getDouble("lat"), it.getDouble("lng"), it.optDouble("radius", 150.0).toFloat())
          .setExpirationDuration(Geofence.NEVER_EXPIRE)
          .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER or Geofence.GEOFENCE_TRANSITION_EXIT)
          .setNotificationResponsiveness(60_000)
          .build()
    }
    val request = GeofencingRequest.Builder()
        // Don't fire for the place the phone is already at when the places are saved.
        .setInitialTrigger(0)
        .addGeofences(fences)
        .build()
    return try {
      client.addGeofences(request, pi).addOnFailureListener { e -> Log.w(TAG, "addGeofences: $e") }
      true
    } catch (e: SecurityException) {
      Log.w(TAG, "no location permission: $e")
      false
    }
  }
}

/** Re-registers the geofences after a reboot or app update (Android forgets them). */
class PlaceBootReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    PlaceStore.register(context)
  }
}

/** Woken by Android on arriving at or leaving a saved place. */
class PlaceReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    val event = GeofencingEvent.fromIntent(intent) ?: return
    if (event.hasError()) return
    val arriving = when (event.geofenceTransition) {
      Geofence.GEOFENCE_TRANSITION_ENTER -> true
      Geofence.GEOFENCE_TRANSITION_EXIT -> false
      else -> return
    }
    val places = PlaceStore.places(context).associateBy { it.getString("id") }
    val pending = goAsync()
    Thread {
      try {
        for (fence in event.triggeringGeofences ?: emptyList()) {
          val place = places[fence.requestId] ?: continue
          remind(context, place.optString("name"), arriving)
        }
      } catch (e: Exception) {
        Log.w("PlaceReceiver", "remind: $e")
      } finally {
        pending.finish()
      }
    }.start()
  }

  private data class PlaceTask(val id: String, val title: String, val due: LocalDateTime?, val leave: Boolean)

  private fun remind(ctx: Context, place: String, arriving: Boolean) {
    val prefs = PlaceStore.prefs(ctx)
    val dir = prefs.getString("dir", null) ?: return
    val file = File(dir, "tasks.json")
    if (!file.exists()) return
    val root = JSONObject(file.readText())
    val active = root.optJSONArray("active") ?: return
    val now = LocalDateTime.now()
    val today = LocalDate.now()
    val endOfToday = today.plusDays(1).atStartOfDay()
    val fired = prefs.getStringSet("fired", emptySet())!!.toMutableSet()
    val atPlace = ArrayList<PlaceTask>()
    val dueToday = ArrayList<String>()
    for (i in 0 until active.length()) {
      val o = active.getJSONObject(i)
      val snoozed = parse(o.optString("snoozedUntil", ""))
      if (snoozed != null && snoozed.isAfter(now)) continue
      val due = parse(o.optString("dueAt", ""))
      if (due != null && due.isBefore(endOfToday)) dueToday.add(o.optString("title"))
      if (!o.optString("place", "").equals(place, ignoreCase = true)) continue
      atPlace.add(PlaceTask(o.getString("id"), o.optString("title"), due, o.optBoolean("placeLeave", false)))
    }
    for (t in atPlace) {
      if (t.leave == arriving) continue
      // With a due date: on the day it is due, and each day while overdue. Without one: once.
      val key = if (t.due == null) "${t.id}|once|${t.leave}" else "${t.id}|$today|${t.leave}"
      if (t.due != null && !t.due.isBefore(endOfToday)) continue
      if (!fired.add(key)) continue
      notify(ctx, t.id.hashCode(), if (arriving) "At $place" else "Leaving $place", t.title)
    }
    if (arriving && prefs.getBoolean("summary", false) && dueToday.isNotEmpty() && fired.add("summary|$place|$today")) {
      val names = dueToday.take(5).joinToString(", ") + if (dueToday.size > 5) "…" else ""
      notify(ctx, ("summary$place").hashCode(), "At $place: ${dueToday.size} task${if (dueToday.size == 1) "" else "s"} for today", names)
    }
    // Forget days gone by (keep the "once" keys).
    val keep = fired.filter { k -> !k.contains("|20") || k.contains("|$today") }.toSet()
    prefs.edit().putStringSet("fired", keep).apply()
  }

  /** The app saves local times without a zone, and UTC times with a Z. */
  private fun parse(s: String): LocalDateTime? {
    if (s.isEmpty() || s == "null") return null
    return try {
      if (s.endsWith("Z")) LocalDateTime.ofInstant(Instant.parse(s), ZoneId.systemDefault()) else LocalDateTime.parse(s)
    } catch (e: Exception) {
      null
    }
  }

  private fun notify(ctx: Context, id: Int, title: String, text: String) {
    // Notification channels need Android 8; older phones get no place reminders.
    if (Build.VERSION.SDK_INT < 26) return
    if (Build.VERSION.SDK_INT >= 33 &&
        ctx.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
    val nm = ctx.getSystemService(NotificationManager::class.java)
    nm.createNotificationChannel(
        NotificationChannel("places", "Place reminders", NotificationManager.IMPORTANCE_HIGH).apply {
          description = "Reminders when arriving at or leaving a saved place"
        })
    val open = PendingIntent.getActivity(
        ctx, id, ctx.packageManager.getLaunchIntentForPackage(ctx.packageName),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    val n = android.app.Notification.Builder(ctx, "places")
        .setSmallIcon(R.mipmap.ic_launcher)
        .setContentTitle(title)
        .setContentText(text)
        .setStyle(android.app.Notification.BigTextStyle().bigText(text))
        .setContentIntent(open)
        .setAutoCancel(true)
        .build()
    nm.notify(id, n)
  }
}
