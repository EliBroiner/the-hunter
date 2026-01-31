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
  static const double _coverageMultiplier = 1.5;
  static const int _exactPhraseBonus = 150;

  /// נתיב התיקייה (ללא שם הקובץ) — לחישוב locationText
  static String _locationText(FileMetadata file) {
    final p = file.path;
    final i = p.lastIndexOf(RegExp(r'[/\\]'));
    if (i <= 0) return '';
    return p.substring(0, i);
  }

  /// מחשב ציון + פירוט: התאמות ב־filename / location / extracted; rawTerms מלא, synonyms 70%
  /// כולל Density Penalty ו־Exact Phrase Bonus
  static (double, String) _scoreWithBreakdown(FileMetadata file, List<String> rawTerms,
      List<String> synonymTerms, String fnLower, String locLower, String extLower,
      String exactPhrase) {
    final rawSet = rawTerms.map((t) => _norm(t)).toSet();
    double score = 0;
    double namePts = 0, locPts = 0, extPts = 0;

    /// Density penalty: score *= (termLength / foundTokenLength)
    double _densityFactor(String term, int foundTokenLen) {
      if (foundTokenLen <= 0) return 1.0;
      final factor = term.length / foundTokenLen;
      return factor > 1.0 ? 1.0 : factor;
    }

    void addPts(String term, bool isRaw) {
      final t = _norm(term);
      if (t.isEmpty) return;
      final pts = isRaw ? 1.0 : _synonymFactor;
      if (fnLower.contains(t)) {
        final factor = _densityFactor(t, fnLower.length);
        namePts += _ptsFilename * pts * factor;
      }
      if (locLower.contains(t)) {
        final factor = _densityFactor(t, locLower.length);
        locPts += _ptsLocation * pts * factor;
      }
      if (extLower.contains(t)) {
        final factor = _densityFactor(t, extLower.length);
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

    // Exact phrase bonus — התאמה מדויקת לשאילתה
    if (exactPhrase.length >= 2) {
      final phraseLower = _norm(exactPhrase);
      if (fnLower.contains(phraseLower) || extLower.contains(phraseLower)) {
        score += _exactPhraseBonus;
      }
    }

    final parts = <String>[];
    if (namePts > 0) parts.add('Name(${namePts.toInt()})');
    if (locPts > 0) parts.add('Loc(${locPts.toInt()})');
    if (extPts > 0) parts.add('Ext(${extPts.toInt()})');

    if (rawTerms.isNotEmpty) {
      final hasAllRaw = rawTerms.every((t) {
        final n = _norm(t);
        return n.isNotEmpty && (fnLower.contains(n) || locLower.contains(n) || extLower.contains(n));
      });
      if (hasAllRaw) {
        score *= _coverageMultiplier;
        parts.add('Coverage×$_coverageMultiplier');
      }
    }
    if (exactPhrase.length >= 2) {
      final phraseLower = _norm(exactPhrase);
      if (fnLower.contains(phraseLower) || extLower.contains(phraseLower)) {
        parts.add('Exact+$_exactPhraseBonus');
      }
    }

    final breakdown = parts.isEmpty ? 'No match' : parts.join(' + ');
    return (score, breakdown);
  }

  static String _norm(String s) => s.trim().toLowerCase();

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
