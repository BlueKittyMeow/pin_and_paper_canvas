import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pin_and_paper_canvas/spatial_canvas.dart';

/// Number of mock cards the example seeds the canvas with.
///
/// Kept as a single easily-changed constant so the manual "100 entities at
/// 60fps" performance gate (DRAG_DROP_CANVAS_MVP_PLAN.md's checkpoint,
/// verified by hand on desktop, not by this automated suite) is a one-command
/// run: just `flutter run -d <desktop>` in this directory, no flags needed.
/// Defaults to 100 for exactly that reason.
const int kMockCardCount = 100;

/// A palette to cycle through so cards are visually distinguishable.
const List<Color> _mockCardColors = [
  Color(0xFF2196F3),
  Color(0xFF4CAF50),
  Color(0xFFFF9800),
  Color(0xFFE91E63),
  Color(0xFF9C27B0),
  Color(0xFF00BCD4),
  Color(0xFF795548),
  Color(0xFF607D8B),
];

/// A mutable mock entity. Not exported -- this is example-app-only scaffolding
/// standing in for a real `TaskSpatialEntity` (Milestone 4's job).
class MockCardEntity implements SpatialEntity {
  MockCardEntity({
    required this.id,
    required this.label,
    required this.position,
    required this.color,
    this.rotation = 0,
    this.size = const Size(160, 100),
    this.zIndex = 0,
  });

  @override
  final String id;

  final String label;

  @override
  Offset position;

  @override
  double rotation;

  @override
  final Size size;

  @override
  int zIndex;

  final Color color;
}

/// Mock [SpatialDataSource] for the example app: [kMockCardCount] entities
/// laid out on a grid across the canvas, draggable and selectable, with no
/// persistence (in-memory only, per INTERFACE_CONTRACTS.md's minimal mock
/// pattern).
class MockSpatialDataSource extends SpatialDataSource {
  MockSpatialDataSource({int count = kMockCardCount, Size canvasSize = const Size(2000, 1500)})
    : _entities = List.generate(count, (i) => _generateMockEntity(i, canvasSize));

  static MockCardEntity _generateMockEntity(int index, Size canvasSize) {
    const cardSize = Size(160, 100);
    const margin = 20.0;
    final cellWidth = cardSize.width + margin;
    final cellHeight = cardSize.height + margin;
    final columns = math.max(1, ((canvasSize.width - margin) / cellWidth).floor());
    final row = index ~/ columns;
    final col = index % columns;
    return MockCardEntity(
      id: 'mock-$index',
      label: 'Card $index',
      position: Offset(margin + col * cellWidth, margin + row * cellHeight),
      color: _mockCardColors[index % _mockCardColors.length],
      zIndex: index,
    );
  }

  final List<MockCardEntity> _entities;

  int _nextZIndex = kMockCardCount;

  @override
  List<SpatialEntity> getVisibleEntities(Rect viewport) => _entities;

  @override
  void onEntityMoved(String id, Offset position, double rotation) {
    final entity = _entities.firstWhere((e) => e.id == id);
    entity.position = position;
    entity.rotation = rotation;
    // Tap-to-front-on-move is a small, harmless MVP nicety: keeps whatever
    // you just dragged from being buried under other cards. Full "tap
    // brings to front" (fable-review.md sec 1.6) is deferred; this just
    // rides along with the move commit.
    entity.zIndex = _nextZIndex++;
    notifyListeners();
  }

  @override
  void onEntityTapped(String id) {
    debugPrint('MockSpatialDataSource: tapped $id');
  }

  @override
  void onEntityDoubleTapped(String id) {
    debugPrint('MockSpatialDataSource: double-tapped $id');
  }

  @override
  void onCanvasTapped(Offset position) {
    debugPrint('MockSpatialDataSource: canvas tapped at $position');
  }
}
