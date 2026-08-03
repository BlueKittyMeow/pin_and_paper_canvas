import 'package:flutter/material.dart';
import 'package:pin_and_paper_canvas/spatial_canvas.dart';

import 'mock_spatial_data_source.dart';

void main() {
  runApp(const CanvasExampleApp());
}

/// Canvas bounds for the example -- matches the size the MVP plan specifies
/// for Milestone 4's real Spatial View in the main app, so this demo is a
/// faithful stand-in for gesture-feel testing.
const Size kExampleCanvasSize = Size(2000, 1500);

class CanvasExampleApp extends StatelessWidget {
  const CanvasExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'pin_and_paper_canvas example',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFC4941A))),
      home: const CanvasDemoScreen(),
    );
  }
}

class CanvasDemoScreen extends StatefulWidget {
  const CanvasDemoScreen({super.key});

  @override
  State<CanvasDemoScreen> createState() => _CanvasDemoScreenState();
}

class _CanvasDemoScreenState extends State<CanvasDemoScreen> {
  late final MockSpatialDataSource _dataSource;
  late final SpatialCanvasController _controller;

  @override
  void initState() {
    super.initState();
    _dataSource = MockSpatialDataSource(canvasSize: kExampleCanvasSize);
    _controller = SpatialCanvasController();
  }

  @override
  void dispose() {
    _dataSource.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('pin_and_paper_canvas ($kMockCardCount cards)'),
        actions: [
          IconButton(
            tooltip: 'Zoom out',
            icon: const Icon(Icons.zoom_out),
            onPressed: () => _controller.zoomTo(_controller.currentZoom - 0.25),
          ),
          IconButton(
            tooltip: 'Reset zoom',
            icon: const Icon(Icons.center_focus_strong),
            onPressed: () => _controller.zoomTo(1.0),
          ),
          IconButton(
            tooltip: 'Zoom in',
            icon: const Icon(Icons.zoom_in),
            onPressed: () => _controller.zoomTo(_controller.currentZoom + 0.25),
          ),
        ],
      ),
      body: Container(
        // Beyond the canvas edge is the "void" past the desk -- deliberately
        // darker and flatter than the desk surface itself (SpatialCanvas's
        // `background`, below) so panning/zooming past the boundary reads as
        // leaving the usable canvas, not just more felt. Purely cosmetic,
        // not part of the module's API.
        color: const Color(0xFF0F0F17),
        child: SpatialCanvas(
          dataSource: _dataSource,
          entityBuilder: _buildMockCard,
          canvasSize: kExampleCanvasSize,
          controller: _controller,
          // Delineates exactly where the usable desk ends: a dark surface
          // filling the canvas bounds, framed by a thin amber edge (the
          // owner's dark-theme-with-gold-accent palette, #C4941A, used
          // sparingly here). Demonstrates SpatialCanvas.background for
          // Milestone 2/3 implementers -- non-interactive, purely decorative.
          background: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E2A),
              border: Border.all(color: const Color(0xFFC4941A), width: 2),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMockCard(SpatialEntity entity, bool isSelected) {
    final mock = entity as MockCardEntity;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: mock.color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isSelected ? Colors.white : Colors.black26, width: isSelected ? 3 : 1),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(1, 2))],
      ),
      child: Center(
        child: Text(
          mock.label,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
