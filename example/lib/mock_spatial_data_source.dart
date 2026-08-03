import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pin_and_paper_canvas/spatial_canvas.dart';
import 'package:pin_and_paper_card_renderer/card_renderer.dart';

/// Number of mock cards the example seeds the canvas with.
///
/// 24 gives a pleasant, uncrowded demo desk (owner feedback: 100 was
/// overwhelming with the overflow stacking). For the manual "100 entities at
/// 60fps" performance gate (DRAG_DROP_CANVAS_MVP_PLAN.md's checkpoint,
/// verified by hand on desktop), set this to 100 and `flutter run` — that
/// one-line flip is the whole procedure. Gate last passed 2026-08-03.
const int kMockCardCount = 24;

/// Believable to-do titles so the Milestone 2 preview reads like a real desk,
/// not lorem ipsum. Cycled (with variation) across [kMockCardCount] cards.
const List<String> _mockTitles = [
  'Water the plants',
  'Rip the next Sesame Street disc',
  'Reflash Robody motor HAT service',
  'Back up Darby to Google Drive',
  'Revise MFA chapter three',
  'Spin the grey wool for the shawl',
  'Order more archival sleeves',
  'Fix the Pi-hole conditional forwarding',
  'Write morning pages',
  'Plan the Victoriana render batch',
  'Mend the studio curtain hem',
  'Catalogue the new paper stock',
  'Test the braille-click prototype',
  'Email Armen about the demo page',
  'Sketch journal cover ideas',
  'Sharpen the good scissors (finally)',
];

/// Small reusable tag set in the owner's palette family; text colors chosen
/// for contrast against each chip color.
const List<TagChip> _mockTags = [
  TagChip(id: 't1', name: 'home', color: Color(0xFF4CAF50), textColor: Colors.white),
  TagChip(id: 't2', name: 'writing', color: Color(0xFF9C27B0), textColor: Colors.white),
  TagChip(id: 't3', name: 'robody', color: Color(0xFF2196F3), textColor: Colors.white),
  TagChip(id: 't4', name: 'urgent', color: Color(0xFFE91E63), textColor: Colors.white),
  TagChip(id: 't5', name: 'fiber arts', color: Color(0xFF795548), textColor: Colors.white),
  TagChip(id: 't6', name: 'someday', color: Color(0xFF607D8B), textColor: Colors.white),
];

/// A mutable mock entity. Not exported -- this is example-app-only scaffolding
/// standing in for a real `TaskSpatialEntity` (Milestone 4's job).
class MockCardEntity implements SpatialEntity {
  MockCardEntity({
    required this.id,
    required this.cardData,
    required this.position,
    this.rotation = 0,
    this.size = kCardSize,
    this.zIndex = 0,
  });

  @override
  final String id;

  /// What the card renderer draws (Milestone 2 preview wiring).
  final TaskCardData cardData;

  @override
  Offset position;

  @override
  double rotation;

  @override
  final Size size;

  @override
  int zIndex;
}

/// Mock [SpatialDataSource] for the example app: [kMockCardCount] entities
/// laid out on a grid across the canvas, draggable and selectable, with no
/// persistence (in-memory only, per INTERFACE_CONTRACTS.md's minimal mock
/// pattern).
class MockSpatialDataSource extends SpatialDataSource {
  MockSpatialDataSource({int count = kMockCardCount, Size canvasSize = const Size(2000, 1500)})
    : _entities = List.generate(count, (i) => _generateMockEntity(i, canvasSize));

  static MockCardEntity _generateMockEntity(int index, Size canvasSize) {
    const margin = 20.0;
    final cellWidth = kCardSize.width + margin;
    final cellHeight = kCardSize.height + margin;
    final columns = math.max(1, ((canvasSize.width - margin) / cellWidth).floor());
    final rows = math.max(1, ((canvasSize.height - margin) / cellHeight).floor());
    final capacity = columns * rows;

    // Cards past the grid's capacity restart the grid with a small diagonal
    // offset per "layer" -- deliberate overlap, which doubles as a live demo
    // of drag/selection raising (fix 4980e5e).
    final layer = index ~/ capacity;
    final slot = index % capacity;
    final row = slot ~/ columns;
    final col = slot % columns;
    final layerOffset = Offset(14.0 * layer, 14.0 * layer);

    final now = DateTime.now();
    // Mixed states: ~1 in 6 completed; due dates cycle through overdue,
    // upcoming, and none so every state the card can render is on the desk.
    final completed = index % 6 == 5;
    final dueBucket = index % 5;
    final dueDate = switch (dueBucket) {
      0 => now.subtract(Duration(days: 1 + index % 3)), // overdue
      1 || 2 => now.add(Duration(days: 1 + index % 9)), // upcoming
      _ => null,
    };

    return MockCardEntity(
      id: 'mock-$index',
      cardData: TaskCardData(
        id: 'mock-$index',
        title: _mockTitles[index % _mockTitles.length],
        tags: [
          _mockTags[index % _mockTags.length],
          if (index % 3 == 0) _mockTags[(index + 2) % _mockTags.length],
        ],
        dueDate: dueDate,
        isCompleted: completed,
        isOverdue: !completed && dueBucket == 0,
      ),
      position: Offset(margin + col * cellWidth, margin + row * cellHeight) + layerOffset,
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
