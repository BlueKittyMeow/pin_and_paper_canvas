// Pure-math coverage for amethyst_chunk.dart's mesh generation: the seeded
// RNG, the point cloud, and the convex hull -- independent of Flutter's
// rendering pipeline (no CustomPainter/Canvas involved here; see
// amethyst_chunk_painter_test.dart for that).

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pin_and_paper_canvas_example/crystal/amethyst_chunk.dart';

void main() {
  group('Mulberry32', () {
    test('seed 23 matches the JS reference bit-exactly for the first 10 outputs', () {
      // Hand-computed by running the reference's own mulberry32(23) in
      // Node.js (crystal-shapes.html's <script>, unmodified) and recording
      // its first 10 outputs -- this is the ground truth this port must
      // reproduce exactly, not just "close enough".
      const expected = [
        0.09272266505286098,
        0.06831189128570259,
        0.6321120406500995,
        0.30546968476846814,
        0.32397183775901794,
        0.214271740289405,
        0.5120620620436966,
        0.9534339555539191,
        0.8260409280192107,
        0.008935947669669986,
      ];
      final rnd = Mulberry32(23);
      for (final value in expected) {
        expect(rnd.next(), value, reason: 'mulberry32(23) must be bit-exact with the JS reference');
      }
    });

    test('is deterministic: two instances with the same seed produce the same sequence', () {
      final a = Mulberry32(7);
      final b = Mulberry32(7);
      for (var i = 0; i < 20; i++) {
        expect(a.next(), b.next());
      }
    });

    test('different seeds diverge', () {
      final a = Mulberry32(23);
      final b = Mulberry32(24);
      expect(a.next(), isNot(b.next()));
    });
  });

  group('chunkCloud', () {
    test('produces the requested point count, sitting on y >= 0', () {
      final pts = chunkCloud(23, 18);
      expect(pts, hasLength(18));
      // "Shifted to sit on y=0": the lowest point's y is exactly 0 (by
      // construction -- every point had the cloud's minY subtracted), and no
      // point should have negative y afterward.
      expect(pts.map((p) => p.y).reduce((a, b) => a < b ? a : b), closeTo(0, 1e-12));
      for (final p in pts) {
        expect(p.y, greaterThanOrEqualTo(-1e-12));
      }
    });

    test('is deterministic for a given seed', () {
      final a = chunkCloud(23, 18);
      final b = chunkCloud(23, 18);
      for (var i = 0; i < a.length; i++) {
        expect(a[i].x, b[i].x);
        expect(a[i].y, b[i].y);
        expect(a[i].z, b[i].z);
      }
    });
  });

  group('hull3D properties (the "no bites" guarantee)', () {
    // Exercise the general function directly (not just the one baked mesh)
    // with the exact seed/n the mesh uses, and cross-check against a second,
    // odder seed/n to make sure these properties are structural, not
    // incidental to seed 23's particular point layout.
    for (final config in [(seed: 23, n: 18), (seed: 5, n: 12)]) {
      test('seed=${config.seed} n=${config.n}: every point lies on or inside every face plane', () {
        final pts = chunkCloud(config.seed, config.n);
        final faces = hull3D(pts);
        expect(faces, isNotEmpty);

        // Looser than hull3D's own internal 1e-9 epsilon: this checks the
        // *result*, which can accumulate a little more floating-point noise
        // than the single dot-product comparisons the algorithm itself
        // makes internally.
        const eps = 1e-6;
        for (final face in faces) {
          final a = face[0], b = face[1], c = face[2];
          final normal = (b - a).cross(c - a);
          for (final p in pts) {
            final d = (p - a).dot(normal);
            expect(
              d,
              lessThanOrEqualTo(eps),
              reason: 'point $p lies outside face plane through $a/$b/$c -- the hull would have a bite taken out of it',
            );
          }
        }
      });

      test('seed=${config.seed} n=${config.n}: every face normal points away from the centroid', () {
        final pts = chunkCloud(config.seed, config.n);
        final faces = hull3D(pts);

        var centroid = const Vec3(0, 0, 0);
        for (final p in pts) {
          centroid += p;
        }
        centroid = centroid.scaled(1 / pts.length);

        for (final face in faces) {
          final a = face[0], b = face[1], c = face[2];
          final normal = (b - a).cross(c - a);
          final towardCentroid = (centroid - a).dot(normal);
          expect(towardCentroid, lessThan(0), reason: 'face normal is not outward-oriented');
        }
      });
    }
  });

  group('AmethystChunkMesh (the baked seed-23 mesh used by the painter)', () {
    test('computes a well-formed faceted mesh for seed 23, n=18', () {
      // The pre-flat-cut mesh was cross-checked at exactly 32 faces against
      // the JS reference's hull3D(chunkCloud(23,18)) in Node.js. The flat
      // base cut (owner decision 2026-08-03) deliberately deviates from the
      // reference, so the count is asserted as a sane range rather than a
      // reference-pinned constant; the hull-property tests above remain the
      // real correctness guarantee.
      expect(AmethystChunkMesh.faces.length, greaterThanOrEqualTo(28));
      expect(AmethystChunkMesh.faces.length, lessThanOrEqualTo(80));
      for (final face in AmethystChunkMesh.faces) {
        expect(face, hasLength(3));
      }
    });

    test('baseAlignedYaw: the bottom screen edge is horizontal and wide', () {
      // Re-derive screen y for base vertices with the painter's projection
      // (same formulas, same kAmethystCameraTilt) at the aligned yaw: the
      // two lowest-projecting base vertices must tie exactly (horizontal
      // bottom edge, parallel to the card edges) and span a real width.
      final yaw = AmethystChunkMesh.baseAlignedYaw;
      final seen = <String>{};
      final base = <Vec3>[
        for (final f in AmethystChunkMesh.faces)
          for (final v in f)
            if (v.y == 0 && seen.add('${v.x},${v.z}')) v,
      ];
      double screenY(Vec3 v) {
        final z1 = -v.x * math.sin(yaw) + v.z * math.cos(yaw);
        return -(v.y * math.cos(kAmethystCameraTilt) - z1 * math.sin(kAmethystCameraTilt));
      }

      double screenX(Vec3 v) => v.x * math.cos(yaw) + v.z * math.sin(yaw);

      final lowest = base.map(screenY).reduce(math.max);
      final bottom = base.where((v) => (screenY(v) - lowest).abs() < 1e-9).toList();
      expect(bottom.length, greaterThanOrEqualTo(2),
          reason: 'an edge (two vertices), not a single point, must rest lowest');
      final xs = bottom.map(screenX).toList()..sort();
      expect(xs.last - xs.first, greaterThan(0.25),
          reason: 'the resting edge should be a real base, not a sliver');
    });

    test('flat-cut base: at least four vertices sit exactly on y=0', () {
      // The cut plane guarantees a stable planar base so the stone sits
      // flat on the desk -- no vertex may dip below it either.
      final vertices = AmethystChunkMesh.faces.expand((f) => f).toList();
      final onPlane = vertices.where((v) => v.y == 0).map((v) => '${v.x},${v.z}').toSet();
      expect(onPlane.length, greaterThanOrEqualTo(4));
      for (final v in vertices) {
        expect(v.y, greaterThanOrEqualTo(0));
      }
    });

    test('is computed once and cached -- repeated access returns the identical list', () {
      final first = AmethystChunkMesh.faces;
      final second = AmethystChunkMesh.faces;
      expect(identical(first, second), isTrue);
    });

    test('carries the reference\'s exact inclusion anchors', () {
      expect(AmethystChunkMesh.fogBlobs, hasLength(3));
      expect(AmethystChunkMesh.veils, hasLength(2));
      expect(AmethystChunkMesh.veils[0], hasLength(4));
    });
  });
}
