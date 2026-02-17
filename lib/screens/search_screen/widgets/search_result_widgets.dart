import 'dart:io';
import 'package:flutter/material.dart';
import '../../../models/file_metadata.dart';
import '../../../services/tags_service.dart';
import '../search_helpers.dart';

/// תמונה ממוזערת או אייקון לפריט תוצאת חיפוש
class SearchFileThumbnail extends StatelessWidget {
  const SearchFileThumbnail({
    super.key,
    required this.file,
    required this.fileColor,
    required this.isWhatsApp,
  });

  final FileMetadata file;
  final Color fileColor;
  final bool isWhatsApp;

  static const _imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'];

  @override
  Widget build(BuildContext context) {
    final ext = file.extension.toLowerCase();
    const size = 52.0;
    const borderRadius = 12.0;

    if (_imageExtensions.contains(ext)) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          color: fileColor.withValues(alpha: 0.15),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.file(
          File(file.path),
          fit: BoxFit.cover,
          width: size,
          height: size,
          cacheWidth: 150,
          cacheHeight: 150,
          errorBuilder: (_, _, _) => Center(
            child: SearchFileIcon(extension: file.extension, isWhatsApp: isWhatsApp),
          ),
          frameBuilder: (_, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded) return child;
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: frame != null
                  ? child
                  : Container(
                      color: fileColor.withValues(alpha: 0.15),
                      child: Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: fileColor,
                          ),
                        ),
                      ),
                    ),
            );
          },
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fileColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Center(
        child: SearchFileIcon(extension: file.extension, isWhatsApp: isWhatsApp),
      ),
    );
  }
}

/// אייקון קובץ (WhatsApp = בועת צ'אט) — ניתן לשימוש חיצוני
class SearchFileIcon extends StatelessWidget {
  const SearchFileIcon({super.key, required this.extension, required this.isWhatsApp});

  final String extension;
  final bool isWhatsApp;

  @override
  Widget build(BuildContext context) {
    if (isWhatsApp) {
      return const Icon(Icons.chat_bubble, size: 22, color: Colors.green);
    }
    IconData icon;
    final color = getFileColor(extension);
    switch (extension.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
      case 'bmp':
      case 'heic':
      case 'heif':
        icon = Icons.image;
        break;
      case 'mp4':
      case 'mov':
      case 'avi':
      case 'mkv':
      case 'webm':
      case '3gp':
        icon = Icons.video_file;
        break;
      case 'pdf':
        icon = Icons.picture_as_pdf;
        break;
      case 'doc':
      case 'docx':
        icon = Icons.description;
        break;
      case 'xls':
      case 'xlsx':
        icon = Icons.table_chart;
        break;
      case 'txt':
      case 'rtf':
        icon = Icons.article;
        break;
      case 'mp3':
      case 'wav':
      case 'm4a':
      case 'ogg':
      case 'aac':
        icon = Icons.audio_file;
        break;
      default:
        icon = Icons.insert_drive_file;
    }
    return Icon(icon, size: 22, color: color);
  }
}

/// טקסט עם הדגשת מונח חיפוש
class SearchHighlightedText extends StatelessWidget {
  const SearchHighlightedText({
    super.key,
    required this.text,
    required this.query,
    required this.baseStyle,
  });

  final String text;
  final String query;
  final TextStyle baseStyle;

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return Text(text, style: baseStyle, maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    final theme = Theme.of(context);
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;

    while (true) {
      final index = lowerText.indexOf(lowerQuery, start);
      if (index == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }
      spans.add(TextSpan(
        text: text.substring(index, index + query.length),
        style: TextStyle(
          backgroundColor: theme.colorScheme.tertiary.withValues(alpha: 0.4),
          color: theme.colorScheme.onTertiaryContainer,
          fontWeight: FontWeight.bold,
        ),
      ));
      start = index + query.length;
    }

    return Text.rich(
      TextSpan(style: baseStyle, children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// קטע טקסט OCR עם תמיכה ב-RTL
class SearchOcrSnippet extends StatelessWidget {
  const SearchOcrSnippet({super.key, required this.text, required this.query});

  final String text;
  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snippet = getTextSnippet(text, query);
    final isRtl = isHebrew(snippet);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.format_quote, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Directionality(
              textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
              child: SearchHighlightedText(
                text: snippet,
                query: query,
                baseStyle: theme.textTheme.bodySmall!.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// שורת פרט — אייקון + תווית + ערך (למשל בפרטי קובץ)
class SearchDetailRow extends StatelessWidget {
  const SearchDetailRow({
    super.key,
    required this.theme,
    required this.label,
    required this.value,
    required this.icon,
    this.isPath = false,
    this.accentColor,
  });

  final ThemeData theme;
  final String label;
  final String value;
  final IconData icon;
  final bool isPath;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final secondaryColor = theme.textTheme.bodyMedium?.color ?? theme.colorScheme.onSurfaceVariant;
    final iconColor = accentColor ?? secondaryColor;
    final textColor = theme.textTheme.bodyLarge?.color ?? (theme.brightness == Brightness.dark ? Colors.white : Colors.black);
    return Row(
      crossAxisAlignment: isPath ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 12),
        SizedBox(width: 80, child: Text(label, style: TextStyle(color: secondaryColor, fontSize: 13))),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontSize: 13, color: textColor),
            textDirection: isHebrew(value) ? TextDirection.rtl : TextDirection.ltr,
            maxLines: isPath ? 2 : 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// תגית מקור — תיקייה / WhatsApp / Google Drive
class SearchResultSourceTag extends StatelessWidget {
  const SearchResultSourceTag({
    super.key,
    required this.folderName,
    required this.isWhatsApp,
    required this.isCloud,
  });

  final String folderName;
  final bool isWhatsApp;
  final bool isCloud;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isWhatsApp ? Colors.green.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Icon(
            isWhatsApp ? Icons.chat_bubble : (isCloud ? Icons.cloud : Icons.folder),
            size: 10,
            color: isWhatsApp ? Colors.green : (isCloud ? Colors.blue : Colors.grey.shade500),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              isCloud ? 'Google Drive' : folderName,
              style: TextStyle(
                fontSize: 10,
                color: isWhatsApp ? Colors.green : (isCloud ? Colors.blue : Colors.grey.shade500),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// שורת 4 שלבי הצינור — OCR, DICT, VIS, AI
class SearchPipelineStatusRow extends StatelessWidget {
  const SearchPipelineStatusRow({super.key, required this.file});

  final FileMetadata file;

  Color _colorFor(String status) {
    switch (status) {
      case 'success':
        return Colors.green;
      case 'failed':
        return Colors.red;
      case 'pending':
        return Colors.orange;
      case 'skipped':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = file.processingSteps;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildIcon(Icons.description, steps.ocrStatus, 'OCR'),
        const SizedBox(width: 4),
        _buildIcon(Icons.menu_book, steps.dictionaryStatus, 'DICT'),
        const SizedBox(width: 4),
        _buildIcon(Icons.visibility_off, steps.visionStatus, 'VIS'),
        const SizedBox(width: 4),
        _buildIcon(Icons.auto_awesome, steps.aiStatus, 'AI'),
      ],
    );
  }

  Widget _buildIcon(IconData icon, String status, String label) {
    final color = _colorFor(status);
    final displayIcon = status == 'skipped' ? Icons.block : icon;
    return Tooltip(
      message: '$label: $status',
      child: Icon(displayIcon, size: 14, color: color),
    );
  }
}

/// שורת מטא — גודל, תאריך, debug score
class SearchResultMetaRow extends StatelessWidget {
  const SearchResultMetaRow({
    super.key,
    required this.file,
    required this.showDebugScore,
  });

  final FileMetadata file;
  final bool showDebugScore;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 2,
      children: [
        Text(
          file.readableSize,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          textDirection: TextDirection.ltr,
        ),
        Text(
          formatDate(file.lastModified),
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          textDirection: TextDirection.ltr,
        ),
        if (showDebugScore && file.debugScore != null)
          Text(
            formatDebugScore(file.debugScore!, file.debugScoreBreakdown),
            style: TextStyle(
              fontSize: 10,
              color: Colors.deepOrange,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }
}

/// שורת טיפ — אייקון + טקסט
class SearchTipRow extends StatelessWidget {
  const SearchTipRow({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, color: Colors.green, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
          ),
        ],
      ),
    );
  }
}

/// צ'יפ תגית קטן (לפריט תוצאה)
class SearchTagChip extends StatelessWidget {
  const SearchTagChip({super.key, required this.tag});

  final CustomTag tag;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tag.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: tag.color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(tag.icon, size: 10, color: tag.color),
          const SizedBox(width: 3),
          Text(tag.name, style: TextStyle(fontSize: 9, color: tag.color)),
        ],
      ),
    );
  }
}
