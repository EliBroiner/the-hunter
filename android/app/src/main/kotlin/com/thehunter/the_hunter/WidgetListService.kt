package com.thehunter.the_hunter

import android.content.Intent
import android.widget.RemoteViewsService
import android.util.Log

/**
 * RemoteViewsService — מאפשר ListView גלילה בווידג'ט.
 * מחזיר Factory שמספק פריטים לרשימה.
 */
class WidgetListService : RemoteViewsService() {

    override fun onGetViewFactory(intent: Intent): RemoteViewsService.RemoteViewsFactory {
        val appWidgetId = intent.getIntExtra(android.appwidget.AppWidgetManager.EXTRA_APPWIDGET_ID, 0)
        return WidgetListFactory(applicationContext, appWidgetId)
    }
}
