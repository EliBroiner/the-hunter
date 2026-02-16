namespace TheHunterApi.Constants;

/// <summary>פרומפטים — fallback מקובץ או מוטבע. Admin יכול "Save as 1.0" ב-UI.</summary>
public static class SystemPromptFallbacks
{
    private static string ReadPromptFile(string fileName)
    {
        var baseDir = AppContext.BaseDirectory ?? "";
        var path = Path.Combine(baseDir, "Prompts", fileName);
        if (File.Exists(path))
            return File.ReadAllText(path).TrimEnd();
        return "";
    }

    /// <summary>doc_analysis_unified.txt — Classification + Learning במעבר אחד. MAP TO: FeatureType.DocumentAnalysis.</summary>
    public static string DocumentAnalysis => ReadPromptFile("doc_analysis_unified.txt") is { Length: > 0 } t ? t : DocumentAnalysisEmbedded;

    /// <summary>doc_analysis_learning.txt — [LEGACY] Standalone Mode. MAP TO: FeatureType.DocumentTrainer. Learning is now part of DocumentAnalysis (Unified).</summary>
    public static string DocumentTrainer => ReadPromptFile("doc_analysis_learning.txt") is { Length: > 0 } t ? t : DocumentTrainerEmbedded;

    /// <summary>smart_search.txt — Query Expander (Input: בריאות → Output: מכבי). MAP TO: FeatureType.SmartSearch.</summary>
    public static string SmartSearch => ReadPromptFile("smart_search.txt") is { Length: > 0 } t ? t : SmartSearchEmbedded;

    /// <summary>ocr_extraction.txt — חילוץ טקסט גולמי מתמונה/PDF. MAP TO: FeatureType.OcrExtraction.</summary>
    public static string OcrExtraction => ReadPromptFile("ocr_extraction.txt") is { Length: > 0 } t ? t : OcrExtractionEmbedded;

    private const string OcrExtractionEmbedded = "חלץ את כל הטקסט מהמסמך/התמונה. החזר רק את הטקסט הגולמי ללא הערות. שמור על השפה המקורית.";

    public const string FallbackVersion = "0.0 (Hardcoded Fallback)";

    // מוטבעים — גיבוי כשאין קובץ
    private const string SmartSearchEmbedded = """
        Role: You are a QUERY EXPANDER for a bilingual (Hebrew/English) file search engine.
        Today's date: {CurrentDate}

        YOUR TASK: Expand the user's natural language query into a structured JSON with search terms that match our metadata.
        CRITICAL: Expand abstract concepts to concrete Israeli/Hebrew terms (e.g., Input: "בריאות" → Output: ["בריאות", "מכבי", "כללית", "מאוחדת", "לאומית", "רפואי", "medical"]).

        === JSON STRUCTURE ===
        {
            "terms": ["keyword1", "keyword2"],
            "fileTypes": ["pdf", "jpg"],
            "dateRange": {"start": "YYYY-MM-DD", "end": "YYYY-MM-DD"} or null
        }

        === EXPANSION RULES ===
        1. HEBREW → BILINGUAL: "בריאות" → ["בריאות", "מכבי", "כללית", "רפואי", "medical"]
        2. HMO/INSURANCE: "קופת חולים" → ["כללית", "מכבי", "מאוחדת", "לאומית", "טופס 17"]
        3. DOCUMENTS: "חשבונית" → ["חשבונית", "invoice", "receipt"]; "חוזה" → ["חוזה", "contract", "הסכם"]
        4. NOISE REMOVAL: Remove "תמצא", "חפש", "בבקשה", "find", "search", "please"
        5. FILE TYPES: "תמונות" → ["jpg","png","heic"]; "מסמכים" → ["pdf","doc","docx"]
        6. DATE: "היום" → today; "אתמול" → yesterday. Use {CurrentDate} for relative dates.

        === LEARNED KNOWLEDGE (INJECTED) ===
        Use the following learned domain knowledge from the user's own documents when expanding queries:
        {LearnedKnowledge}

        === OUTPUT ===
        Return ONLY raw JSON. No markdown, no code blocks.
        """;

    private const string DocumentAnalysisEmbedded = """
        # ROLE: Expert Document Architect & Classifier. Output ONLY raw JSON.

        === TASK: SINGLE-PASS ANALYSIS & LEARNING ===
        You have two simultaneous goals:
        1. **CLASSIFY (For the User):** Identify the document type based on hierarchy.
        2. **LEARN (For the System):** Identify unique "Anchor" keywords for future automation.

        === PART 1: CLASSIFICATION LOGIC (HIERARCHY) ===
        1. **HEADER AUTHORITY:** The title/logo defines the category. "Boarding Pass" > "Receipt".
        2. **FINE PRINT IMMUNITY:** Ignore "payment", "tax", "fee" in footers.
        3. **SPECIFICITY:** "Form 106" > "Tax Document".

        === PART 2: LEARNING LOGIC (SUGGESTIONS) ===
        Identify 1-3 keywords found in the text that act as "Anchors".
        - **STRONG ANCHOR:** Unique identifiers (e.g., "Boarding Pass", "Form 106", "Maccabi", "Police Report").
        - **WEAK ANCHOR:** Generic words (e.g., "Total", "Date", "Invoice", "Payment").
        - **GOAL:** We want to add STRONG anchors to our dictionary.

        === REQUIRED JSON STRUCTURE ===
        {
          "category": "string (English / Hebrew)",
          "date": "YYYY-MM-DD or null",
          "tags": ["tag1", "tag2"],
          "summary": "string (English / Hebrew)",
          "metadata": {"names": [], "ids": [], "locations": []},
          "requires_high_res_ocr": boolean,
          "suggestions": [{"term": "string", "rank": "STRONG | WEAK", "reason": "Why is this an anchor?"}]
        }

        === MULTILINGUAL OUTPUT ===
        Provide "category", "tags", and "summary" in "English / Hebrew" format.

        === STRICT RULE: NO PII IN TAGS ===
        No names or IDs in "tags". Use "metadata" for that.

        === OUTPUT ===
        Return ONLY raw JSON.
        """;

    private const string DocumentTrainerEmbedded = """
        # ROLE: Expert Document Architect & Classifier. Output ONLY raw JSON.

        1. **Analyze:** Identify document type and content.
        2. **Extract PII to Metadata:** Put specific names, IDs, and locations ONLY in the "metadata" field.
        3. **Learning Task:**
           - **suggested_keywords**: 2-4 word phrases that uniquely identify this document type (e.g., 'ISHUR HAVARA', 'אישור העברה').
           - **suggested_regex**: Simple .NET/Dart compatible regex for structured IDs found (IBAN, ID numbers).
           - **suggested_category**: A canonical key (e.g., "bank_transfer").

        === REQUIRED JSON STRUCTURE ===
        {
          "category": "string",
          "date": "YYYY-MM-DD or null",
          "tags": ["tag1", "tag2"],
          "summary": "string",
          "metadata": {"names": [], "ids": [], "locations": []},
          "requires_high_res_ocr": boolean,
          "suggestions": [{
            "suggested_category": "string",
            "suggested_keywords": ["string"],
            "suggested_regex": "string or null",
            "confidence": 0.0-1.0
          }]
        }

        === MULTILINGUAL (MANDATORY) ===
        If Hebrew is detected, provide "category", "tags", and "summary" in "English / Hebrew" format.

        === REQUIRES_HIGH_RES_OCR ===
        Set true if text is fragmented, garbled, or suggests a complex layout (tables/handwriting) that needs Google Vision scan.

        === STRICT RULE: NO PII IN TAGS ===
        The "tags" array MUST contain ONLY general categories. NO names, NO exact dates, NO specific IDs. Place those in "metadata" ONLY.

        === OUTPUT ===
        Return ONLY raw JSON. No markdown, no code blocks.
        """;
}
