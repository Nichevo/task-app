package com.jeff.task_blocks

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context

/**
 * Redraws the widgets every 15 minutes (the shortest Android allows for a periodic job) so
 * the colours keep moving between the app's own updates. Only runs while a widget exists.
 */
class WidgetRefreshJob : JobService() {
  override fun onStartJob(params: JobParameters?): Boolean {
    WidgetData.refreshAll(this)
    return false
  }

  override fun onStopJob(params: JobParameters?): Boolean = false

  companion object {
    private const val JOB_ID = 4242

    fun schedule(c: Context) {
      val scheduler = c.getSystemService(Context.JOB_SCHEDULER_SERVICE) as JobScheduler
      if (scheduler.getPendingJob(JOB_ID) != null) return
      scheduler.schedule(
          JobInfo.Builder(JOB_ID, ComponentName(c, WidgetRefreshJob::class.java))
              .setPeriodic(15 * 60 * 1000L)
              .setPersisted(true)
              .build())
    }

    fun cancelIfNoWidgets(c: Context) {
      if (WidgetData.anyWidgets(c)) return
      (c.getSystemService(Context.JOB_SCHEDULER_SERVICE) as JobScheduler).cancel(JOB_ID)
    }
  }
}
