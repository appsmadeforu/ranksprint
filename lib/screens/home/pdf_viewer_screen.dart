import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import 'pdf_web_viewer_stub.dart'
    if (dart.library.html) 'pdf_web_viewer.dart';

class PdfViewerScreen extends StatefulWidget {
  final String pdfUrl;
  final String title;
  final List<String> pdfUrls;
  final int currentIndex;

  const PdfViewerScreen({
    super.key,
    required this.pdfUrl,
    required this.title,
    required this.pdfUrls,
    required this.currentIndex,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.currentIndex >= 0 ? widget.currentIndex : 0;
  }

  void _previousPdf() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
    }
  }

  void _nextPdf() {
    if (_currentIndex < widget.pdfUrls.length - 1) {
      setState(() => _currentIndex++);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Back',
          ),
        ],
      ),
      body: _buildPdfBody(),
      bottomNavigationBar: BottomAppBar(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ElevatedButton.icon(
                onPressed: _currentIndex > 0 ? _previousPdf : null,
                icon: const Icon(Icons.arrow_back),
                label: const Text('Previous'),
              ),
              Text(
                'Paper ${_currentIndex + 1} of ${widget.pdfUrls.length}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _currentIndex < widget.pdfUrls.length - 1
                    ? _nextPdf
                    : null,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Next'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPdfBody() {
    final url = widget.pdfUrls[_currentIndex];
    if (isWebPdfViewerSupported) {
      return buildWebPdfViewer(url);
    }

    return SfPdfViewer.network(
      url,
      onDocumentLoadFailed: (PdfDocumentLoadFailedDetails details) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading PDF: ${details.error}')),
        );
      },
    );
  }
}
