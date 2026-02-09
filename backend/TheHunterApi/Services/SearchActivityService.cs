using Google.Cloud.Firestore;

namespace TheHunterApi.Services;

/// <summary>
/// רישום היסטוריית חיפושים — Firestore collection search_history, מסמך חדש לכל term.
/// </summary>
public interface ISearchActivityService
{
    Task RecordSearchTermsAsync(IEnumerable<string> terms, string? userId = null);
}

public class SearchActivityService : ISearchActivityService
{
    private const string ColSearchHistory = "search_history";
    private readonly FirestoreDb _firestore;

    public SearchActivityService(FirestoreDb firestore)
    {
        _firestore = firestore;
    }

    /// <summary>
    /// מוסיף מסמך לכל מונח: userId, term, timestamp.
    /// </summary>
    public async Task RecordSearchTermsAsync(IEnumerable<string> terms, string? userId = null)
    {
        var list = terms.Where(t => !string.IsNullOrWhiteSpace(t)).Select(t => t.Trim()).Distinct().ToList();
        if (list.Count == 0) return;

        var col = _firestore.Collection(ColSearchHistory);
        var now = Timestamp.FromDateTime(DateTime.UtcNow);
        foreach (var term in list)
        {
            await col.AddAsync(new Dictionary<string, object>
            {
                { "userId", userId ?? "" },
                { "term", term },
                { "timestamp", now }
            });
        }
    }
}
