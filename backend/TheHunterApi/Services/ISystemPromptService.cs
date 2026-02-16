using TheHunterApi.Models;

namespace TheHunterApi.Services;

/// <summary>
/// שירות ניהול פרומפטים למערכת — שליפה, הוספת טיוטה, והחלפת פרומפט פעיל.
/// </summary>
public interface ISystemPromptService
{
    /// <summary>
    /// מביא את הפרומפט הפעיל עבור feature נתון.
    /// </summary>
    /// <param name="feature">Search, Summary, Tags, DocAnalysis וכו'.</param>
    /// <returns>הפרומפט הפעיל או null אם אין.</returns>
    Task<SystemPrompt?> GetActivePromptAsync(string feature);

    /// <summary>
    /// מוסיף פרומפט חדש כטיוטה (IsActive = false).
    /// </summary>
    /// <param name="feature">מזהה feature.</param>
    /// <param name="content">תוכן הפרומפט.</param>
    /// <param name="version">מזהה גרסה (למשל "1.1").</param>
    /// <returns>הפרומפט שנוצר.</returns>
    Task<SystemPrompt> AddDraftAsync(string feature, string content, string version);

    /// <summary>
    /// מפעיל פרומפט מסוים — משנה את IsActive ל-true עבור ה-promptId, ומבטל פעילות של כל השאר באותו feature בטרנזקציה.
    /// </summary>
    /// <param name="promptId">מזהה הפרומפט להפעלה.</param>
    /// <returns>true בהצלחה, false אם הפרומפט לא נמצא.</returns>
    Task<bool> SetActiveAsync(int promptId);

    /// <summary>
    /// מפעיל פרומפט לפי feature+version — משנה IsActive ל-true עבור המסמך המתאים, ומבטל את השאר באותו feature.
    /// </summary>
    Task<bool> SetActiveByFeatureVersionAsync(string feature, string version);

    /// <summary>
    /// מביא פרומפטים לפי feature — ממוין לפי גרסה יורד (1.2, 1.1, 1.0).
    /// </summary>
    Task<List<SystemPrompt>> GetPromptsForFeatureAsync(string feature);

    /// <summary>
    /// מביא היסטוריית פרומפטים — מסונן לפי feature (אופציונלי), ממוין לפי CreatedAt יורד.
    /// </summary>
    Task<List<SystemPrompt>> GetListAsync(string? feature = null);
}
