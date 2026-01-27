package com.thehunter.the_hunter

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import android.app.PendingIntent
import android.view.View
import androidx.core.content.FileProvider
import es.antonborri.home_widget.HomeWidgetPlugin
import java.io.File

class SearchWidgetProvider : AppWidgetProvider() {
    
    companion object {
        const val ACTION_OPEN_FILE = "com.thehunter.ACTION_OPEN_FILE"
        const val ACTION_SHARE_FILE = "com.thehunter.ACTION_SHARE_FILE"
        const val EXTRA_FILE_PATH = "file_path"
    }
    
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }
    
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        
        val filePath = intent.getStringExtra(EXTRA_FILE_PATH) ?: return
        val file = File(filePath)
        
        if (!file.exists()) return
        
        when (intent.action) {
            ACTION_OPEN_FILE -> {
                try {
                    val uri = FileProvider.getUriForFile(
                        context,
                        "${context.packageName}.fileprovider",
                        file
                    )
                    val openIntent = Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(uri, getMimeType(filePath))
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    context.startActivity(openIntent)
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
            ACTION_SHARE_FILE -> {
                try {
                    val uri = FileProvider.getUriForFile(
                        context,
                        "${context.packageName}.fileprovider",
                        file
                    )
                    val shareIntent = Intent(Intent.ACTION_SEND).apply {
                        type = getMimeType(filePath)
                        putExtra(Intent.EXTRA_STREAM, uri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    context.startActivity(Intent.createChooser(shareIntent, "שתף קובץ").apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    })
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
        }
    }
    
    private fun getMimeType(path: String): String {
        val ext = path.substringAfterLast('.', "").lowercase()
        return when (ext) {
            "jpg", "jpeg" -> "image/jpeg"
            "png" -> "image/png"
            "gif" -> "image/gif"
            "webp" -> "image/webp"
            "pdf" -> "application/pdf"
            "doc", "docx" -> "application/msword"
            "xls", "xlsx" -> "application/vnd.ms-excel"
            "mp4" -> "video/mp4"
            "mp3" -> "audio/mpeg"
            "txt" -> "text/plain"
            else -> "*/*"
        }
    }

    override fun onEnabled(context: Context) {}
    override fun onDisabled(context: Context) {}
}

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
    val recentFileName = widgetData.getString("recent_file_name", null)
    val recentFilePath = widgetData.getString("recent_file_path", null)

    // Create RemoteViews
    val views = RemoteViews(context.packageName, R.layout.search_widget)
    
    // Update stats
    views.setTextViewText(R.id.files_count, filesCount.toString())
    views.setTextViewText(R.id.images_count, imagesCount.toString())
    views.setTextViewText(R.id.pdfs_count, pdfsCount.toString())

    // Open app intent
    val openAppIntent = Intent(context, MainActivity::class.java).apply {
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
    }
    val openAppPendingIntent = PendingIntent.getActivity(
        context, 0, openAppIntent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )
    
    // Set click listeners
    views.setOnClickPendingIntent(R.id.search_bar, openAppPendingIntent)
    views.setOnClickPendingIntent(R.id.stats_row, openAppPendingIntent)

    // Recent file section
    if (!recentFileName.isNullOrEmpty() && !recentFilePath.isNullOrEmpty()) {
        views.setViewVisibility(R.id.recent_file_container, View.VISIBLE)
        views.setTextViewText(R.id.recent_file_name, recentFileName)
        views.setTextViewText(R.id.recent_file_info, "נפתח לאחרונה")
        
        // Open file intent
        val openFileIntent = Intent(context, SearchWidgetProvider::class.java).apply {
            action = SearchWidgetProvider.ACTION_OPEN_FILE
            putExtra(SearchWidgetProvider.EXTRA_FILE_PATH, recentFilePath)
        }
        val openFilePendingIntent = PendingIntent.getBroadcast(
            context, 1, openFileIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.btn_open_file, openFilePendingIntent)
        views.setOnClickPendingIntent(R.id.recent_file_container, openFilePendingIntent)
        
        // Share file intent
        val shareFileIntent = Intent(context, SearchWidgetProvider::class.java).apply {
            action = SearchWidgetProvider.ACTION_SHARE_FILE
            putExtra(SearchWidgetProvider.EXTRA_FILE_PATH, recentFilePath)
        }
        val shareFilePendingIntent = PendingIntent.getBroadcast(
            context, 2, shareFileIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.btn_share_file, shareFilePendingIntent)
    } else {
        views.setViewVisibility(R.id.recent_file_container, View.GONE)
    }

    // Update the widget
    appWidgetManager.updateAppWidget(appWidgetId, views)
}
