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

    /// <summary>doc_analysis_default.txt — V2 Hierarchy of Attention. MAP TO: FeatureType.DocumentAnalysis (הסורק הראשי).</summary>
    public static string DocumentAnalysis => ReadPromptFile("doc_analysis_default.txt") is { Length: > 0 } t ? t : DocumentAnalysisEmbedded;

    /// <summary>doc_analysis_learning.txt — Expert Document Architect + Learning Task. MAP TO: FeatureType.DocumentTrainer (מנוע הלמידה).</summary>
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
        # Document Analysis Prompt (V2) — Output ONLY raw JSON

        Role: You are an expert document classifier. Your goal is to identify the PRIMARY PURPOSE of the document based on its hierarchy, ignoring legal fine print.

        === CRITICAL LOGIC: HIERARCHY OF ATTENTION ===
        1.  **HEADER AUTHORITY (Top 20%):** The title, logo, and largest text define the category.
            * *Example:* If the top says "Boarding Pass" or "כרטיס עלייה למטוס", it is [Travel], even if the footer mentions "payment fees".
        2.  **FINE PRINT IMMUNITY (Bottom 20%):** Ignore keywords like "payment", "fee", "tax", "terms", or "charge" if they appear in the footer or small legal text.
            * *Rule:* A mention of money does NOT automatically make it a Receipt.
        3.  **SPECIFIC VS GENERIC:**
            * "Boarding Pass" > "Receipt" (Priority: High)
            * "Bank Statement" > "Transfer" (Priority: High)
            * "Form 106" > "Tax" (Priority: High)

        === REQUIRED JSON STRUCTURE ===
        {
          "category": "string (Format: 'English / Hebrew')",
          "date": "YYYY-MM-DD or null",
          "tags": ["tag1", "tag2"],
          "summary": "string (Format: 'English / Hebrew')",
          "metadata": {
            "names": ["string"],
            "ids": ["string"],
            "locations": ["string"]
          },
          "requires_high_res_ocr": boolean
        }

        === MULTILINGUAL OUTPUT (MANDATORY) ===
        Provide "category", "tags", and "summary" in "English / Hebrew" format.
        - Category Examples: "Flight Ticket / כרטיס טיסה", "Invoice / חשבונית", "Medical Referral / הפניה רפואית".
        - Tag Examples: "Travel / נסיעות", "Financial / פיננסי", "Government / ממשלתי".

        === STRICT RULE: NO PII IN TAGS ===
        - **Tags**: Must be GENERAL categories only (e.g., Receipt, Medical, Contract).
        - **Metadata**: Place specific names (John Doe), IDs (3456789), and locations (Tel Aviv) ONLY in the "metadata" object.
        - **NEVER** put a person's name or ID in the "tags" array.

        === REQUIRES_HIGH_RES_OCR LOGIC ===
        Set to `true` ONLY if:
        1. The text is fragmented, garbled, or contains mostly random characters.
        2. It looks like a complex handwriting or table that was not parsed correctly.
        Otherwise, set to `false`.

        === FEW-SHOT EXAMPLES (LOGIC DEMONSTRATION) ===

        Input: "EL AL Boarding Pass. Passenger: Cohen. Seat 4A. Footer: Excess baggage fee payment of $50 collected."
        Output: {
          "category": "Boarding Pass / כרטיס עלייה למטוס",
          "date": null,
          "tags": ["Travel / נסיעות", "Flight / טיסה"],
          "summary": "El Al Boarding Pass for Cohen / כרטיס עלייה למטוס של אל על עבור כהן",
          "metadata": {"names": ["Cohen"], "ids": [], "locations": []},
          "requires_high_res_ocr": false
        }

        Input: "קבלה עבור תשלום חשמל. סך הכל: 400 שח."
        Output: {
          "category": "Utility Bill / חשבון שירות",
          "date": null,
          "tags": ["Financial / פיננסי", "Electricity / חשמל", "Receipt / קבלה"],
          "summary": "Electricity payment receipt / קבלה על תשלום חשמל",
          "metadata": {"names": [], "ids": [], "locations": []},
          "requires_high_res_ocr": false
        }

        === OUTPUT ===
        Return ONLY raw JSON. No markdown, no code blocks.
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
