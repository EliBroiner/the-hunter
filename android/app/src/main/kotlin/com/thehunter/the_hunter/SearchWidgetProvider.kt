package com.thehunter.the_hunter

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.app.PendingIntent
import android.graphics.Color
import android.view.View
import androidx.core.content.FileProvider
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray
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
            try {
                updateAppWidget(context, appWidgetManager, appWidgetId)
            } catch (e: Exception) {
                e.printStackTrace()
                updateAppWidgetEmptyState(context, appWidgetManager, appWidgetId)
            }
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

/**
 * Fail-Safe: קורא מ־SharedPreferences בלבד (widget_recent_data). ללא Isar.
 * STATE 1: רשימת 3 קבצים | STATE 2: מטמון ריק | STATE 3: שגיאת פרסור → Start Hunting
 */
fun updateAppWidget(
    context: Context,
    appWidgetManager: AppWidgetManager,
    appWidgetId: Int
) {
    val files = try {
        val widgetData = HomeWidgetPlugin.getData(context)
        val raw = widgetData.getString("widget_recent_data", null)
            ?: widgetData.getString("widget_recent_files", null)
        parseCachedFiles(raw)
    } catch (e: Exception) {
        e.printStackTrace()
        emptyList()
    }

    val views = RemoteViews(context.packageName, R.layout.search_widget)

    val openAppIntent = Intent(context, MainActivity::class.java).apply {
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
    }
    val openAppPendingIntent = PendingIntent.getActivity(
        context, 0, openAppIntent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )

    views.setOnClickPendingIntent(R.id.search_bar, openAppPendingIntent)

    if (files.isEmpty()) {
        showStartHuntingState(context, appWidgetManager, appWidgetId, views, openAppPendingIntent)
        return
    }

    views.setViewVisibility(R.id.files_list, View.VISIBLE)
    views.setViewVisibility(R.id.start_hunting_btn, View.GONE)

        val rowIds = listOf(R.id.file_row_1, R.id.file_row_2, R.id.file_row_3)
        val nameIds = listOf(R.id.file_1_name, R.id.file_2_name, R.id.file_3_name)
        val catIds = listOf(R.id.file_1_category, R.id.file_2_category, R.id.file_3_category)
        val iconIds = listOf(R.id.file_1_icon, R.id.file_2_icon, R.id.file_3_icon)
        val iconContainerIds = listOf(R.id.file_1_icon_container, R.id.file_2_icon_container, R.id.file_3_icon_container)

        for (i in 0 until 3) {
            val rowId = rowIds[i]
            val nameId = nameIds[i]
            val catId = catIds[i]
            val iconId = iconIds[i]
            val iconContainerId = iconContainerIds[i]
            if (i < files.size) {
                val (name, category, path) = files[i]
                views.setViewVisibility(rowId, View.VISIBLE)
                views.setTextViewText(nameId, name)
                views.setTextViewText(catId, category)
                views.setImageViewResource(iconId, getIconForCategory(category, path))
                views.setInt(iconId, "setColorFilter", getColorForCategory(category))
                views.setInt(iconContainerId, "setBackgroundResource", getIconBgForCategory(category))

            val openFileIntent = Intent(context, SearchWidgetProvider::class.java).apply {
                action = SearchWidgetProvider.ACTION_OPEN_FILE
                putExtra(SearchWidgetProvider.EXTRA_FILE_PATH, path)
            }
            val openFilePendingIntent = PendingIntent.getBroadcast(
                context, i + 1, openFileIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(rowId, openFilePendingIntent)
        } else {
            views.setViewVisibility(rowId, View.GONE)
        }
    }

    appWidgetManager.updateAppWidget(appWidgetId, views)
}

/** צבע לפי קטגוריה — תמיכה דו־לשונית */
private fun getColorForCategory(category: String?): Int {
    if (category.isNullOrEmpty()) return Color.parseColor("#9E9E9E")
    val c = category.lowercase()
    return when {
        c.contains("financial") || c.contains("כספי") || c.contains("invoice") || c.contains("חשבונית") ||
        c.contains("receipt") || c.contains("קבלה") || c.contains("bank") || c.contains("בנק") ->
            Color.parseColor("#4CAF50")
        c.contains("travel") || c.contains("נסיעות") || c.contains("flight") || c.contains("טיסה") ||
        c.contains("trip") || c.contains("טיול") -> Color.parseColor("#2196F3")
        c.contains("medical") || c.contains("רפואי") || c.contains("health") || c.contains("בריאות") ->
            Color.parseColor("#F44336")
        c.contains("id") || c.contains("תעודה") || c.contains("passport") || c.contains("דרכון") ||
        c.contains("legal") || c.contains("משפטי") || c.contains("contract") || c.contains("חוזה") ->
            Color.parseColor("#FFC107")
        else -> Color.parseColor("#9E9E9E")
    }
}

/** רקע עיגול 10% opacity לפי קטגוריה */
private fun getIconBgForCategory(category: String?): Int {
    if (category.isNullOrEmpty()) return R.drawable.icon_bg_grey
    val c = category.lowercase()
    return when {
        c.contains("financial") || c.contains("כספי") || c.contains("invoice") || c.contains("חשבונית") ||
        c.contains("receipt") || c.contains("קבלה") || c.contains("bank") || c.contains("בנק") ->
            R.drawable.icon_bg_green
        c.contains("travel") || c.contains("נסיעות") || c.contains("flight") || c.contains("טיסה") ||
        c.contains("trip") || c.contains("טיול") -> R.drawable.icon_bg_blue
        c.contains("medical") || c.contains("רפואי") || c.contains("health") || c.contains("בריאות") ->
            R.drawable.icon_bg_red
        c.contains("id") || c.contains("תעודה") || c.contains("passport") || c.contains("דרכון") ||
        c.contains("legal") || c.contains("משפטי") || c.contains("contract") || c.contains("חוזה") ->
            R.drawable.icon_bg_amber
        else -> R.drawable.icon_bg_grey
    }
}

/** אייקון לפי קטגוריה — תמיכה דו־לשונית. fallback לפי path */
private fun getIconForCategory(category: String?, path: String): Int {
    val c = (category ?: "").lowercase()
    when {
        c.contains("invoice") || c.contains("חשבונית") || c.contains("receipt") || c.contains("קבלה") ->
            return android.R.drawable.ic_menu_edit
        c.contains("document") || c.contains("מסמך") -> return android.R.drawable.ic_menu_agenda
        c.contains("image") || c.contains("תמונה") || c.contains("photo") -> return android.R.drawable.ic_menu_gallery
        c.contains("pdf") -> return android.R.drawable.ic_menu_save
        c.contains("contract") || c.contains("חוזה") -> return android.R.drawable.ic_menu_manage
        c.contains("id") || c.contains("תעודה") -> return android.R.drawable.ic_menu_myplaces
    }
    val ext = path.substringAfterLast('.', "").lowercase()
    return when {
        ext == "pdf" -> android.R.drawable.ic_menu_save
        ext in listOf("jpg", "jpeg", "png", "gif", "webp", "bmp", "heic", "heif") ->
            android.R.drawable.ic_menu_gallery
        else -> android.R.drawable.ic_menu_recent_history
    }
}

private fun parseCachedFiles(raw: String?): List<Triple<String, String, String>> {
    if (raw.isNullOrEmpty()) return emptyList()
    return try {
        val arr = JSONArray(raw)
        val list = mutableListOf<Triple<String, String, String>>()
        for (i in 0 until minOf(arr.length(), 3)) {
            val obj = arr.getJSONObject(i)
            val n = obj.optString("n", "")
            val p = obj.optString("p", "")
            if (n.isNotEmpty() && p.isNotEmpty()) {
                list.add(Triple(n, obj.optString("c", "—"), p))
            }
        }
        list
    } catch (_: Exception) {
        emptyList()
    }
}

/** מצב ריק — מטמון ריק או כשל טעינה */
private fun updateAppWidgetEmptyState(
    context: Context,
    appWidgetManager: AppWidgetManager,
    appWidgetId: Int
) {
    val views = RemoteViews(context.packageName, R.layout.search_widget)
    val openAppIntent = Intent(context, MainActivity::class.java).apply {
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
    }
    val openAppPendingIntent = PendingIntent.getActivity(
        context, 0, openAppIntent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )
    showStartHuntingState(context, appWidgetManager, appWidgetId, views, openAppPendingIntent)
}

private fun showStartHuntingState(
    context: Context,
    appWidgetManager: AppWidgetManager,
    appWidgetId: Int,
    views: RemoteViews,
    openAppPendingIntent: PendingIntent
) {
    views.setViewVisibility(R.id.files_list, View.GONE)
    views.setViewVisibility(R.id.start_hunting_btn, View.VISIBLE)
    views.setOnClickPendingIntent(R.id.search_bar, openAppPendingIntent)
    views.setOnClickPendingIntent(R.id.start_hunting_btn, openAppPendingIntent)
    appWidgetManager.updateAppWidget(appWidgetId, views)
}
