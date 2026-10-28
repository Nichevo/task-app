package com.jeff.task_blocks

import android.content.ContentUris
import android.content.Context
import android.provider.CalendarContract

data class DeviceCalendar(val id: String, val name: String, val account: String)

data class DeviceEvent(
    val id: String,
    val calendarId: String,
    val title: String,
    val start: Long,
    val allDay: Boolean,
    val location: String?,
)

/** Reads the phone's calendars through Android's calendar provider. Nothing leaves the phone. */
object CalendarStore {
  fun calendars(c: Context): List<DeviceCalendar> {
    val out = ArrayList<DeviceCalendar>()
    val projection =
        arrayOf(
            CalendarContract.Calendars._ID,
            CalendarContract.Calendars.CALENDAR_DISPLAY_NAME,
            CalendarContract.Calendars.ACCOUNT_NAME,
        )
    c.contentResolver.query(CalendarContract.Calendars.CONTENT_URI, projection, null, null, null)?.use { cur ->
      while (cur.moveToNext()) {
        out.add(DeviceCalendar(cur.getLong(0).toString(), cur.getString(1) ?: "", cur.getString(2) ?: ""))
      }
    }
    return out
  }

  /** Event instances starting between [from] and [to], in the given calendars (all when empty). */
  fun events(c: Context, from: Long, to: Long, calendarIds: Set<String>): List<DeviceEvent> {
    val out = ArrayList<DeviceEvent>()
    val builder = CalendarContract.Instances.CONTENT_URI.buildUpon()
    ContentUris.appendId(builder, from)
    ContentUris.appendId(builder, to)
    val projection =
        arrayOf(
            CalendarContract.Instances.EVENT_ID,
            CalendarContract.Instances.CALENDAR_ID,
            CalendarContract.Instances.TITLE,
            CalendarContract.Instances.BEGIN,
            CalendarContract.Instances.ALL_DAY,
            CalendarContract.Instances.EVENT_LOCATION,
            CalendarContract.Instances._ID,
        )
    c.contentResolver.query(builder.build(), projection, null, null, CalendarContract.Instances.BEGIN + " ASC")?.use {
        cur ->
      while (cur.moveToNext()) {
        val calId = cur.getLong(1).toString()
        if (calendarIds.isNotEmpty() && !calendarIds.contains(calId)) continue
        val begin = cur.getLong(3)
        if (begin < from) continue
        val allDay = cur.getInt(4) == 1
        // Instance id + start keeps repeating events apart.
        out.add(
            DeviceEvent(
                "${cur.getLong(0)}@${begin}",
                calId,
                cur.getString(2) ?: "",
                if (allDay) localMidnight(begin) else begin,
                allDay,
                cur.getString(5),
            ))
      }
    }
    return out
  }

  /** All-day events are stored at UTC midnight; show them at local midnight. */
  private fun localMidnight(utcMs: Long): Long {
    val cal = java.util.Calendar.getInstance(java.util.TimeZone.getTimeZone("UTC"))
    cal.timeInMillis = utcMs
    val local = java.util.Calendar.getInstance()
    local.set(cal.get(java.util.Calendar.YEAR), cal.get(java.util.Calendar.MONTH), cal.get(java.util.Calendar.DAY_OF_MONTH), 0, 0, 0)
    local.set(java.util.Calendar.MILLISECOND, 0)
    return local.timeInMillis
  }
}
