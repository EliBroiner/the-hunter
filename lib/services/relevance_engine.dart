import 'package:flutter/foundation.dart';
import '../configs/ranking_config.dart';
import '../models/file_metadata.dart';
import '../utils/smart_search_parser.dart';

/// מנוע רלוונטיות — מיון אחיד לתוצאות מקומיות, Drive ו-AI; משקלים נלקחים מ־RankingConfig
class RelevanceEngine {
  RelevanceEngine._();

  static const double _synonymFactor = 0.7;
  static const int _aiMetadataBonus = 80;
  /// בונוס ל-Drive: אין תוכן מחולץ — התאמות בשם קובץ שוקלות יותר כדי לאזן מול מקומי
  static const double _driveMetadataBonus = 55.0;
  /// בונוס סמיכות: זוגות מונחי שאילתה שמופיעים consecutively בתוכן (מקסימום 4 זוגות = 100 נקודות)
  static const double _adjacentPairBonus = 25.0;
  static const int _adjacentPairCap = 4;
  static const double _multiWordSeverePenalty = 0.2;
  static const double _multiWordFullBonusAdd = 50.0;
  /// קנס לשם מערכת/קריפטי — ציון נייטרלי לשפה
  static const double _crypticNamePenalty = -35.0;
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

  /// התאמת מילה שלמה בתוכן — גבולות: לא אות/ספרה (עברית/אנגלית) לפני ואחרי
  static bool _wholeWordInContent(String contentWithSpaces, String term) {
    final t = _norm(term);
    if (t.isEmpty || contentWithSpaces.isEmpty) return false;
    final escaped = RegExp.escape(t);
    // [^\w] = לא אות/ספרה; unicode: true כדי ש־\w יכלול עברית
    final boundary = RegExp('(^|[^\\w])' + escaped + r'([^\w]|$)', unicode: true);
    return boundary.hasMatch(contentWithSpaces);
  }

  /// נתיב התיקייה (ללא שם הקובץ) — לחישוב locationText
  static String _locationText(FileMetadata file) {
    final p = file.path;
    final i = p.lastIndexOf(RegExp(r'[/\\]'));
    if (i <= 0) return '';
    return p.substring(0, i);
  }

  /// סופר כמה זוגות סמוכים (מונח-מונח) מהשאילתה מופיעים consecutively בתוכן — כל זוג נספר פעם אחת
  static int _countUniqueAdjacentPairs(List<String> rawTerms, String contentWithSpaces) {
    if (contentWithSpaces.isEmpty) return 0;
    final terms = rawTerms.map((t) => _norm(t)).where((s) => s.isNotEmpty).toList();
    if (terms.length < 2) return 0;
    final queryPairs = <String>{};
    for (var i = 0; i < terms.length - 1; i++) {
      queryPairs.add('${terms[i]} ${terms[i + 1]}');
    }
    final words = contentWithSpaces
        .split(RegExp(r'\s+'))
        .map((s) => _norm(s))
        .where((s) => s.isNotEmpty)
        .toList();
    if (words.length < 2) return 0;
    final foundPairs = <String>{};
    for (var i = 0; i < words.length - 1; i++) {
      final pair = '${words[i]} ${words[i + 1]}';
      if (queryPairs.contains(pair)) foundPairs.add(pair);
    }
    return foundPairs.length;
  }

  /// מחשב ציון + פירוט: filename, location, תוכן
  /// משקלים דינמיים: RankingConfig מתעדכן מ-syncDictionaryWithServer (rankingConfig מהשרת)
  static (double, String) _scoreWithBreakdown(FileMetadata file, List<String> rawTerms,
      List<String> synonymTerms, String fnLower, String locLower, String extLower,
      String extRaw, String exactPhrase) {
    final config = RankingConfig.instance;
    final ptsFilename = config.filenameWeight;
    final ptsLocation = config.pathWeight;
    final maxContentScore = config.contentWeight;
    final exactPhraseBonus = config.exactPhraseBonus;
    final multiWordFullBonus = config.fullMatchMultiplier;

    final rawSet = rawTerms.map((t) => _norm(t)).toSet();
    final termsFound = <String>{};
    final contentTermsFound = <String>{};
    double score = 0;
    double namePts = 0, locPts = 0;

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
        namePts += ptsFilename * pts * factor;
      }
      if (_termMatches(locLower, term)) {
        termsFound.add(t);
        final factor = densityFactor(t, locLower.length);
        locPts += ptsLocation * pts * factor;
      }
      // תוכן: סופרים רק מונחי שאילתה (raw) שמופיעים — ציון לפי Query Coverage Ratio
      final inContent = extRaw.isNotEmpty && (_wholeWordInContent(extRaw, term) || extLower.contains(t));
      if (inContent) {
        termsFound.add(t);
        if (isRaw) contentTermsFound.add(t);
      }
    }

    for (final term in rawTerms) {
      addPts(term, true);
    }
    for (final term in synonymTerms) {
      if (rawSet.contains(_norm(term))) continue;
      addPts(term, false);
    }

    final queryWordCount = rawTerms.isEmpty ? 0 : rawTerms.length;
    final weightPerWord = queryWordCount > 0 ? maxContentScore / queryWordCount : 0.0;
    final contentScore = contentTermsFound.length * weightPerWord;
    score = namePts + locPts + contentScore;

    // בונוס סמיכות — מונחים שמופיעים consecutively בתוכן (כל זוג ייחודי נספר פעם אחת)
    final adjacencyCount = _countUniqueAdjacentPairs(rawTerms, extRaw);
    score += (adjacencyCount > _adjacentPairCap ? _adjacentPairCap : adjacencyCount) * _adjacentPairBonus;

    // Drive: בונוס מטאדאטה — התאמות בשם קובץ שוקלות יותר (אין OCR)
    if (file.isCloud && namePts > 0) {
      score += _driveMetadataBonus;
    }

    // עדיפות שפה: בונוס לשם עברי נקי, קנס לשם מערכת (GUID, pdf.123)
    final baseName = fnLower.contains('.') ? fnLower.substring(0, fnLower.lastIndexOf('.')) : fnLower;
    if (baseName.length >= 20 && _guidLikeName.hasMatch(baseName)) {
      score += _crypticNamePenalty;
    } else if (_pdfDotNumbers.hasMatch(fnLower)) {
      score += _crypticNamePenalty;
    }

    // Exact phrase bonus — התאמה מדויקת (לאחר נרמול רווחים/שורות)
    if (exactPhrase.length >= 2) {
      final phraseNorm = _normalize(exactPhrase);
      final fnNorm = _normalize(fnLower);
      final extNorm = _normalize(extLower);
      if (fnNorm.contains(phraseNorm) || extNorm.contains(phraseNorm)) {
        score += exactPhraseBonus;
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
        score = (score * multiWordFullBonus) + _multiWordFullBonusAdd;
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
    if (contentScore != 0) parts.add('Content(${_fmtScore(contentScore)})');
    if (adjacencyCount > 0) parts.add('Adj($adjacencyCount)');
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
        parts.add('Exact+$exactPhraseBonus');
      }
    }
    if (baseName.length >= 20 && _guidLikeName.hasMatch(baseName)) {
      parts.add('Cryptic($_crypticNamePenalty)');
    } else if (_pdfDotNumbers.hasMatch(fnLower)) {
      parts.add('Cryptic($_crypticNamePenalty)');
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
    if (file.isCloud && namePts > 0) parts.add('Drive+$_driveMetadataBonus');

    final breakdown = parts.isEmpty ? 'No match' : parts.join(' + ');
    return (score, breakdown);
  }

  /// נרמול למונח: trim + lowercase — ללא הסרת ספרות (תמיכה ב־"185", "2024", "106")
  static String _norm(String s) => s.trim().toLowerCase();

  /// פורמט ציון לדיבוג — מספר שלם או עשרוני אחד
  static String _fmtScore(double d) =>
      d == d.roundToDouble() ? d.toInt().toString() : d.toStringAsFixed(1);

  /// נרמול לטקסט מ־PDF: הסרת ניקוד, רווחים מרובים, תווים לא־אלפאנומריים ("ק ב ל ה" → "קבלה").
  /// Regex: [^a-z0-9\u0590-\u05FF] — ספרות 0–9 נשמרות (חיפוש מספרים נתמך).
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
      final extRaw = ext.trim().toLowerCase();
      final fnLower = _norm(fn);
      final locLower = _norm(loc);
      final extLower = _norm(ext);
      final (score, breakdown) = _scoreWithBreakdown(
          file, intent.rawTerms, synonymTerms, fnLower, locLower, extLower, extRaw, exactPhrase);
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
