import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

class HtmlHelper {
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
}
