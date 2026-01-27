package com.thehunter.the_hunter

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.widget.RemoteViews
import android.app.PendingIntent
import es.antonborri.home_widget.HomeWidgetPlugin

class SearchWidgetProvider : AppWidgetProvider() {
    
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onEnabled(context: Context) {
        // First widget added
    }

    override fun onDisabled(context: Context) {
        // Last widget removed
    }

    companion object {
        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            // Get data from SharedPreferences (set by Flutter)
            val widgetData = HomeWidgetPlugin.getData(context)
            val filesCount = widgetData.getInt("files_count", 0)
            val imagesCount = widgetData.getInt("images_count", 0)
            val pdfsCount = widgetData.getInt("pdfs_count", 0)

            // Create RemoteViews
            val views = RemoteViews(context.packageName, R.layout.search_widget)
            
            // Update text views
            views.setTextViewText(R.id.files_count, filesCount.toString())
            views.setTextViewText(R.id.images_count, imagesCount.toString())
            views.setTextViewText(R.id.pdfs_count, pdfsCount.toString())

            // Create intent to open app on click
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                context, 
                0, 
                intent, 
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            // Set click listener on the whole widget
            views.setOnClickPendingIntent(R.id.widget_container, pendingIntent)
            views.setOnClickPendingIntent(R.id.search_bar, pendingIntent)

            // Update the widget
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
