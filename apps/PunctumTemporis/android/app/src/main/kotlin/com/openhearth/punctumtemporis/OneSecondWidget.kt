package com.openhearth.punctumtemporis

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class OneSecondWidget : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    companion object {
        private const val HOME_WIDGET_PREFS = "HomeWidgetPreferences"

        private fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val prefs = context.getSharedPreferences(HOME_WIDGET_PREFS, Context.MODE_PRIVATE)
            val streak = prefs.getInt("streak", 0)
            val capturedToday = prefs.getBoolean("captured_today", false)

            val views = RemoteViews(context.packageName, R.layout.one_second_widget)

            views.setTextViewText(R.id.streak_text, streak.toString())
            views.setTextViewText(
                R.id.streak_label,
                if (streak == 1) "DAY STREAK" else "DAYS STREAK"
            )
            views.setTextViewText(
                R.id.status_text,
                if (capturedToday) "TODAY: CAPTURED" else "TODAY: NOT YET"
            )

            val launchIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                appWidgetId,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
