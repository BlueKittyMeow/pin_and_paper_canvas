import 'dart:async' show unawaited;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:pin_and_paper_canvas/spatial_canvas.dart';
import 'package:pin_and_paper_card_renderer/card_renderer.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      // The DEBUG ribbon drapes over the appbar's right corner on desktop
      // and hides/crowds the action icons (owner report 2026-08-03).
      debugShowCheckedModeBanner: false,
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

  // Which back-face rows to show when a card is flipped. Example-app-only
  // UI state (the settings menu below), deliberately separate from the
  // flip-per-card state that lives on `_dataSource`: this is a display
  // preference shared by every card, not per-entity data. In-memory only,
  // per this task's brief -- no persistence.
  TaskCardBackFields _backFields = const TaskCardBackFields();

  static const _kBackFieldsKey = 'example_card_back_fields';

  @override
  void initState() {
    super.initState();
    _dataSource = MockSpatialDataSource(canvasSize: kExampleCanvasSize);
    _controller = SpatialCanvasController();
    unawaited(_restoreBackFields());
  }

  Future<void> _restoreBackFields() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kBackFieldsKey);
      if (raw == null || !mounted) return;
      final saved = jsonDecode(raw) as Map<String, dynamic>;
      setState(() {
        _backFields = TaskCardBackFields(
          showStatus: saved['status'] as bool? ?? true,
          showDueDate: saved['dueDate'] as bool? ?? true,
          showTags: saved['tags'] as bool? ?? true,
          showNotes: saved['notes'] as bool? ?? true,
          showCreated: saved['created'] as bool? ?? false,
          showId: saved['id'] as bool? ?? false,
        );
      });
    } catch (_) {
      // No prefs backend (plain widget tests): keep defaults, in-memory.
    }
  }

  Future<void> _persistBackFields() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kBackFieldsKey,
        jsonEncode({
          'status': _backFields.showStatus,
          'dueDate': _backFields.showDueDate,
          'tags': _backFields.showTags,
          'notes': _backFields.showNotes,
          'created': _backFields.showCreated,
          'id': _backFields.showId,
        }),
      );
    } catch (_) {
      // Best-effort, same as the data source's layout persistence.
    }
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
          // Double-tap a card to flip it; this menu picks which rows its
          // back face shows. Standard PopupMenuButton close-on-select
          // behavior (no StatefulBuilder-kept-open menu) -- simple and
          // robust beats a fancier menu for this preview.
          PopupMenuButton<_BackField>(
            tooltip: 'Card back fields',
            // A labeled button, not a bare glyph: the lone Icons.tune was
            // invisible next to three zoom icons (owner couldn't find it).
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.flip_to_back, size: 18),
                  SizedBox(width: 6),
                  Text('Card backs'),
                ],
              ),
            ),
            onSelected: (field) {
              setState(() {
                _backFields = _toggleBackField(_backFields, field);
              });
              unawaited(_persistBackFields());
            },
            itemBuilder: (context) => [
              for (final field in _BackField.values)
                CheckedPopupMenuItem<_BackField>(
                  value: field,
                  checked: _backFieldValue(_backFields, field),
                  child: Text(_backFieldLabels[field]!),
                ),
            ],
          ),
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
          entityBuilder: _buildEntityWidget,
          canvasSize: kExampleCanvasSize,
          controller: _controller,
          // The default drag-lift shadow is a rounded rect -- right for
          // cards, a "weird square shadow" under the amethyst, which paints
          // its own grounding pool (owner report 2026-08-03). Suppress it
          // for the stone; lift scale still applies.
          liftDecorationBuilder: (entity) =>
              entity is AmethystEntity ? const BoxDecoration() : null,
          // Delineates exactly where the usable desk ends: a dark surface
          // filling the canvas bounds, framed by a thin amber edge (the
          // owner's dark-theme-with-gold-accent palette, #C4941A, used
          // sparingly here). Demonstrates SpatialCanvas.background for
          // Milestone 2/3 implementers -- non-interactive, purely decorative.
          background: Container(
            decoration: BoxDecoration(
              // Lara's seamless kraft-paper texture (from the sketchpad
              // asset library, downscaled): the desk reads as warm craft
              // paper, cream cards sit on it like real index cards. The
              // amber edge still marks where the usable desk ends.
              image: const DecorationImage(
                image: AssetImage('assets/SeamlessKraft1.jpg'),
                repeat: ImageRepeat.repeat,
              ),
              border: Border.all(color: const Color(0xFFC4941A), width: 2),
            ),
          ),
        ),
      ),
    );
  }

  // Milestone 2 preview: the real card renderer on the mock desk, plus the
  // one amethyst desk object -- branches on entity type rather than an
  // unconditional cast, since the canvas now hosts two different kinds of
  // SpatialEntity (mock_spatial_data_source.dart's AmethystEntity being the
  // second). Milestone 4 repeats the card half of this wiring in the main
  // app with real tasks. FlippableTaskCard (rather than TaskCard directly)
  // is what makes double-tap-to-flip work -- it reads flip state from the
  // data source, same as isSelected reads selection state from the canvas.
  Widget _buildEntityWidget(SpatialEntity entity, bool isSelected) {
    if (entity is AmethystEntity) {
      final chunk = AmethystChunk(
        size: entity.size,
        rotationY: entity.rotationY,
        isSelected: isSelected,
        // Explicit even though it's also AmethystChunk's own default: this
        // is the one azimuth value the whole desk shares today (see
        // kDeskLightAzimuth's doc comment) -- passing it explicitly here is
        // what Phase 5 will change to instead read a real shared light
        // state.
        lightAzimuthDegrees: kDeskLightAzimuth,
      );
      if (!isSelected) return chunk;
      // Selected: resize chips, INSIDE the entity's bounds (anything outside
      // a Positioned entity's box is unhittable -- the 843e79a lesson).
      // Their inner tap recognizers win the arena over the canvas's per-card
      // detector, so tapping a chip resizes without moving/deselecting.
      return Stack(children: [
        Positioned.fill(child: chunk),
        Positioned(
          top: 2,
          right: 2,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _ResizeChip(
              icon: Icons.add,
              tooltip: 'Bigger',
              onTap: () => _dataSource.resizeAmethyst(entity.id, 1.15),
            ),
            const SizedBox(height: 4),
            _ResizeChip(
              icon: Icons.remove,
              tooltip: 'Smaller',
              onTap: () => _dataSource.resizeAmethyst(entity.id, 1 / 1.15),
            ),
          ]),
        ),
      ]);
    }
    final mock = entity as MockCardEntity;
    return FlippableTaskCard(
      data: mock.cardData,
      showBack: _dataSource.isFlipped(mock.id),
      isSelected: isSelected,
      backFields: _backFields,
    );
  }
}

/// Small circular resize control shown on the selected amethyst. Amber on
/// dark, matching the desk's accent language; deliberately tiny so it reads
/// as a handle, not a toolbar.
class _ResizeChip extends StatelessWidget {
  const _ResizeChip({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: const Color(0xCC16161F),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFC4941A), width: 1),
          ),
          child: Icon(icon, size: 14, color: const Color(0xFFC4941A)),
        ),
      ),
    );
  }
}

/// One togglable row in the "Card back fields" menu, paired with the
/// [TaskCardBackFields] flag it reads/writes.
enum _BackField { status, dueDate, tags, notes, created, id }

const Map<_BackField, String> _backFieldLabels = {
  _BackField.status: 'Status',
  _BackField.dueDate: 'Due date',
  _BackField.tags: 'Tags',
  _BackField.notes: 'Notes',
  _BackField.created: 'Created',
  _BackField.id: 'Id',
};

bool _backFieldValue(TaskCardBackFields fields, _BackField field) => switch (field) {
  _BackField.status => fields.showStatus,
  _BackField.dueDate => fields.showDueDate,
  _BackField.tags => fields.showTags,
  _BackField.notes => fields.showNotes,
  _BackField.created => fields.showCreated,
  _BackField.id => fields.showId,
};

TaskCardBackFields _toggleBackField(TaskCardBackFields fields, _BackField field) => switch (field) {
  _BackField.status => fields.copyWith(showStatus: !fields.showStatus),
  _BackField.dueDate => fields.copyWith(showDueDate: !fields.showDueDate),
  _BackField.tags => fields.copyWith(showTags: !fields.showTags),
  _BackField.notes => fields.copyWith(showNotes: !fields.showNotes),
  _BackField.created => fields.copyWith(showCreated: !fields.showCreated),
  _BackField.id => fields.copyWith(showId: !fields.showId),
};
