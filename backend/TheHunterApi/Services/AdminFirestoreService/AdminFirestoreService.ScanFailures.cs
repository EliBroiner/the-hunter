using Google.Cloud.Firestore;
using TheHunterApi.Models;

namespace TheHunterApi.Services;

/// <summary>חלק partial — כשלונות סריקה (scan_failures).</summary>
public partial class AdminFirestoreService
{
    /// <summary>כשלונות Meaningful Text Check — אחרונים 10.</summary>
    public async Task<(List<ScanFailure> Failures, bool Ok)> GetScanFailuresAsync(int limit = 10)
    {
        try
        {
            var query = _db.Collection(ColScanFailures)
                .OrderByDescending("timestamp")
                .Limit(limit);
            var snapshot = await query.GetSnapshotAsync();
            var list = new List<ScanFailure>();
            foreach (var doc in snapshot.Documents)
            {
                var f = MapDocToScanFailure(doc.Id, doc.ToDictionary());
                if (f != null) list.Add(f);
            }
            return (list, true);
        }
        catch (Exception ex)
        {
            LogIfPermissionDenied(ex, "GetScanFailures");
            _logger.LogError(ex, "ERROR fetching scan_failures: {Message}", ex.Message);
            return (new List<ScanFailure>(), false);
        }
    }

    /// <summary>מחזיר כשלון בודד לפי Id.</summary>
    public async Task<ScanFailure?> GetScanFailureByIdAsync(string id)
    {
        try
        {
            var snap = await _db.Collection(ColScanFailures).Document(id).GetSnapshotAsync();
            if (!snap.Exists) return null;
            return MapDocToScanFailure(snap.Id, snap.ToDictionary());
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "GetScanFailureById {Id}: {Message}", id, ex.Message);
            return null;
        }
    }

    /// <summary>דיווח כשלון מהאפליקציה.</summary>
    public async Task<string?> AddScanFailureAsync(string documentId, string filename, string rawText, double? garbageRatioPercent, string? userId, string? reasonForUpload = null)
    {
        try
        {
            LogWriteAttempt(ColScanFailures, "Add");
            var col = _db.Collection(ColScanFailures);
            var data = new Dictionary<string, object>
            {
                { "documentId", documentId ?? "" },
                { "filename", filename ?? "" },
                { "rawText", (rawText ?? "").Length > 50000 ? (rawText ?? "").Substring(0, 50000) + "…" : (rawText ?? "") },
                { "timestamp", Timestamp.FromDateTime(DateTime.UtcNow) },
                { "userId", userId ?? "" }
            };
            if (garbageRatioPercent.HasValue) data["garbageRatioPercent"] = garbageRatioPercent.Value;
            if (!string.IsNullOrWhiteSpace(reasonForUpload)) data["reasonForUpload"] = reasonForUpload.Trim();
            var docRef = await col.AddAsync(data);
            _logger.LogInformation("[ScanFailure] Reported: docId={DocId}, filename={Fn}", documentId, filename);
            return docRef.Id;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "AddScanFailure failed: {Message}", ex.Message);
            return null;
        }
    }

    /// <summary>מחזיר כשלון לפי documentId.</summary>
    public async Task<ScanFailure?> GetScanFailureByDocumentIdAsync(string documentId)
    {
        try
        {
            var snapshot = await _db.Collection(ColScanFailures)
                .WhereEqualTo("documentId", documentId)
                .OrderByDescending("timestamp")
                .Limit(1)
                .GetSnapshotAsync();
            var doc = snapshot.Documents.FirstOrDefault();
            return doc != null ? MapDocToScanFailure(doc.Id, doc.ToDictionary()) : null;
        }
        catch { return null; }
    }

    private static ScanFailure? MapDocToScanFailure(string id, IReadOnlyDictionary<string, object> data)
    {
        try
        {
            DateTime dt = DateTime.UtcNow;
            if (data.TryGetValue("timestamp", out var ts) && ts is Timestamp t)
                dt = t.ToDateTime().ToUniversalTime();
            return new ScanFailure
            {
                Id = id,
                DocumentId = data.TryGetValue("documentId", out var di) ? (di?.ToString() ?? "") : "",
                Filename = data.TryGetValue("filename", out var fn) ? (fn?.ToString() ?? "") : "",
                RawText = data.TryGetValue("rawText", out var rt) ? (rt?.ToString() ?? "") : "",
                GarbageRatioPercent = data.TryGetValue("garbageRatioPercent", out var gr) && gr is double d ? d : null,
                UserId = data.TryGetValue("userId", out var uid) ? uid?.ToString() : null,
                Timestamp = dt,
                ReasonForUpload = data.TryGetValue("reasonForUpload", out var rfu) ? rfu?.ToString() : null
            };
        }
        catch { return null; }
    }
}
