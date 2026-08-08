import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pin_and_paper_canvas/spatial_canvas.dart';

void main() {
  testWidgets('stacks contact + cast shadow layers under the color pass', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: DachshundFigurine(size: Size(128, 128))),
      ),
    );

    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images, hasLength(3));
    final names = [
      for (final img in images) (img.image as AssetImage).assetName,
    ];
    expect(names, const [
      'assets/desk_objects/dachshund/three_q_left_cast.png',
      'assets/desk_objects/dachshund/three_q_left_contact.png',
      'assets/desk_objects/dachshund/three_q_left_color.png',
    ]);
    for (final img in images) {
      expect((img.image as AssetImage).package, 'pin_and_paper_canvas');
    }

    // Shadow layers composite at the rig's ~40%; the color pass is full.
    final opacities = tester.widgetList<Opacity>(find.byType(Opacity)).toList();
    expect(opacities, hasLength(2));
    for (final o in opacities) {
      expect(o.opacity, kDachshundShadowOpacity);
    }
  });

  testWidgets('every rotation stop resolves its own sprite set', (tester) async {
    for (final stop in DachshundStop.values) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: DachshundFigurine(size: const Size(96, 96), stop: stop),
        ),
      );
      final names = [
        for (final img in tester.widgetList<Image>(find.byType(Image)))
          (img.image as AssetImage).assetName,
      ];
      expect(names, [
        'assets/desk_objects/dachshund/${stop.assetStem}_cast.png',
        'assets/desk_objects/dachshund/${stop.assetStem}_contact.png',
        'assets/desk_objects/dachshund/${stop.assetStem}_color.png',
      ]);
    }
  });

  test('double-tap cycle walks all seven stops and wraps', () {
    var stop = DachshundStop.threeQLeft;
    final seen = <DachshundStop>{};
    for (var i = 0; i < DachshundStop.values.length; i++) {
      seen.add(stop);
      stop = stop.next;
    }
    expect(seen, DachshundStop.values.toSet());
    expect(stop, DachshundStop.threeQLeft); // full circle
    expect(DachshundStop.topDown.next, DachshundStop.threeQLeft);
  });

  testWidgets('selection applies the brighten filter', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: DachshundFigurine(size: Size(128, 128), isSelected: true),
      ),
    );
    expect(find.byType(ColorFiltered), findsOneWidget);
  });
}
