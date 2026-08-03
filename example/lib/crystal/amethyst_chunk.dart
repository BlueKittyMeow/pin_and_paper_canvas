// The amethyst chunk desk object: a raw, squat crystal rendered with a
// hand-rolled 3D pipeline (seeded point cloud -> brute-force convex hull ->
// projected/shaded triangles), not a 3D engine. This is a faithful Dart port
// of the owner-approved reference prototype (a standalone JS/canvas page,
// "Crystal Shape Fitting -- Pin & Paper"). Every formula below -- the RNG,
// the point cloud's jitter/squash/shear, the hull test, the projection, the
// lambert+specular shading, the fog/veil inclusions, the cast shadow/pool --
// is carried over term-for-term from that reference; see individual doc
// comments for the handful of places Dart's type system or API shape forced
// a (verified-equivalent) restatement rather than a literal transliteration.
//
// Ported for: the Pin & Paper canvas POC's amethyst desk object
// (example/lib/mock_spatial_data_source.dart's AmethystEntity).

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Placeholder for the desk's future global light source. DRAG_DROP_CANVAS
/// _MVP_PLAN.md's Phase 5 gives the whole desk one shared light wash that
/// every object samples; until that lands, this is the one azimuth value the
/// example wires into every light-aware desk object by hand, so the desk
/// reads as lit from a single consistent direction. Owner-approved value:
/// 9.0 degrees (see [AmethystChunk.lightAzimuthDegrees]'s doc comment).
const double kDeskLightAzimuth = 30.0;

/// The painter's fixed camera pitch (see [AmethystChunkPainter]). Public so
/// [AmethystChunkMesh.baseAlignedYaw] can be computed with the *same*
/// projection the painter uses -- the two must never drift apart, or the
/// "bottom edge sits flat" guarantee silently breaks.
const double kAmethystCameraTilt = -0.50;

// ---------------------------------------------------------------------------
// Mesh generation: seeded point cloud -> convex hull. Pure math, no Flutter
// dependency, so it's independently testable (see amethyst_chunk_test.dart's
// hull-properties test) and trivially deterministic across runs/platforms.
// ---------------------------------------------------------------------------

/// A point/direction in the chunk's local 3D model space (unitless -- the
/// mesh lives in a roughly [-1, 1] cube, scaled to pixels at paint time).
class Vec3 {
  const Vec3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 scaled(double s) => Vec3(x * s, y * s, z * s);
  Vec3 cross(Vec3 o) => Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;
  double get length => math.sqrt(x * x + y * y + z * z);

  /// Unit-length copy, or `this` unchanged for a zero vector (matches the
  /// reference's `||1` guard against divide-by-zero on a degenerate normal).
  Vec3 get normalized {
    final l = length;
    return l == 0 ? this : Vec3(x / l, y / l, z / l);
  }

  @override
  String toString() => 'Vec3($x, $y, $z)';
}

/// Bit-exact port of the reference's `mulberry32` PRNG:
/// ```js
/// function mulberry32(a){return function(){a|=0;a=a+0x6D2B79F5|0;
///   let t=Math.imul(a^a>>>15,1|a);t=t+Math.imul(t^t>>>7,61|t)^t;
///   return((t^t>>>14)>>>0)/4294967296}}
/// ```
/// JS's `|0`/`>>>`/`Math.imul` are all 32-bit-wraparound operations, and
/// every step here (add, xor, or, unsigned-shift, multiply-keep-low-32-bits)
/// only depends on the *bit pattern* of its operands, not on whether that
/// pattern is read as signed or unsigned -- so this port stays entirely in
/// unsigned 32-bit space (`& 0xFFFFFFFF` after add/multiply, plain `>>` for
/// the always-non-negative shifts) rather than chasing JS's signed `|0`
/// coercions, and produces identical results. Dart's 64-bit `int` can hold
/// the intermediate `x * y` product from [_mul32] even when it overflows 32
/// bits (native Dart ints wrap at 64 bits on overflow, same two's-complement
/// behavior as everywhere else in the language), so the low-32-bits mask
/// after multiplying is exact -- no separate `Math.imul`-style split-multiply
/// trick is needed. Verified bit-exact against the reference for
/// `mulberry32(23)`'s first 10 outputs (see amethyst_chunk_test.dart).
class Mulberry32 {
  Mulberry32(int seed) : _a = seed.toUnsigned(32);

  int _a;

  static int _mul32(int x, int y) => (x * y) & 0xFFFFFFFF;

  /// Next pseudo-random double in `[0, 1)`.
  double next() {
    _a = (_a + 0x6D2B79F5) & 0xFFFFFFFF;
    var t = _mul32(_a ^ (_a >> 15), 1 | _a);
    t = ((t + _mul32(t ^ (t >> 7), 61 | t)) ^ t) & 0xFFFFFFFF;
    return (t ^ (t >> 14)).toUnsigned(32) / 4294967296.0;
  }
}

/// Port of the reference's `chunkCloud(seed, n)`: `n` points on a
/// fibonacci-sphere (so the cloud has no clumped pole), each jittered to a
/// radius in `[0.62, 1.0)`, squashed 30% on `y` (a settled stone, not a
/// ball), sheared slightly on `x` by `y` (so it leans, asymmetric), then
/// shifted so its lowest point sits on `y = 0` (the desk surface).
List<Vec3> chunkCloud(int seed, int n) {
  final rnd = Mulberry32(seed);
  final pts = <Vec3>[];
  final golden = math.pi * (3 - math.sqrt(5));
  for (var i = 0; i < n; i++) {
    final t = (i + 0.5) / n;
    final phi = math.acos(1 - 2 * t);
    final theta = golden * i;
    final r = 0.62 + rnd.next() * 0.38;
    var x = math.sin(phi) * math.cos(theta) * r;
    var y = math.cos(phi) * r;
    final z = math.sin(phi) * math.sin(theta) * r;
    y *= 0.70;
    x += y * 0.14;
    pts.add(Vec3(x, y, z));
  }
  final minY = pts.map((p) => p.y).reduce(math.min);
  final shifted = pts.map((p) => Vec3(p.x, p.y - minY, p.z)).toList();

  // Flat-cut the base (owner decision 2026-08-03, deviating from the
  // fitting-room reference): real display crystals are cut flat to sit on a
  // shelf, and a planar base makes the contact line straight -- the
  // "invisible shim" under an irregular base becomes geometrically
  // impossible. Everything below the cut plane drops to y=0; if the jitter
  // left fewer than four points that low, the four lowest are flattened so
  // the hull always gains a stable base facet.
  const cutHeight = 0.22;
  var flattened = 0;
  for (var i = 0; i < shifted.length; i++) {
    if (shifted[i].y < cutHeight) {
      shifted[i] = Vec3(shifted[i].x, 0, shifted[i].z);
      flattened++;
    }
  }
  if (flattened < 4) {
    final byHeight = List<int>.generate(shifted.length, (i) => i)
      ..sort((a, b) => shifted[a].y.compareTo(shifted[b].y));
    for (final i in byHeight.take(4)) {
      shifted[i] = Vec3(shifted[i].x, 0, shifted[i].z);
    }
  }
  return List.unmodifiable(shifted);
}

/// Port of the reference's `hull3D(pts)`: brute-force convex hull by testing
/// every vertex triple's plane -- O(n^3), but `n` is 18, so it's ~816
/// candidate planes and instant. A plane is kept as a hull face iff every
/// other point lies on one side of it (within `eps`, to tolerate points that
/// land almost exactly on a candidate plane); kept faces are re-wound
/// (`[a,b,c]` vs `[a,c,b]`) so their vertex order's cross product always
/// points away from the point cloud's centroid -- i.e. every returned face
/// is already outward-oriented, with no separate normal-flipping step
/// needed anywhere downstream. Being a hull (not, say, an alpha-shape or a
/// jittered loft) is what gives the stone its "no bites taken out of it"
/// guarantee from any viewing angle -- see amethyst_chunk_test.dart's hull
/// properties test.
List<List<Vec3>> hull3D(List<Vec3> pts) {
  final faces = <List<Vec3>>[];
  final n = pts.length;
  const eps = 1e-9;

  var centroid = const Vec3(0, 0, 0);
  for (final p in pts) {
    centroid += p;
  }
  centroid = centroid.scaled(1 / n);

  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      for (var k = j + 1; k < n; k++) {
        final a = pts[i], b = pts[j], c = pts[k];
        final normal = (b - a).cross(c - a);
        var pos = 0, neg = 0;
        for (var m = 0; m < n; m++) {
          if (m == i || m == j || m == k) continue;
          final d = (pts[m] - a).dot(normal);
          if (d > eps) {
            pos++;
          } else if (d < -eps) {
            neg++;
          }
          if (pos > 0 && neg > 0) break;
        }
        if (pos > 0 && neg > 0) continue; // not a hull face -- points on both sides
        final towardCentroid = (centroid - a).dot(normal);
        faces.add(towardCentroid < 0 ? [a, b, c] : [a, c, b]);
      }
    }
  }
  return faces;
}

/// One fog-bank inclusion: a soft radial glow anchored at a fixed 3D point
/// inside the stone, so it drifts against the facets as the stone turns
/// rather than sitting flat on the screen.
class FogBlob {
  const FogBlob(this.center, this.radius, this.alpha);
  final Vec3 center;
  final double radius;
  final double alpha;
}

/// The baked chunk mesh: seed 23, n=18, computed once (a `static final`, not
/// per paint -- Dart initializes a class's `static final` field lazily on
/// first access and caches it for the process's lifetime) and shared by
/// every [AmethystChunkPainter] instance/repaint. Also carries the
/// reference's exact inclusion anchors (fog blobs + fracture veils), which
/// are hand-placed 3D points, not derived from the mesh, so they're just
/// data here.
class AmethystChunkMesh {
  AmethystChunkMesh._();

  static const int seed = 23;
  static const int pointCount = 18;

  /// Outward-oriented triangles (each a 3-element `[a, b, c]` list of
  /// [Vec3]) forming the convex hull of `chunkCloud(seed, pointCount)`.
  static final List<List<Vec3>> faces = hull3D(chunkCloud(seed, pointCount));

  /// The yaw at which the flat base's most camera-friendly edge projects as
  /// the stone's *bottom* silhouette, perfectly horizontal on screen -- so a
  /// resting stone's contact line runs parallel to the card edges (owner
  /// request 2026-08-03: "rotate the stone so the horizontal bottom of it is
  /// flat"). Computed with the painter's own projection formulas at
  /// [kAmethystCameraTilt]: for each edge of the base polygon there is
  /// exactly one yaw (mod pi) that makes its two endpoints share a screen y;
  /// among the candidates whose edge is actually the lowest thing on screen
  /// at that yaw, the widest wins.
  static final double baseAlignedYaw = _computeBaseAlignedYaw();

  static double _computeBaseAlignedYaw() {
    // Unique base-plane vertices (the flat cut guarantees >= 4), ordered
    // around their centroid so consecutive pairs are real polygon edges.
    final seen = <String>{};
    final base = <Vec3>[];
    for (final face in faces) {
      for (final v in face) {
        if (v.y == 0 && seen.add('${v.x},${v.z}')) base.add(v);
      }
    }
    if (base.length < 2) return 0;
    final cx = base.map((v) => v.x).reduce((a, b) => a + b) / base.length;
    final cz = base.map((v) => v.z).reduce((a, b) => a + b) / base.length;
    base.sort((a, b) =>
        math.atan2(a.z - cz, a.x - cx).compareTo(math.atan2(b.z - cz, b.x - cx)));

    // Same math as AmethystChunkPainter's project(), reduced to what decides
    // screen y for a base vertex (y == 0): sy ∝ -y2 = z1 * sin(tilt).
    double screenY(Vec3 v, double yaw) {
      final z1 = -v.x * math.sin(yaw) + v.z * math.cos(yaw);
      return -(v.y * math.cos(kAmethystCameraTilt) - z1 * math.sin(kAmethystCameraTilt));
    }

    double screenX(Vec3 v, double yaw) =>
        v.x * math.cos(yaw) + v.z * math.sin(yaw);

    var bestYaw = 0.0, bestSpan = -1.0;
    for (var i = 0; i < base.length; i++) {
      final a = base[i], b = base[(i + 1) % base.length];
      // Yaw that zeroes the edge's rotated z-span -> endpoints share sy.
      final theta = math.atan2(b.z - a.z, b.x - a.x);
      for (final yaw in [theta, theta + math.pi]) {
        final edgeY = math.max(screenY(a, yaw), screenY(b, yaw));
        var isBottom = true;
        for (final v in base) {
          if (screenY(v, yaw) > edgeY + 1e-9) {
            isBottom = false;
            break;
          }
        }
        if (!isBottom) continue;
        final span = (screenX(a, yaw) - screenX(b, yaw)).abs();
        if (span > bestSpan) {
          bestSpan = span;
          bestYaw = yaw;
        }
      }
    }
    return bestYaw;
  }

  /// Milky inclusions: soft radial glows at fixed 3D anchors inside the
  /// stone (reference: `CHUNK.inclusions.fog`).
  static const List<FogBlob> fogBlobs = [
    FogBlob(Vec3(-0.18, 0.30, 0.10), 0.52, 0.50),
    FogBlob(Vec3(0.28, 0.55, -0.15), 0.38, 0.42),
    FogBlob(Vec3(0.02, 0.15, -0.05), 0.60, 0.34),
  ];

  /// Fracture veils: translucent quads at fixed 3D anchors inside the stone
  /// (reference: `CHUNK.inclusions.veils`).
  static const List<List<Vec3>> veils = [
    [Vec3(-0.55, 0.10, -0.2), Vec3(0.45, 0.28, -0.35), Vec3(0.5, 0.62, 0.1), Vec3(-0.4, 0.5, 0.25)],
    [Vec3(-0.3, 0.55, 0.35), Vec3(0.35, 0.42, 0.3), Vec3(0.2, 0.95, -0.05), Vec3(-0.25, 0.9, 0.0)],
  ];
}

// ---------------------------------------------------------------------------
// 2D convex hull (for the projected silhouette clip path). Port of the
// reference's monotone-chain `convexHull(pts)`.
// ---------------------------------------------------------------------------

double _cross2D(Offset o, Offset a, Offset b) =>
    (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);

List<Offset> _convexHull2D(List<Offset> points) {
  final pts = List<Offset>.of(points)
    ..sort((a, b) => a.dx != b.dx ? a.dx.compareTo(b.dx) : a.dy.compareTo(b.dy));
  if (pts.length < 3) return pts;

  final lower = <Offset>[];
  for (final q in pts) {
    while (lower.length > 1 && _cross2D(lower[lower.length - 2], lower[lower.length - 1], q) <= 0) {
      lower.removeLast();
    }
    lower.add(q);
  }
  final upper = <Offset>[];
  for (final q in pts.reversed) {
    while (upper.length > 1 && _cross2D(upper[upper.length - 2], upper[upper.length - 1], q) <= 0) {
      upper.removeLast();
    }
    upper.add(q);
  }
  lower.removeLast();
  upper.removeLast();
  return [...lower, ...upper];
}

// ---------------------------------------------------------------------------
// Rendering: projection, shading, painter, widget.
// ---------------------------------------------------------------------------

/// A mesh face after projecting its 3 vertices for this frame's rotation.
class _ProjectedFace {
  const _ProjectedFace({required this.screenPoints, required this.normal, required this.depth});

  /// The 3 vertices in screen (canvas-local) coordinates.
  final List<Offset> screenPoints;

  /// Unit camera-space normal, oriented outward (recomputed per frame from
  /// the projected/rotated points, same as the reference -- the mesh's own
  /// outward winding from [hull3D] guarantees this comes out right after
  /// re-deriving it post-rotation).
  final Vec3 normal;

  /// Camera-space depth (z) of the face centroid; smaller sorts first
  /// (farther from the viewer, painted first).
  final double depth;
}

Vec3 _lightVector(double azimuthDegrees) {
  final az = azimuthDegrees * math.pi / 180;
  // +0.62, DELIBERATE DEVIATION from the reference's -0.62: in this
  // projection +y is screen-up, so the reference's negative component lit
  // the stone from *below* -- unnoticeable for a floating gem in the
  // fitting room, but on the desk the brightest facets sat on the bottom
  // rim while the cast shadow claimed a top-right sun (owner report
  // 2026-08-03: "maybe it's how the rendered light is hitting the
  // facets"). Top facets now catch the window light the shadow implies.
  return Vec3(math.sin(az), 0.62, 0.55).normalized;
}

Path _polygonPath(List<Offset> points) {
  final path = Path()..moveTo(points[0].dx, points[0].dy);
  for (var i = 1; i < points.length; i++) {
    path.lineTo(points[i].dx, points[i].dy);
  }
  path.close();
  return path;
}

/// Paints a radial "pool" of light beneath the stone -- used for both the
/// cast shadow and the transmitted-purple-light pool, offset opposite the
/// light direction. Port of the reference's `pool(px, r, col0, col1, squish)`
/// helper: a radial gradient vertically squashed via a save/scale/restore
/// around the draw call (rather than an actually-elliptical gradient shape),
/// exactly as the reference does with a canvas transform.
void _paintPool(
  Canvas canvas, {
  required double centerX,
  required double centerY,
  required double radius,
  required Color innerColor,
  required Color outerColor,
  required double verticalSquish,
}) {
  if (radius <= 0) return; // degenerate layout (e.g. Size.zero) -- nothing to paint
  final center = Offset(centerX, centerY);
  final innerStop = (3.0 / radius).clamp(0.0, 1.0);
  final shader = ui.Gradient.radial(center, radius, [innerColor, outerColor], [innerStop, 1.0]);
  canvas.save();
  canvas.translate(centerX, centerY);
  canvas.scale(1, verticalSquish);
  canvas.translate(-centerX, -centerY);
  canvas.drawCircle(center, radius, Paint()..shader = shader);
  canvas.restore();
}

/// Paints one milky fog-bank inclusion: a 3-stop radial gradient (bright
/// core, softer mid, transparent edge), matching the reference's per-blob
/// `createRadialGradient` with stops at `r*0.1`/`0.6`/`1.0`.
void _paintFogBlob(Canvas canvas, Offset center, double radius, double fogAmount, FogBlob blob) {
  if (radius <= 0) return; // degenerate layout (e.g. Size.zero) -- nothing to paint
  final alpha = (blob.alpha * fogAmount).clamp(0.0, 1.0);
  final colors = [
    HSLColor.fromAHSL(alpha, 274, 0.50, 0.88).toColor(),
    HSLColor.fromAHSL(alpha * 0.45, 272, 0.45, 0.80).toColor(),
    HSLColor.fromAHSL(0, 272, 0.45, 0.80).toColor(),
  ];
  final shader = ui.Gradient.radial(center, radius, colors, const [0.1, 0.6, 1.0]);
  canvas.drawCircle(center, radius, Paint()..shader = shader);
}

/// Normalizes a hue that may have drifted outside `[0, 360)` (the reference
/// passes CSS `hsla()` hues like `272 + n.x*8` straight through -- CSS wraps
/// hue automatically; [HSLColor.fromAHSL] expects it pre-wrapped).
double _wrapHue(double hue) => ((hue % 360) + 360) % 360;

/// Paints the amethyst chunk: the full pipeline from the reference's
/// `draw()`, minus the reference's own page chrome (the kraft-paper
/// background fill and dust specks belong to that standalone demo page, not
/// to one desk object sharing a canvas with other objects -- this painter
/// leaves its background transparent, same as [AmethystChunk] paints nothing
/// outside the stone/pool itself).
///
/// Paints in the reference's exact order: cast shadow + transmitted pool
/// (and, if [isSelected], a soft amber underglow beneath even those) ->
/// back-face interior (dimmed) -> fog/veil inclusions clipped to the
/// projected silhouette -> front faces with lambert+specular shading.
class AmethystChunkPainter extends CustomPainter {
  AmethystChunkPainter({
    required this.rotationY,
    required this.lightAzimuthDegrees,
    required this.inclusions,
    required this.glassiness,
    required this.isSelected,
  });

  /// Yaw around the vertical axis, in radians. Reference: `state.rot`.
  final double rotationY;

  /// See [AmethystChunk.lightAzimuthDegrees].
  final double lightAzimuthDegrees;

  /// `0..1` fraction. Reference: `state.fog / 100`. Owner-approved default
  /// 0.55.
  final double inclusions;

  /// `0..1` fraction. Reference: `state.glass / 100`. Owner-approved default
  /// 0.62. Front-face alpha is `1 - glassiness*0.55`.
  final double glassiness;

  /// Brightens the specular highlight slightly and adds a soft amber
  /// underglow beneath the stone. Deliberately subtler than the cards'
  /// selection treatment (fable-review.md's card glow/border) -- a mineral
  /// doesn't need a border to read as picked up.
  final bool isSelected;

  /// Fixed camera pitch. DELIBERATE DEVIATION from the reference's -0.21:
  /// the fitting-room demo rendered the stone in isolation from a low
  /// oblique angle, but the desk is a flat-lay (cards seen dead-on from
  /// above) and the projection mismatch made the stone read as a hovering
  /// sticker (owner report 2026-08-03). -0.50 shows more top, less side --
  /// closer to the desk's own viewpoint -- which together with the contact
  /// shadow grounds it on the paper.
  static const double _cameraTilt = kAmethystCameraTilt;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    final centerX = width / 2;
    final baseY = height * 0.78;
    final scale = height * 0.42;

    final light = _lightVector(lightAzimuthDegrees);
    final tiltCos = math.cos(_cameraTilt), tiltSin = math.sin(_cameraTilt);
    final yawCos = math.cos(rotationY), yawSin = math.sin(rotationY);

    // Project a model-space point to (screen coordinates, camera-space
    // coordinates) -- mirrors the reference's `project()`, which returns
    // both `{sx,sy}` (screen) and `w` (camera-space, used for depth/normals).
    ({Offset screen, Vec3 cam}) project(Vec3 p) {
      final x1 = p.x * yawCos + p.z * yawSin;
      final z1 = -p.x * yawSin + p.z * yawCos;
      final y2 = p.y * tiltCos - z1 * tiltSin;
      final z2 = p.y * tiltSin + z1 * tiltCos;
      return (screen: Offset(centerX + x1 * scale, baseY - y2 * scale), cam: Vec3(x1, y2, z2));
    }

    final projectedFaces = <_ProjectedFace>[];
    for (final face in AmethystChunkMesh.faces) {
      final a = project(face[0]), b = project(face[1]), c = project(face[2]);
      var normal = (b.cam - a.cam).cross(c.cam - a.cam);
      final centroid = (a.cam + b.cam + c.cam).scaled(1 / 3);
      // Re-orient for camera space exactly as the reference does: a fixed
      // "downward" reference point relative to the centroid, not the mesh's
      // object-space centroid (which the vertices are already wound around
      // from hull3D) -- this second check is about *this frame's* projected
      // normal direction, independent of the winding baked into the mesh.
      final out = Vec3(centroid.x, centroid.y - 0.5, centroid.z);
      if (normal.dot(out) < 0) normal = normal.scaled(-1);
      projectedFaces.add(_ProjectedFace(
        screenPoints: [a.screen, b.screen, c.screen],
        normal: normal.normalized,
        depth: centroid.z,
      ));
    }
    projectedFaces.sort((p, q) => p.depth.compareTo(q.depth));

    final frontFaces = projectedFaces.where((f) => f.normal.z > -0.02);
    final backFaces = projectedFaces.where((f) => f.normal.z <= -0.02);

    // Silhouette + ground-contact geometry, from the *projected* mesh so it
    // stays correct at any rotation/tilt: the contact line is where the
    // stone's lowest screen-space vertices actually are, not a fixed baseY.
    final allScreenPoints = projectedFaces.expand((f) => f.screenPoints).toList(growable: false);
    final hull = _convexHull2D(allScreenPoints);
    var lowestY = double.negativeInfinity;
    for (final p in allScreenPoints) {
      if (p.dy > lowestY) lowestY = p.dy;
    }
    var baseMinX = double.infinity, baseMaxX = double.negativeInfinity;
    for (final p in allScreenPoints) {
      if (p.dy > lowestY - scale * 0.20) {
        if (p.dx < baseMinX) baseMinX = p.dx;
        if (p.dx > baseMaxX) baseMaxX = p.dx;
      }
    }
    final contactCx = (baseMinX + baseMaxX) / 2;
    final contactCy = lowestY - scale * 0.02;

    // --- directional cast shadow + transmitted pool (painted first,
    // beneath everything). The desk story: a window at the top-right
    // (kDeskLightAzimuth), so shadows throw down-left, shaped like the
    // stone itself -- the silhouette projected along the light, each point
    // displaced proportionally to its height above the contact line. Base
    // points stay pinned; the top gets thrown furthest. ---
    final shadowDir = Offset(-light.x, 0.85);

    if (isSelected) {
      // Soft amber underglow, beneath even the shadow/pool -- the whole
      // "brighten specular + underglow" selection treatment stays confined
      // to this one extra pool plus the specular boost below; no border,
      // no outline.
      _paintPool(
        canvas,
        centerX: contactCx,
        centerY: contactCy,
        radius: scale * 1.15,
        innerColor: const Color.fromRGBO(196, 148, 26, 0.22),
        outerColor: const Color.fromRGBO(196, 148, 26, 0),
        verticalSquish: 0.30,
      );
    }

    // Cast shadow: the hull silhouette skewed onto the desk. Height above
    // the contact line becomes displacement along [shadowDir], foreshortened
    // (0.5) so it reads as paper-flat, not a standing mirror image.
    Offset castPoint(Offset p) {
      final heightAboveBase = (contactCy - p.dy).clamp(0.0, double.infinity);
      return Offset(
        p.dx + shadowDir.dx * heightAboveBase * 0.5,
        contactCy + shadowDir.dy * heightAboveBase * 0.5,
      );
    }

    if (hull.length > 2) {
      final castHull = hull.map(castPoint).toList(growable: false);
      final tail = Offset(
        contactCx + shadowDir.dx * scale * 0.9,
        contactCy + shadowDir.dy * scale * 0.9,
      );
      final castPaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(contactCx, contactCy),
          tail,
          // Dark enough to register on the dark kraft, not just on cream
          // cards (owner report: grounding read worse on the corkboard).
          [const Color.fromRGBO(24, 14, 8, 0.52), const Color.fromRGBO(24, 14, 8, 0.06)],
        )
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, scale * 0.035);
      canvas.drawPath(_polygonPath(castHull), castPaint);

      // Transmitted purple: light that came *through* the stone lands inside
      // the very shadow the stone casts.
      _paintPool(
        canvas,
        centerX: contactCx + shadowDir.dx * scale * 0.42,
        centerY: contactCy + shadowDir.dy * scale * 0.42,
        radius: scale * 0.48,
        innerColor: Color.fromRGBO(149, 90, 219, (0.42 + 0.14 * inclusions).clamp(0.0, 1.0)),
        outerColor: const Color.fromRGBO(139, 92, 201, 0),
        verticalSquish: 0.5,
      );
    }
    // Contact shadow: the tight, dark occlusion right where stone meets
    // paper -- the "it is actually resting on something" cue. NOT a
    // bounding-box ellipse (owner report: that pokes out below the base's
    // higher side like an invisible shim). Instead a band that follows the
    // hull's bottom contour: its top edge rides the silhouette and its
    // drop tapers to nothing where the body lifts away from the paper.
    final bandDepth = scale * 0.30;
    final bottomChain = hull.where((p) => p.dy > lowestY - bandDepth).toList()
      ..sort((a, b) => a.dx.compareTo(b.dx));
    if (bottomChain.length >= 2) {
      final contour = Path()..moveTo(bottomChain.first.dx, bottomChain.first.dy + 1);
      for (final p in bottomChain.skip(1)) {
        contour.lineTo(p.dx, p.dy + 1);
      }
      for (final p in bottomChain.reversed) {
        final closeness = (1 - (lowestY - p.dy) / bandDepth).clamp(0.0, 1.0);
        contour.lineTo(p.dx, p.dy + 1 + scale * 0.12 * closeness);
      }
      contour.close();
      canvas.drawPath(
        contour,
        Paint()
          ..color = const Color.fromRGBO(18, 10, 6, 0.52)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, scale * 0.045),
      );
    }

    // --- back faces: dimmed interior ---
    for (final f in backFaces) {
      final lambert = math.max(0.0, f.normal.dot(light));
      final lightness = (0.12 + lambert * 0.18).clamp(0.0, 1.0);
      final path = _polygonPath(f.screenPoints);
      canvas.drawPath(path, Paint()..color = HSLColor.fromAHSL(0.85, 270, 0.38, lightness).toColor());
    }

    // --- fog/veils, clipped to the projected silhouette (hull computed
    // above, alongside the contact-shadow geometry) ---
    if (hull.length > 2 && inclusions > 0) {
      canvas.save();
      canvas.clipPath(_polygonPath(hull));

      for (final veil in AmethystChunkMesh.veils) {
        final screenPts = veil.map((v) => project(v).screen).toList(growable: false);
        final path = _polygonPath(screenPts);
        canvas.drawPath(
          path,
          Paint()..color = HSLColor.fromAHSL((0.16 * inclusions + 0.04).clamp(0.0, 1.0), 276, 0.45, 0.84).toColor(),
        );
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = HSLColor.fromAHSL((0.22 * inclusions).clamp(0.0, 1.0), 280, 0.60, 0.90).toColor(),
        );
      }

      for (final blob in AmethystChunkMesh.fogBlobs) {
        final center = project(blob.center).screen;
        _paintFogBlob(canvas, center, blob.radius * scale, inclusions, blob);
      }

      canvas.restore();
    }

    // --- front faces: lambert + specular shading ---
    final faceAlpha = (1 - glassiness * 0.55).clamp(0.0, 1.0);
    final specularBoost = isSelected ? 1.15 : 1.0;
    for (final f in frontFaces) {
      final lambert = math.max(0.0, f.normal.dot(light));
      // Reflection vector's z-component: since `light` and `f.normal` are
      // both unit vectors, this stays in [-1, 1], so `spec` below stays in
      // [0, 1] with no clamping needed (matches the reference's assumption).
      final reflectZ = light.z - 2 * lambert * f.normal.z;
      final spec = math.pow(math.max(0.0, -reflectZ), 18).toDouble() * specularBoost;

      final hue = _wrapHue(272 + f.normal.x * 8);
      final saturation = (0.42 + lambert * 0.18).clamp(0.0, 1.0);
      final lightness = (0.20 + lambert * 0.44 + spec * 0.22).clamp(0.0, 1.0);
      final path = _polygonPath(f.screenPoints);
      canvas.drawPath(path, Paint()..color = HSLColor.fromAHSL(faceAlpha, hue, saturation, lightness).toColor());

      final strokeLightness = (0.60 + spec * 0.30).clamp(0.0, 1.0);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = HSLColor.fromAHSL(0.28, 280, 0.60, strokeLightness).toColor(),
      );
    }
  }

  @override
  bool shouldRepaint(AmethystChunkPainter oldDelegate) =>
      oldDelegate.rotationY != rotationY ||
      oldDelegate.lightAzimuthDegrees != lightAzimuthDegrees ||
      oldDelegate.inclusions != inclusions ||
      oldDelegate.glassiness != glassiness ||
      oldDelegate.isSelected != isSelected;
}

/// The amethyst chunk desk object -- a raw, squat crystal built as the
/// convex hull of a seeded point cloud (seed 23, 18 points; see
/// [AmethystChunkMesh]), rendered with a hand-rolled projection/shading
/// pipeline ([AmethystChunkPainter]). See this file's top doc comment for
/// the reference prototype this is ported from.
///
/// NOTE ON PAINTING OUTSIDE [size]: the cast shadow/pool sits just below the
/// stone's silhouette and can extend a little past the bottom edge of
/// [size] (same as the reference's own canvas layout gives the pool room
/// below `baseY`). [CustomPaint] itself never clips a painter's drawing to
/// its `size` (Flutter's `RenderCustomPaint` paints unclipped), and the
/// parent `SpatialCanvas`'s entity `Stack` is built with `clipBehavior:
/// Clip.none` (see `lib/src/spatial_canvas.dart`'s class doc comment) --
/// between those two facts, the pool's slight overflow paints exactly as
/// intended instead of being cut off.
class AmethystChunk extends StatelessWidget {
  const AmethystChunk({
    super.key,
    this.size = const Size(150, 120),
    this.lightAzimuthDegrees = kDeskLightAzimuth,
    this.inclusions = 0.55,
    this.glassiness = 0.62,
    this.isSelected = false,
    this.rotationY = 0.15,
  });

  /// Visual size of the widget. Matches [AmethystChunk]'s entity size on the
  /// desk (`example/lib/mock_spatial_data_source.dart`'s `AmethystEntity`).
  final Size size;

  /// Direction of the single light source, in degrees -- matches the
  /// reference's `light` slider (range roughly `-60..60`; positive rotates
  /// the light toward stage right). Owner-approved default: 9.0.
  ///
  /// This is a widget parameter (not a literal baked into the painter) even
  /// though nothing in this POC varies it per-object yet, *because* of
  /// where it's headed: DRAG_DROP_CANVAS_MVP_PLAN.md's Phase 5 gives the
  /// desk one real global light wash that every light-aware object
  /// (including the cards) will sample, instead of each object hardcoding
  /// its own copy of the constant the way this example currently does with
  /// [kDeskLightAzimuth]. Keeping it a parameter now means that later wiring
  /// is a call-site change (read the shared light state and pass it here)
  /// rather than a signature change to this widget.
  final double lightAzimuthDegrees;

  /// Inclusions (fog banks + fracture veils) opacity, `0..1`. Owner-approved
  /// default 0.55.
  final double inclusions;

  /// Facet glassiness, `0..1` -- higher lets more of the interior ghost
  /// through the front facets (front-face alpha is `1 - glassiness*0.55`).
  /// Owner-approved default 0.62.
  final double glassiness;

  /// Whether the canvas currently has this entity selected. See
  /// [AmethystChunkPainter]'s class doc comment for the (deliberately
  /// subtle) visual treatment.
  final bool isSelected;

  /// Fixed yaw around the vertical axis, in radians. The reference exposes
  /// this as a live drag-to-rotate gesture; this POC's `AmethystEntity`
  /// instead keeps one fixed pose forever (no rotation gesture wired up for
  /// desk objects yet), so this is just the pose to render.
  final double rotationY;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: size,
      painter: AmethystChunkPainter(
        rotationY: rotationY,
        lightAzimuthDegrees: lightAzimuthDegrees,
        inclusions: inclusions,
        glassiness: glassiness,
        isSelected: isSelected,
      ),
    );
  }
}
