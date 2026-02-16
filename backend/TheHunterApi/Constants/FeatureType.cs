namespace TheHunterApi.Constants;

/// <summary>סוגי תכונות AI — Document Analysis, Document Trainer, Smart Search, OCR Extraction.</summary>
public enum FeatureType
{
    /// <summary>מסווג מסמכים — קטגוריה, תגיות, תאריך. MAP: analysis → doc_analysis_default.txt</summary>
    DocumentAnalysis,

    /// <summary>מנוע למידה — suggested_keywords, suggested_regex. MAP: trainer → doc_analysis_learning.txt</summary>
    DocumentTrainer,

    /// <summary>מרחיב שאילתות חיפוש — terms, fileTypes, dateRange. MAP: search → smart_search.txt</summary>
    SmartSearch,

    /// <summary>חילוץ טקסט מתמונה/PDF — החזרת טקסט גולמי בלבד.</summary>
    OcrExtraction
}
