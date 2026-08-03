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

/// Believable notes, loosely paired with [_mockTitles] by index, for the
/// card-flip back face preview. Only a fraction of cards get one (see
/// `_generateMockEntity`) -- most index cards are bare, some have a line or
/// two jotted on the back, same as real ones.
const List<String> _mockNotes = [
  'Check the soil moisture before watering -- the ferns are still recovering from the heat wave.',
  'Need the season 22 discs from archive.org; check file sizes before starting the rip.',
  'The chips.py patch keeps getting wiped on pip upgrades -- write it down somewhere permanent this time.',
  'Ask Kyla if the drive still has room before starting; last sync filled it to 90%.',
  "Chapter three needs the pacing fix from Lara's margin notes, not a full rewrite.",
  'Ply is thinner than planned -- might need a third bobbin to hit worsted weight.',
  'Current box is down to three sleeves; order from the usual supplier before the next batch.',
  "Router UI shows conditional forwarding as enabled but it's still not resolving local hostnames reliably.",
];

/// The amethyst chunk desk object: a fixed-pose mineral sitting on the desk
/// alongside the mock cards, one-of-a-kind (there's exactly one, id
/// `'amethyst-1'`) rather than generated in bulk like [MockCardEntity].
///
/// Unlike a card's `rotation` (this class's own [rotation], which the
/// canvas's `Transform.rotate` applies as ordinary 2D layout rotation, in
/// degrees), [rotationY] is the crystal's 3D mesh yaw around its vertical
/// axis, consumed directly by `AmethystChunkPainter`
/// (`example/lib/crystal/amethyst_chunk.dart`). It's fixed at construction
/// and never changes -- this entity keeps the one pose it was built with for
/// its entire lifetime, including across drags (dragging moves [position]
/// only; see [MockSpatialDataSource.onEntityMoved]'s type-check branch for
/// this entity). [rotation] itself stays permanently 0: nothing in this POC
/// drives 2D layout rotation for the stone.
class AmethystEntity implements SpatialEntity {
  AmethystEntity({
    required this.id,
    required this.position,
    required this.rotationY,
    this.size = const Size(150, 120),
    this.zIndex = 0,
  });

  @override
  final String id;

  @override
  Offset position;

  /// The crystal mesh's fixed yaw, in radians. See this class's doc comment.
  final double rotationY;

  @override
  double get rotation => 0;

  /// Mutable: the owner can resize the stone via the selection chips (see
  /// MockSpatialDataSource.resizeAmethyst). Cards stay fixed-size; a desk
  /// object is decor, and decor gets to be whatever size sparks joy.
  @override
  Size size;

  @override
  int zIndex;
}

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
    : _entities = [
        ...List.generate(count, (i) => _generateMockEntity(i, canvasSize)),
        _generateAmethystEntity(count, canvasSize),
      ];

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
        // Spread over the last ~6 weeks so the back face's "Created" row
        // shows varied, plausible dates rather than everything reading "now".
        createdAt: now.subtract(Duration(days: 3 + (index * 5) % 40)),
        // 1 in 4 cards has a note -- believable back-of-card detail, not
        // every card (per this task's "believable" brief).
        notes: index % 4 == 0 ? _mockNotes[(index ~/ 4) % _mockNotes.length] : null,
      ),
      position: Offset(margin + col * cellWidth, margin + row * cellHeight) + layerOffset,
      zIndex: index,
    );
  }

  /// Places the single amethyst chunk on an open patch of desk below the
  /// mock card grid -- computed from the same grid math [_generateMockEntity]
  /// uses (margin/cell size/column count), rather than a hand-picked
  /// constant, so this keeps working if [kMockCardCount] or [canvasSize]
  /// ever change. `usedRows` is how many grid rows the card count actually
  /// fills; sitting a full cell below that (plus the standard margin) clears
  /// the grid entirely -- verified against the current defaults (24 cards,
  /// 2000x1500 canvas, 220x140 cards): 8 columns, 3 used rows, so the chunk
  /// lands at roughly (20, 520), well clear of the cards' y-range of
  /// 20..480.
  static AmethystEntity _generateAmethystEntity(int cardCount, Size canvasSize) {
    const margin = 20.0;
    const chunkSize = Size(150, 120);
    final cellWidth = kCardSize.width + margin;
    final cellHeight = kCardSize.height + margin;
    final columns = math.max(1, ((canvasSize.width - margin) / cellWidth).floor());
    final usedRows = (cardCount / columns).ceil();
    final top = margin + usedRows * cellHeight + margin;

    return AmethystEntity(
      id: 'amethyst-1',
      position: Offset(margin, top),
      // Reference prototype's initial pose (`state.rot = 0.15`); fixed
      // forever per this entity's doc comment.
      rotationY: 0.15,
      size: chunkSize,
      zIndex: cardCount,
    );
  }

  final List<SpatialEntity> _entities;

  int _nextZIndex = kMockCardCount;

  /// Ids currently showing their back face. Lives here (next to the other
  /// per-entity state this data source already owns) rather than in the
  /// screen's `State`, because it's toggled by a `SpatialDataSource`
  /// callback ([onEntityDoubleTapped]) the same way selection/position are
  /// -- and this class is already a `ChangeNotifier` the canvas listens to,
  /// so `notifyListeners()` here rebuilds the canvas for free, same as
  /// [onEntityMoved] does.
  final Set<String> _flippedIds = {};

  /// Whether [id]'s card is currently showing `TaskCardBack`. Read by the
  /// example's `entityBuilder` when building each `FlippableTaskCard`.
  bool isFlipped(String id) => _flippedIds.contains(id);

  /// Uniformly scales the amethyst by [factor], growing/shrinking from its
  /// center (position compensates by half the size delta) so it doesn't
  /// appear to slide toward its own top-left corner. Width clamped to
  /// [90, 280]; the 150:120 aspect is preserved.
  void resizeAmethyst(String id, double factor) {
    final entity = _entities.whereType<AmethystEntity>().firstWhere((e) => e.id == id);
    final oldSize = entity.size;
    final newW = (oldSize.width * factor).clamp(90.0, 280.0);
    final newSize = Size(newW, newW * (120 / 150));
    entity.position += Offset((oldSize.width - newSize.width) / 2, (oldSize.height - newSize.height) / 2);
    entity.size = newSize;
    notifyListeners();
  }

  @override
  List<SpatialEntity> getVisibleEntities(Rect viewport) => _entities;

  @override
  void onEntityMoved(String id, Offset position, double rotation) {
    // _entities is now heterogeneous (MockCardEntity + the one
    // AmethystEntity), and SpatialEntity itself only declares getters (no
    // setters) for position/rotation/zIndex -- MockCardEntity/AmethystEntity
    // each add their own mutable fields on top of that, so writing to them
    // needs the concrete type back via an `is` check rather than an
    // unconditional cast (the entity system has exactly two entity types in
    // this example; a third would need its own branch here).
    final entity = _entities.firstWhere((e) => e.id == id);
    if (entity is MockCardEntity) {
      entity.position = position;
      entity.rotation = rotation;
      // Tap-to-front-on-move is a small, harmless MVP nicety: keeps whatever
      // you just dragged from being buried under other cards. Full "tap
      // brings to front" (fable-review.md sec 1.6) is deferred; this just
      // rides along with the move commit.
      entity.zIndex = _nextZIndex++;
    } else if (entity is AmethystEntity) {
      entity.position = position;
      // AmethystEntity.rotation is permanently 0 (see its doc comment) --
      // the crystal's actual pose is [AmethystEntity.rotationY], which
      // dragging never touches. `rotation` from the drag is accepted (same
      // signature as the card branch) but has nothing to write back to.
      entity.zIndex = _nextZIndex++;
    }
    notifyListeners();
  }

  @override
  void onEntityTapped(String id) {
    debugPrint('MockSpatialDataSource: tapped $id');
  }

  @override
  void onEntityDoubleTapped(String id) {
    // Double-tap flips the card -- the Milestone 2 preview's stand-in for
    // whatever gesture/affordance Milestone 4 settles on in the real app.
    // Only cards flip; the amethyst has no back face.
    if (_entities.whereType<AmethystEntity>().any((e) => e.id == id)) return;
    if (!_flippedIds.remove(id)) {
      _flippedIds.add(id);
    }
    notifyListeners();
  }

  @override
  void onCanvasTapped(Offset position) {
    debugPrint('MockSpatialDataSource: canvas tapped at $position');
  }
}
