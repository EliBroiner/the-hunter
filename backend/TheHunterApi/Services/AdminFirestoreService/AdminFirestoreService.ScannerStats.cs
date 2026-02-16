using Google.Cloud.Firestore;
using TheHunterApi.Models;

namespace TheHunterApi.Services;

/// <summary>חלק partial — לוגים, ranking, scanner_settings, processing_chains, File X-Ray.</summary>
public partial class AdminFirestoreService
{
    /// <summary>לוגים/פעילות חיפוש — collection 'logs'.</summary>
    public async Task<(List<SearchActivity> Activities, bool Ok)> GetLogsAsync(int limit = 50)
    {
        try
        {
            var query = _db.Collection(ColLogs).OrderByDescending("count").Limit(limit);
            var snapshot = await query.GetSnapshotAsync();
            var list = new List<SearchActivity>();
            int id = 1;
            foreach (var doc in snapshot.Documents)
            {
                var a = MapDocToSearchActivity(doc.Id, doc.ToDictionary(), id++);
                if (a != null) list.Add(a);
            }
            if (list.Count == 0) LogEmptyCollectionWarning(ColLogs);
            return (list, true);
        }
        catch (Exception ex)
        {
            LogIfPermissionDenied(ex, "GetLogs");
            _logger.LogError(ex, "ERROR fetching from Firestore: {Message}", ex.Message);
            return (new List<SearchActivity>(), false);
        }
    }

    /// <summary>משקלי דירוג — ranking_settings.</summary>
    public async Task<(Dictionary<string, double> Weights, bool Ok)> GetRankingWeightsAsync()
    {
        try
        {
            var snapshot = await _db.Collection(ColRankingSettings).GetSnapshotAsync();
            var dict = new Dictionary<string, double>();
            foreach (var doc in snapshot.Documents)
            {
                var v = doc.GetValue<double?>("value");
                if (v.HasValue) dict[doc.Id] = v.Value;
            }
            if (dict.Count == 0) LogEmptyCollectionWarning(ColRankingSettings);
            return (dict, true);
        }
        catch (Exception ex)
        {
            LogIfPermissionDenied(ex, "GetRankingWeights");
            _logger.LogError(ex, "ERROR fetching from Firestore: {Message}", ex.Message);
            return (new Dictionary<string, double>(), false);
        }
    }

    public async Task SetRankingWeightsAsync(Dictionary<string, double> weights)
    {
        if (weights.Count == 0) return;
        LogWriteAttempt(ColRankingSettings, "Set");
        var col = _db.Collection(ColRankingSettings);
        foreach (var kvp in weights)
            await col.Document(kvp.Key).SetAsync(new Dictionary<string, object> { { "value", kvp.Value } }, SetOptions.MergeAll);
    }

    /// <summary>הגדרות סריקה — scanner_settings.</summary>
    public async Task<Dictionary<string, double>> GetScannerSettingsAsync()
    {
        try
        {
            var snapshot = await _db.Collection(ColScannerSettings).GetSnapshotAsync();
            var dict = new Dictionary<string, double>();
            foreach (var doc in snapshot.Documents)
            {
                try
                {
                    var field = doc.GetValue<object>("value");
                    double? v = field switch
                    {
                        double d => d,
                        int i => i,
                        long l => l,
                        float f => f,
                        _ => field != null && double.TryParse(field.ToString(), out var parsed) ? parsed : null
                    };
                    if (v.HasValue) dict[doc.Id] = v.Value;
                }
                catch (Exception ex) { _logger.LogWarning(ex, "Skip scanner_settings doc {DocId}", doc.Id); }
            }
            return dict;
        }
        catch (Exception ex)
        {
            LogIfPermissionDenied(ex, "GetScannerSettings");
            _logger.LogError(ex, "GetScannerSettings: {Message}", ex.Message);
            return new Dictionary<string, double>();
        }
    }

    public async Task SetScannerSettingAsync(string key, double value)
    {
        try
        {
            LogWriteAttempt(ColScannerSettings, "Set");
            await _db.Collection(ColScannerSettings).Document(key).SetAsync(
                new Dictionary<string, object> { { "value", value } }, SetOptions.MergeAll);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "SetScannerSetting {Key}: {Message}", key, ex.Message);
            throw;
        }
    }

    /// <summary>מגדיל מונה תמונות שדולגו (No Text Detected).</summary>
    public async Task IncrementImagesSkippedNoTextAsync()
    {
        try
        {
            var docRef = _db.Collection(ColScanStats).Document("counters");
            await _db.RunTransactionAsync(async transaction =>
            {
                var snap = await transaction.GetSnapshotAsync(docRef);
                if (!snap.Exists)
                    transaction.Set(docRef, new Dictionary<string, object>
                    {
                        { "imagesSkippedNoText", 1L },
                        { "lastUpdated", Timestamp.FromDateTime(DateTime.UtcNow) }
                    });
                else
                    transaction.Update(docRef, new Dictionary<string, object>
                    {
                        { "imagesSkippedNoText", FieldValue.Increment(1) },
                        { "lastUpdated", Timestamp.FromDateTime(DateTime.UtcNow) }
                    });
            });
        }
        catch (Exception ex) { _logger.LogError(ex, "IncrementImagesSkippedNoText failed"); }
    }

    public async Task<long> GetImagesSkippedNoTextCountAsync()
    {
        try
        {
            var snap = await _db.Collection(ColScanStats).Document("counters").GetSnapshotAsync();
            if (!snap.Exists) return 0;
            var data = snap.ToDictionary();
            if (!data.TryGetValue("imagesSkippedNoText", out var val) || val == null) return 0;
            return Convert.ToInt64(val);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "GetImagesSkippedNoTextCount failed");
            return 0;
        }
    }

    /// <summary>שומר שרשרת עיבוד — processing_chains.</summary>
    public async Task SaveProcessingChainAsync(string documentId, string chain, string? filename = null,
        string? rawText = null, string? cleanedText = null, string? ocrSource = null,
        IReadOnlyList<string>? tags = null, string? category = null)
    {
        try
        {
            var data = new Dictionary<string, object>
            {
                { "chain", chain },
                { "filename", filename ?? "" },
                { "timestamp", Timestamp.FromDateTime(DateTime.UtcNow) }
            };
            if (!string.IsNullOrEmpty(rawText)) data["rawText"] = rawText.Length > 50000 ? rawText.Substring(0, 50000) + "…" : rawText;
            if (!string.IsNullOrEmpty(cleanedText)) data["cleanedText"] = cleanedText.Length > 50000 ? cleanedText.Substring(0, 50000) + "…" : cleanedText;
            if (!string.IsNullOrEmpty(ocrSource)) data["ocrSource"] = ocrSource;
            if (tags != null && tags.Count > 0) data["tags"] = tags.ToArray();
            if (!string.IsNullOrEmpty(category)) data["category"] = category;
            await _db.Collection(ColProcessingChains).Document(documentId).SetAsync(data, SetOptions.MergeAll);
        }
        catch (Exception ex) { _logger.LogError(ex, "SaveProcessingChain failed for doc {DocId}", documentId); }
    }

    /// <summary>מוחק processing_chains ישנים מ-30 יום.</summary>
    public async Task<int> CleanupOldProcessingChainsAsync(int maxAgeDays = 30)
    {
        try
        {
            var cutoff = Timestamp.FromDateTime(DateTime.UtcNow.AddDays(-maxAgeDays));
            var snap = await _db.Collection(ColProcessingChains)
                .WhereLessThan("timestamp", cutoff)
                .GetSnapshotAsync();
            var count = 0;
            foreach (var doc in snap.Documents)
            {
                await doc.Reference.DeleteAsync();
                count++;
            }
            if (count > 0) _logger.LogInformation("[processing_chains] Deleted {Count} old logs", count);
            return count;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "CleanupOldProcessingChains failed");
            return 0;
        }
    }

    public async Task<string?> GetProcessingChainAsync(string documentId)
    {
        try
        {
            var snap = await _db.Collection(ColProcessingChains).Document(documentId).GetSnapshotAsync();
            if (!snap.Exists) return null;
            return snap.GetValue<string>("chain");
        }
        catch { return null; }
    }

    /// <summary>נתוני File X-Ray — processing_chains + scan_failures.</summary>
    public async Task<FileXRayData?> GetFileXRayAsync(string documentId)
    {
        try
        {
            var chainSnap = await _db.Collection(ColProcessingChains).Document(documentId).GetSnapshotAsync();
            if (!chainSnap.Exists)
            {
                var failure = await GetScanFailureByDocumentIdAsync(documentId);
                return failure != null ? new FileXRayData
                {
                    DocumentId = documentId, Filename = failure.Filename, RawText = failure.RawText,
                    OcrSource = "Local (Failed)", ProcessingChain = null
                } : null;
            }
            var d = chainSnap.ToDictionary();
            var tags = new List<string>();
            if (d.TryGetValue("tags", out var tVal) && tVal is System.Collections.IEnumerable en)
            {
                foreach (var item in en) tags.Add(item?.ToString() ?? "");
            }
            return new FileXRayData
            {
                DocumentId = documentId,
                Filename = GetString(d, "filename"),
                ProcessingChain = GetString(d, "chain"),
                RawText = GetString(d, "rawText"),
                CleanedText = GetString(d, "cleanedText"),
                OcrSource = GetString(d, "ocrSource"),
                Tags = tags,
                Category = GetString(d, "category")
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "GetFileXRay failed for doc {DocId}", documentId);
            return null;
        }
    }

    private static string GetString(IReadOnlyDictionary<string, object> d, string key) =>
        d.TryGetValue(key, out var v) && v != null ? v.ToString() ?? "" : "";

    private static SearchActivity? MapDocToSearchActivity(string docId, IReadOnlyDictionary<string, object> data, int id)
    {
        try
        {
            var term = GetField(data, "term")?.ToString() ?? docId;
            var count = 0;
            var c = GetField(data, "count");
            if (c is long l) count = (int)l;
            else if (c is int i) count = i;
            var lastSearch = DateTime.UtcNow;
            if (GetField(data, "lastSearch") is Timestamp ts) lastSearch = ts.ToDateTime();
            return new SearchActivity { Id = id, Term = term, Count = count, LastSearch = lastSearch };
        }
        catch { return null; }
    }
}
