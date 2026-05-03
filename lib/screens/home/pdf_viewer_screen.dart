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
  bool _isPdfLoading = true;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.currentIndex >= 0 ? widget.currentIndex : 0;
    _beginPdfLoad();
  }

  void _previousPdf() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
      });
      _beginPdfLoad();
    }
  }

  void _nextPdf() {
    if (_currentIndex < widget.pdfUrls.length - 1) {
      setState(() {
        _currentIndex++;
      });
      _beginPdfLoad();
    }
  }

  void _beginPdfLoad() {
    if (!mounted) return;
    setState(() => _isPdfLoading = true);

    if (isWebPdfViewerSupported) {
      Future<void>.delayed(const Duration(milliseconds: 1400), () {
        if (mounted) {
          setState(() => _isPdfLoading = false);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Back',
          ),
        ],
      ),
      body: Stack(
        children: [
          _buildPdfBody(),
          if (_isPdfLoading) const _PdfLoadingOverlay(),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        color: colorScheme.surface,
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
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurface,
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
      onDocumentLoaded: (_) {
        if (mounted) {
          setState(() => _isPdfLoading = false);
        }
      },
      onDocumentLoadFailed: (PdfDocumentLoadFailedDetails details) {
        if (mounted) {
          setState(() => _isPdfLoading = false);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading PDF: ${details.error}')),
        );
      },
    );
  }
}

class _PdfLoadingOverlay extends StatelessWidget {
  const _PdfLoadingOverlay();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.surface.withValues(alpha: 0.92),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(
              strokeWidth: 3.2,
              color: colorScheme.primary,
            ),
          ),
          SizedBox(height: 18),
          Text(
            'Loading paper...',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'This may take a few seconds',
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
