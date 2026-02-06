namespace TheHunterApi.Services;

/// <summary>
/// ריכוז שגיאות 500 — נגיש מ-middleware ו-controller
/// </summary>
public static class AdminErrorTracker
{
    private static readonly List<string> _errors = new();
    private static readonly object _lock = new();
    private const int MaxErrors = 15;

    public static IReadOnlyList<string> RecentErrors
    {
        get { lock (_lock) { return _errors.Take(MaxErrors).ToList(); } }
    }

    /// <summary>
    /// מוסיף שגיאה לרשימה — מוגבל ל-15 רשומות אחרונות
    /// </summary>
    public static void AddError(string message)
    {
        lock (_lock)
        {
            _errors.Insert(0, $"{DateTime.Now:HH:mm:ss} - {message}");
            while (_errors.Count > MaxErrors) _errors.RemoveAt(_errors.Count - 1);
        }
    }

    /// <summary>
    /// מנקה את רשימת השגיאות
    /// </summary>
    public static void ClearErrors()
    {
        lock (_lock) { _errors.Clear(); }
    }
}
