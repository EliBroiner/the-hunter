namespace TheHunterApi.Config;

/// <summary>נתוני seed ל-smart_categories — תואם ל-assets/smart_search_config.json.</summary>
public static class SmartCategoriesSeedData
{
    public static IReadOnlyDictionary<string, string[]> GetRules() => new Dictionary<string, string[]>
    {
        ["general"] = ["document", "doc", "מסמך", "קובץ", "file", "scan", "סריקה", "copy", "העתק"],
        ["receipt"] = ["invoice", "receipt", "קבלה", "חשבונית", "bill", "inv", "payment", "transfer", "bit", "date", "paybox", "ביט", "פייבוקס"],
        ["id"] = ["id", "identity", "תעודת זהות", "ת.ז", "דרכון", "passport", "teudat zehut"],
        ["flight"] = ["boarding pass", "flight", "טיסה", "כרטיס טיסה"],
        ["salary"] = ["form 106", "106", "טופס 106", "משכורת", "תלוש", "payslip"],
        ["medical"] = ["סיכום ביקור", "הפניה", "טופס 17", "מכבי", "כללית", "אסותא"],
        ["car"] = ["license", "vehicle test", "compulsory insurance", "רישיון רכב", "מבחן רישוי", "טסט לרכב", "טסט", "ביטוח חובה", "רכב", "vehicle"],
        ["army"] = ["idf", "miluim", "מילואים", "3010", "צו גיוס", "שמ\"פ", "צבא", "army"],
        ["municipality"] = ["arnona", "ארנונה", "water bill", "חשבון מים", "עירייה", "עיריה"],
        ["transfer"] = ["reference", "asmachta", "אסמכתא", "confirmation", "אישור", "transfer", "העברה"],
        ["bank"] = ["check", "cheque", "צ'ק", "שיק", "המחאה"],
        ["employment"] = ["קורות חיים", "קו\"ח", "cv", "resume", "curriculum vitae"],
        ["government"] = ["רשות האכיפה", "גביית קנסות", "דוח תנועה", "משטרת ישראל", "קנס"],
        ["travel"] = ["boarding pass", "security check", "ben gurion", "tlv", "el al"],
        ["vehicle"] = ["רישיון רכב", "מבחן רישוי", "טסט לרכב"],
    };

    public static IReadOnlyDictionary<string, IReadOnlyDictionary<string, string>> GetStrongRanks() => new Dictionary<string, IReadOnlyDictionary<string, string>>
    {
        ["id"] = new Dictionary<string, string> { ["teudat zehut"] = "strong", ["תעודת זהות"] = "strong" },
        ["salary"] = new Dictionary<string, string> { ["form 106"] = "strong", ["טופס 106"] = "strong", ["106"] = "strong" },
        ["medical"] = new Dictionary<string, string> { ["סיכום ביקור"] = "strong", ["הפניה"] = "strong", ["טופס 17"] = "strong", ["מכבי"] = "strong", ["כללית"] = "strong", ["אסותא"] = "strong" },
        ["car"] = new Dictionary<string, string> { ["רישיון רכב"] = "strong", ["מבחן רישוי"] = "strong", ["טסט לרכב"] = "strong", ["license"] = "strong", ["vehicle test"] = "strong", ["compulsory insurance"] = "strong", ["טסט"] = "strong", ["ביטוח חובה"] = "strong" },
        ["vehicle"] = new Dictionary<string, string> { ["רישיון רכב"] = "strong", ["מבחן רישוי"] = "strong", ["טסט לרכב"] = "strong" },
        ["army"] = new Dictionary<string, string> { ["idf"] = "strong", ["miluim"] = "strong", ["מילואים"] = "strong", ["3010"] = "strong", ["צו גיוס"] = "strong", ["שמ\"פ"] = "strong" },
        ["municipality"] = new Dictionary<string, string> { ["arnona"] = "strong", ["ארנונה"] = "strong", ["water bill"] = "strong", ["חשבון מים"] = "strong" },
        ["employment"] = new Dictionary<string, string> { ["קורות חיים"] = "strong", ["קו\"ח"] = "strong", ["cv"] = "strong", ["resume"] = "strong", ["curriculum vitae"] = "strong" },
        ["government"] = new Dictionary<string, string> { ["רשות האכיפה"] = "strong", ["גביית קנסות"] = "strong", ["דוח תנועה"] = "strong", ["משטרת ישראל"] = "strong", ["קנס"] = "strong" },
        ["flight"] = new Dictionary<string, string> { ["boarding pass"] = "strong", ["flight"] = "strong" },
        ["travel"] = new Dictionary<string, string> { ["boarding pass"] = "strong", ["security check"] = "strong", ["ben gurion"] = "strong", ["tlv"] = "strong", ["el al"] = "strong" },
    };

    public static IReadOnlyDictionary<string, IReadOnlyDictionary<string, string>> GetWeakRanks() => new Dictionary<string, IReadOnlyDictionary<string, string>>
    {
        ["transfer"] = new Dictionary<string, string> { ["reference"] = "weak", ["asmachta"] = "weak", ["אסמכתא"] = "weak", ["confirmation"] = "weak", ["אישור"] = "weak", ["transfer"] = "weak", ["העברה"] = "weak" },
        ["receipt"] = new Dictionary<string, string> { ["payment"] = "weak", ["transfer"] = "weak", ["receipt"] = "weak", ["invoice"] = "weak", ["date"] = "weak", ["paybox"] = "weak", ["ביט"] = "weak", ["פייבוקס"] = "weak", ["העברה"] = "weak" },
        ["general"] = new Dictionary<string, string> { ["Document"] = "weak", ["document"] = "weak", ["doc"] = "weak", ["Scan"] = "weak", ["scan"] = "weak", ["File"] = "weak", ["file"] = "weak", ["copy"] = "weak", ["מסמך"] = "weak", ["קובץ"] = "weak", ["סריקה"] = "weak", ["העתק"] = "weak" },
    };
}
