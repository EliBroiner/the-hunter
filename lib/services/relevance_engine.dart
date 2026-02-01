import 'package:flutter/foundation.dart';
import '../models/file_metadata.dart';
import '../utils/smart_search_parser.dart';

/// מנוע רלוונטיות — מיון אחיד לתוצאות מקומיות, Drive ו-AI
class RelevanceEngine {
  RelevanceEngine._();

  static const int _ptsFilename = 100;
  static const int _ptsLocation = 80;
  static const int _ptsExtracted = 20;
  static const double _synonymFactor = 0.7;
  static const int _exactPhraseBonus = 150;
  static const int _aiMetadataBonus = 80;
  static const double _multiWordSeverePenalty = 0.2;
  static const double _multiWordFullBonus = 1.2;
  static const double _multiWordFullBonusAdd = 50.0;
  /// בונוס לשם קובץ עברי נקי; קנס לשם מערכת/קריפטי
  static const double _hebrewNameBonus = 45.0;
  static const double _crypticNamePenalty = -35.0;
  static final RegExp _hebrewChars = RegExp(r'[\u0590-\u05FF]');
  static final RegExp _guidLikeName = RegExp(r'^[a-fA-F0-9\-]{20,}$');
  static final RegExp _pdfDotNumbers = RegExp(r'^pdf\.\d+', caseSensitive: false);

  static bool _isAllDigits(String s) =>
      s.isNotEmpty && s.split('').every((c) => c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39);

  /// התאמת מונח — אחרי נרמול (ניקוד, רווחים, לא־אלפאנומרי); מספרים: גבולות regex
  static bool _termMatches(String text, String term) {
    final textNorm = _normalize(text);
    final t = _normalize(term);
    if (t.isEmpty) return false;
    if (_isAllDigits(t)) {
      final pattern = '(^|\\D)' + RegExp.escape(t) + r'(\D|$)';
      return RegExp(pattern).hasMatch(textNorm);
    }
    return textNorm.contains(t);
  }

  /// נתיב התיקייה (ללא שם הקובץ) — לחישוב locationText
  static String _locationText(FileMetadata file) {
    final p = file.path;
    final i = p.lastIndexOf(RegExp(r'[/\\]'));
    if (i <= 0) return '';
    return p.substring(0, i);
  }

  /// מחשב ציון + פירוט: התאמות ב־filename / location / extracted; rawTerms מלא, synonyms 70%
  /// כולל Density Penalty, Exact Phrase Bonus, Strict Number, Multi-Word Penalty, AI Metadata
  static (double, String) _scoreWithBreakdown(FileMetadata file, List<String> rawTerms,
      List<String> synonymTerms, String fnLower, String locLower, String extLower,
      String exactPhrase) {
    final rawSet = rawTerms.map((t) => _norm(t)).toSet();
    final termsFound = <String>{};
    double score = 0;
    double namePts = 0, locPts = 0, extPts = 0;

    double densityFactor(String term, int foundTokenLen) {
      if (foundTokenLen <= 0) return 1.0;
      final factor = term.length / foundTokenLen;
      return factor > 1.0 ? 1.0 : factor;
    }

    void addPts(String term, bool isRaw) {
      final t = _norm(term);
      if (t.isEmpty) return;
      final pts = isRaw ? 1.0 : _synonymFactor;
      if (_termMatches(fnLower, term)) {
        termsFound.add(t);
        final factor = densityFactor(t, fnLower.length);
        namePts += _ptsFilename * pts * factor;
      }
      if (_termMatches(locLower, term)) {
        termsFound.add(t);
        final factor = densityFactor(t, locLower.length);
        locPts += _ptsLocation * pts * factor;
      }
      if (_termMatches(extLower, term)) {
        termsFound.add(t);
        final factor = densityFactor(t, extLower.length);
        extPts += _ptsExtracted * pts * factor;
      }
    }

    for (final term in rawTerms) {
      addPts(term, true);
    }
    for (final term in synonymTerms) {
      if (rawSet.contains(_norm(term))) continue;
      addPts(term, false);
    }

    score = namePts + locPts + extPts;

    // עדיפות שפה: בונוס לשם עברי נקי, קנס לשם מערכת (GUID, pdf.123)
    final baseName = fnLower.contains('.') ? fnLower.substring(0, fnLower.lastIndexOf('.')) : fnLower;
    if (baseName.length >= 20 && _guidLikeName.hasMatch(baseName)) {
      score += _crypticNamePenalty;
    } else if (_pdfDotNumbers.hasMatch(fnLower)) {
      score += _crypticNamePenalty;
    } else if (_hebrewChars.hasMatch(file.name) && baseName.length >= 2) {
      score += _hebrewNameBonus;
    }

    // Exact phrase bonus — התאמה מדויקת (לאחר נרמול רווחים/שורות)
    if (exactPhrase.length >= 2) {
      final phraseNorm = _normalize(exactPhrase);
      final fnNorm = _normalize(fnLower);
      final extNorm = _normalize(extLower);
      if (fnNorm.contains(phraseNorm) || extNorm.contains(phraseNorm)) {
        score += _exactPhraseBonus;
      }
    }

    // Multi-Word — קנס על התאמה חלקית; בונוס + מכפיל על התאמה מלאה
    final totalQueryTerms = rawTerms.length;
    if (totalQueryTerms > 0) {
      final rawNormSet = rawTerms.map((t) => _norm(t)).toSet();
      final termsFoundCount = rawNormSet.intersection(termsFound).length;
      final matchRatio = termsFoundCount / totalQueryTerms;
      if (matchRatio < 0.5) {
        score *= _multiWordSeverePenalty;
      } else if (matchRatio >= 1.0) {
        score = (score * _multiWordFullBonus) + _multiWordFullBonusAdd;
      }
    }

    // AI Metadata — התאמה ל־category או tags
    final cat = file.category?.toLowerCase();
    final aiTags = file.tags?.map((t) => t.toLowerCase()).toList();
    if (cat != null || (aiTags != null && aiTags.isNotEmpty)) {
      for (final term in rawTerms) {
        final t = _norm(term);
        if (t.isEmpty) continue;
        if (cat != null && (cat == t || cat.contains(t))) {
          score += _aiMetadataBonus;
          break;
        }
        if (aiTags != null && aiTags.any((tag) => tag == t || tag.contains(t))) {
          score += _aiMetadataBonus;
          break;
        }
      }
    }

    final parts = <String>[];
    if (namePts != 0) parts.add('Fn(${_fmtScore(namePts)})');
    if (locPts != 0) parts.add('Loc(${_fmtScore(locPts)})');
    if (extPts != 0) parts.add('Ext(${_fmtScore(extPts)})');
    if (rawTerms.isNotEmpty) {
      final rawNormSet = rawTerms.map((t) => _norm(t)).toSet();
      final termsFoundCount = rawNormSet.intersection(termsFound).length;
      final matchRatio = termsFoundCount / rawTerms.length;
      if (matchRatio < 0.5) {
        parts.add('MultiWord×$_multiWordSeverePenalty');
      } else if (matchRatio >= 1.0) {
        parts.add('MultiWord(x1.2+50)');
      }
    }
    if (exactPhrase.length >= 2) {
      final phraseNorm = _normalize(exactPhrase);
      final fnNorm = _normalize(fnLower);
      final extNorm = _normalize(extLower);
      if (fnNorm.contains(phraseNorm) || extNorm.contains(phraseNorm)) {
        parts.add('Exact+$_exactPhraseBonus');
      }
    }
    if (baseName.length >= 20 && _guidLikeName.hasMatch(baseName)) {
      parts.add('Cryptic($_crypticNamePenalty)');
    } else if (_pdfDotNumbers.hasMatch(fnLower)) {
      parts.add('Cryptic($_crypticNamePenalty)');
    } else if (_hebrewChars.hasMatch(file.name) && baseName.length >= 2) {
      parts.add('Hebrew+$_hebrewNameBonus');
    }
    if (cat != null || (aiTags != null && aiTags.isNotEmpty)) {
      var aiMatch = false;
      for (final term in rawTerms) {
        final t = _norm(term);
        if (t.isEmpty) continue;
        if (cat != null && (cat == t || cat.contains(t))) { aiMatch = true; break; }
        if (aiTags != null && aiTags.any((tag) => tag == t || tag.contains(t))) { aiMatch = true; break; }
      }
      if (aiMatch) parts.add('AI($_aiMetadataBonus)');
    }

    final breakdown = parts.isEmpty ? 'No match' : parts.join(' + ');
    return (score, breakdown);
  }

  static String _norm(String s) => s.trim().toLowerCase();

  /// פורמט ציון לדיבוג — מספר שלם או עשרוני אחד
  static String _fmtScore(double d) =>
      d == d.roundToDouble() ? d.toInt().toString() : d.toStringAsFixed(1);

  /// נרמול לטקסט מ־PDF: הסרת ניקוד, רווחים מרובים, תווים לא־אלפאנומריים ("ק ב ל ה" → "קבלה")
  static String _normalize(String input) {
    var s = input.trim().toLowerCase();
    // הסרת ניקוד עברי (U+0591–U+05BD, U+05BF–U+05C2, U+05C4–U+05C7)
    s = s.replaceAll(RegExp(r'[\u0591-\u05BD\u05BF-\u05C2\u05C4-\u05C7]'), '');
    s = s.replaceAll(RegExp(r'\s+'), '');
    // שמירה רק על אותיות (כולל עברית) וספרות — טיפול ב־"H e b r e w" / "ק.ב.ל.ה"
    return s.replaceAll(RegExp(r'[^a-z0-9\u0590-\u05FF]'), '');
  }

  /// מדרג ומיין קבצים לפי ציון רלוונטיות; ממלא debugScore/debugScoreBreakdown; לוג Top 5
  static List<FileMetadata> rankAndSort(List<FileMetadata> files, SearchIntent intent) {
    if (files.isEmpty) return files;
    if (intent.rawTerms.isEmpty && intent.terms.isEmpty) {
      for (final f in files) {
        f.debugScore = null;
        f.debugScoreBreakdown = null;
      }
      files.sort((a, b) => b.lastModified.compareTo(a.lastModified));
      return files;
    }

    final rawSet = intent.rawTerms.map((t) => _norm(t)).toSet();
    final synonymTerms = intent.terms.where((t) => !rawSet.contains(_norm(t))).toList();

    final exactPhrase = intent.rawTerms.join(' ');
    final scored = files.map((file) {
      final fn = file.name;
      final loc = _locationText(file);
      final ext = file.extractedText ?? '';
      final fnLower = _norm(fn);
      final locLower = _norm(loc);
      final extLower = _norm(ext);
      final (score, breakdown) = _scoreWithBreakdown(
          file, intent.rawTerms, synonymTerms, fnLower, locLower, extLower, exactPhrase);
      file.debugScore = score;
      file.debugScoreBreakdown = breakdown;
      return _ScoredFile(file, score);
    }).toList();

    scored.sort((a, b) {
      final cmp = b.score.compareTo(a.score);
      if (cmp != 0) return cmp;
      return b.file.lastModified.compareTo(a.file.lastModified);
    });

    // לוג Top 5
    final top5 = scored.take(5).toList();
    for (var i = 0; i < top5.length; i++) {
      final e = top5[i];
      debugPrint(
          '🏆 Rank #${i + 1}: ${e.file.name} - Score: ${e.score.toStringAsFixed(1)} (${e.file.debugScoreBreakdown ?? ""})');
    }

    return scored.map((e) => e.file).toList();
  }
}

class _ScoredFile {
  final FileMetadata file;
  final double score;
  _ScoredFile(this.file, this.score);
}
