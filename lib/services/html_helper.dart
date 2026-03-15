import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

class HtmlHelper {
  static const List<String> _defaultImageKeys = [
    'imageUrl',
    'imageUrls',
    'image',
    'images',
    'questionImageUrl',
    'questionImageUrls',
    'questionImage',
    'questionImages',
    'optionImageUrl',
    'optionImageUrls',
    'optionImage',
    'optionImages',
  ];

  /// Converts HTML string to plain text by removing tags and decoding entities
  static String htmlToPlainText(String? html) {
    if (html == null || html.isEmpty) {
      return '';
    }

    String text = html;

    // Remove script and style tags completely
    text = text.replaceAll(RegExp(r'<script>.*?</script>', dotAll: true), '');
    text = text.replaceAll(RegExp(r'<style>.*?</style>', dotAll: true), '');

    // Convert common block elements to newlines
    text = text.replaceAll(RegExp(r'</p>', caseSensitive: false), '\n');
    text = text.replaceAll(RegExp(r'</div>', caseSensitive: false), '\n');
    text = text.replaceAll(RegExp(r'</li>', caseSensitive: false), '\n');
    text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');

    // Remove all other HTML tags
    text = text.replaceAll(RegExp(r'<[^>]*>', dotAll: true), '');

    // Decode HTML entities
    text = _decodeHtmlEntities(text);

    // Clean up excessive whitespace
    text = text.replaceAll(RegExp(r'\n\s*\n'), '\n'); // Remove empty lines
    text = text.replaceAll(RegExp(r'[ \t]+'), ' '); // Collapse spaces/tabs
    text = text.trim();

    return text;
  }

  /// Decodes common HTML entities
  static String _decodeHtmlEntities(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&copy;', '©')
        .replaceAll('&reg;', '®')
        .replaceAll('&bull;', '•')
        .replaceAll('&hellip;', '…')
        .replaceAll('&#x27;', "'");
  }

  /// Builds a Text widget from HTML content
  static Widget buildTextFromHtml(
    String? html, {
    TextStyle? style,
    int? maxLines,
    TextOverflow overflow = TextOverflow.clip,
  }) {
    final plainText = htmlToPlainText(html);
    return Text(
      plainText,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
    );
  }

  /// Builds a rich text widget that preserves basic formatting
  static InlineSpan buildRichTextFromHtml(String? html) {
    if (html == null || html.isEmpty) {
      return const TextSpan(text: '');
    }

    final plainText = htmlToPlainText(html);
    return TextSpan(text: plainText);
  }

  /// Renders HTML as a widget using flutter_html
  static Widget renderHtml(String html, {
    TextStyle? style,
    int? maxLines,
    TextOverflow? overflow,
  }) {
    return Html(
      data: html,
      style: {
        "body": Style(
          fontSize: style?.fontSize != null ? FontSize(style!.fontSize!) : FontSize(14),
          color: style?.color ?? Colors.black,
          margin: Margins.zero,
          padding: HtmlPaddings.zero,
          maxLines: maxLines,
          textOverflow: overflow,
        ),
        "p": Style(
          margin: Margins.zero,
          padding: HtmlPaddings.zero,
          fontSize: style?.fontSize != null ? FontSize(style!.fontSize!) : FontSize(14),
          color: style?.color ?? Colors.black,
          maxLines: maxLines,
          textOverflow: overflow,
        ),
        "div": Style(
          margin: Margins.zero,
          padding: HtmlPaddings.zero,
          fontSize: style?.fontSize != null ? FontSize(style!.fontSize!) : FontSize(14),
          color: style?.color ?? Colors.black,
          maxLines: maxLines,
          textOverflow: overflow,
        ),
        "span": Style(
          margin: Margins.zero,
          padding: HtmlPaddings.zero,
          fontSize: style?.fontSize != null ? FontSize(style!.fontSize!) : FontSize(14),
          color: style?.color ?? Colors.black,
          maxLines: maxLines,
          textOverflow: overflow,
        ),
      },
    );
  }

  static List<String> extractImageUrls(
    dynamic source, {
    List<String> preferredKeys = const [],
  }) {
    if (source is! Map) {
      return const [];
    }

    final urls = <String>[];
    final seen = <String>{};
    final keys = <String>[
      ...preferredKeys,
      ..._defaultImageKeys.where((key) => !preferredKeys.contains(key)),
    ];

    for (final key in keys) {
      _collectImageUrls(source[key], urls, seen);
    }

    return urls;
  }

  static Widget renderContent({
    String? html,
    List<String> imageUrls = const [],
    TextStyle? style,
    int? maxLines,
    TextOverflow? overflow,
    double imageSpacing = 12,
    double borderRadius = 12,
  }) {
    final content = html?.trim() ?? '';
    final dedupedImageUrls = <String>[];
    final seen = <String>{};

    for (final url in imageUrls) {
      final normalized = url.trim();
      if (normalized.isEmpty ||
          seen.contains(normalized) ||
          (content.isNotEmpty && content.contains(normalized))) {
        continue;
      }
      seen.add(normalized);
      dedupedImageUrls.add(normalized);
    }

    if (content.isEmpty && dedupedImageUrls.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (content.isNotEmpty)
          renderHtml(
            content,
            style: style,
            maxLines: maxLines,
            overflow: overflow,
          ),
        for (int i = 0; i < dedupedImageUrls.length; i++) ...[
          if (content.isNotEmpty || i > 0) SizedBox(height: imageSpacing),
          _HtmlNetworkImage(
            imageUrl: dedupedImageUrls[i],
            borderRadius: borderRadius,
            textStyle: style,
          ),
        ],
      ],
    );
  }

  static void _collectImageUrls(
    dynamic value,
    List<String> urls,
    Set<String> seen,
  ) {
    if (value == null) {
      return;
    }

    if (value is String) {
      final normalized = value.trim();
      if (_isImageLikeUrl(normalized) && seen.add(normalized)) {
        urls.add(normalized);
      }
      return;
    }

    if (value is Iterable) {
      for (final item in value) {
        _collectImageUrls(item, urls, seen);
      }
      return;
    }

    if (value is Map) {
      for (final key in const ['imageUrl', 'url', 'src', 'downloadUrl']) {
        _collectImageUrls(value[key], urls, seen);
      }
    }
  }

  static bool _isImageLikeUrl(String value) {
    if (value.isEmpty) {
      return false;
    }

    final uri = Uri.tryParse(value);
    if (uri == null || !(uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https'))) {
      return false;
    }

    return true;
  }
}

class _HtmlNetworkImage extends StatelessWidget {
  const _HtmlNetworkImage({
    required this.imageUrl,
    required this.borderRadius,
    required this.textStyle,
  });

  final String imageUrl;
  final double borderRadius;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Image.network(
        imageUrl,
        fit: BoxFit.contain,
        width: double.infinity,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) {
            return child;
          }

          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: const Color(0xFFF8FAFC),
            child: const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: const Color(0xFFF8FAFC),
            child: Text(
              'Unable to load image',
              style: TextStyle(
                color: textStyle?.color ?? Colors.black54,
                fontSize: textStyle?.fontSize ?? 14,
              ),
            ),
          );
        },
      ),
    );
  }
}
