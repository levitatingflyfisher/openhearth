package com.openhearth.porch_app

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews

// Static homescreen-widget spike. The real presence→widget data bridge is not
// built yet (see HONEST-STATUS) — the pre-competition version extended
// home_widget's HomeWidgetProvider, but the ground-up client deferred the
// widget layer and doesn't depend on home_widget, so this stands on the
// Android framework AppWidgetProvider and renders placeholder text. It makes
// the widget pickable and exercises the layout; wiring live presence into it
// is future work.
class PorchWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.porch_widget_layout).apply {
                setTextViewText(R.id.widget_title, "Porch")
                setTextViewText(R.id.widget_status, "Open Porch to see who's around")
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
