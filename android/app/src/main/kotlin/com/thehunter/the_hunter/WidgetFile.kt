package com.thehunter.the_hunter

/** מודל משותף לווידג'ט — SearchWidgetProvider + WidgetListFactory */
internal data class WidgetFile(
    val name: String,
    val category: String,
    val path: String,
    val timestamp: Long
)
