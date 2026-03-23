import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

const bool isWebPdfViewerSupported = true;

Widget buildWebPdfViewer(String pdfUrl) {
  final viewType = 'pdf-viewer-${pdfUrl.hashCode}';

  ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
    final iframe = web.HTMLIFrameElement()
      ..src = pdfUrl
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%';
    return iframe;
  });

  return HtmlElementView(viewType: viewType);
}
