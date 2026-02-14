package com.thehunter.the_hunter

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

private const val TAG = "WidgetListFactory"
private const val MAX_ITEMS = 15

/**
 * RemoteViewsFactory — מספק פריטים ל־ListView בווידג'ט.
 */
class WidgetListFactory(
    private val context: Context,
    private val appWidgetId: Int
) : RemoteViewsService.RemoteViewsFactory {

    private var files: List<WidgetFile> = emptyList()

    override fun onCreate() {}

    override fun onDataSetChanged() {
        files = try {
            val widgetData = HomeWidgetPlugin.getData(context)
            val raw = widgetData.getString("widget_recent_data", null)
                ?: widgetData.getString("widget_recent_files", null)
            parseCachedFiles(raw)
        } catch (e: Exception) {
            Log.e(TAG, "WidgetListFactory parse error", e)
            emptyList()
        }
        Log.i(TAG, "[WIDGET] Initialized scrollable factory with ${files.size} items.")
    }

    override fun onDestroy() {}

    override fun getCount(): Int = files.size

    override fun getViewAt(position: Int): RemoteViews? {
        if (position >= files.size) return null
        val f = files[position]
        val rv = RemoteViews(context.packageName, R.layout.widget_list_item)

        rv.setTextViewText(R.id.item_category, cleanCategoryForDisplay(f.category))
        rv.setTextViewText(R.id.item_name, cleanFilenameForDisplay(f.name))
        rv.setTextViewText(R.id.item_trailing, formatDateForDisplay(f.timestamp))
        rv.setImageViewResource(R.id.item_icon, getIconForCategory(f.category, f.path))
        rv.setInt(R.id.item_icon, "setColorFilter", getColorForCategory(f.category))
        rv.setInt(R.id.item_icon_container, "setBackgroundResource", getIconBgForCategory(f.category))

        val openFileIntent = Intent(context, SearchWidgetProvider::class.java).apply {
            action = SearchWidgetProvider.ACTION_OPEN_FILE
            putExtra(SearchWidgetProvider.EXTRA_FILE_PATH, f.path)
        }
        val openFilePendingIntent = PendingIntent.getBroadcast(
            context, position + 100, openFileIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        rv.setOnClickPendingIntent(R.id.widget_list_item_root, openFilePendingIntent)

        return rv
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = true

    private fun parseCachedFiles(raw: String?): List<WidgetFile> {
        if (raw.isNullOrEmpty()) return emptyList()
        return try {
            val arr = JSONArray(raw)
            val list = mutableListOf<WidgetFile>()
            for (i in 0 until minOf(arr.length(), MAX_ITEMS)) {
                val obj = arr.getJSONObject(i)
                val n = obj.optString("n", "")
                val p = obj.optString("p", "")
                if (n.isNotEmpty() && p.isNotEmpty()) {
                    list.add(WidgetFile(
                        name = n,
                        category = obj.optString("c", "—"),
                        path = p,
                        timestamp = obj.optLong("t", 0L)
                    ))
                }
            }
            list
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun cleanFilenameForDisplay(filename: String): String {
        if (filename.isBlank()) return "—"
        var s = filename
        while (s.contains(".")) s = s.substring(0, s.lastIndexOf('.'))
        s = s.replace(Regex("-\\d+$"), "")
        s = s.replace(Regex("\\d{4}[-_]?\\d{2}[-_]?\\d{2}"), "")
        s = s.replace(Regex("\\d{2}[-_]\\d{2}[-_]\\d{4}"), "")
        s = s.replace("_", " ").replace("-", " ")
        return s.trim().replace(Regex("\\s+"), " ").ifBlank { filename }
    }

    private fun cleanCategoryForDisplay(category: String?): String {
        if (category.isNullOrBlank()) return "—"
        return category.replace("_", " ").replace("-", " ").trim()
    }

    private fun formatDateForDisplay(timestamp: Long): String {
        if (timestamp <= 0) return "›"
        val date = Date(timestamp)
        val today = Date()
        val sdf = SimpleDateFormat("dd/MM", Locale("he"))
        return if (sdf.format(date) == sdf.format(today)) "היום" else sdf.format(date)
    }

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
            c.contains("salary") || c.contains("payslip") || c.contains("תלוש") || c.contains("משכורת") ->
                Color.parseColor("#4CAF50")
            else -> Color.parseColor("#9E9E9E")
        }
    }

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
            c.contains("salary") || c.contains("payslip") || c.contains("תלוש") || c.contains("משכורת") ->
                R.drawable.icon_bg_green
            else -> R.drawable.icon_bg_grey
        }
    }

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
}
