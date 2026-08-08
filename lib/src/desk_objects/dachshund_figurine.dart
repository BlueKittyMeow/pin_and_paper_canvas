import 'package:flutter/widgets.dart';

/// Opacity for the prerendered shadow layers. The render rig ships them
/// full-alpha and expects the app to composite at ~40% (camera_stops.json
/// `softness_decision`, per the accepted notebook show-off) — and to vary
/// this later for time-of-day light without re-rendering the sprites.
const double kDachshundShadowOpacity = 0.40;

/// The figurine's seven prerendered rotation stops — the preset strip from
/// the owner's desk mockups (Top-Down 0°, 3/4 L/R ±45°, Front L/R ±60°,
/// Front 90°, Back 180°), authored as the shared camera rig
/// (agentic-blender-props config/camera_stops.json).
enum DachshundStop {
  threeQLeft('three_q_left'),
  frontLeft('front_left'),
  front('front'),
  back('back'),
  frontRight('front_right'),
  threeQRight('three_q_right'),
  topDown('top_down');

  const DachshundStop(this.assetStem);

  /// Basename prefix of this stop's sprite files.
  final String assetStem;

  /// The next stop in the double-tap turntable cycle. Declaration order IS
  /// the cycle: a sweep of the side views by yaw (45° → 60° → 90° → 180° →
  /// 300° → 315°), then the top-down oddball, then around again.
  DachshundStop get next => DachshundStop.values[(index + 1) % DachshundStop.values.length];
}

/// The seven turntable stops are the SHARED camera rig for every sprite
/// desk object (dachshund, gems, whatever comes next) — the enum predates
/// the second resident, hence the breed-specific name. New code should
/// prefer this alias.
typedef SpriteStop = DachshundStop;

/// The marble longhaired dachshund figurine (asset `dachshund-v1-approved`,
/// owner-accepted 2026-08-04) as a desk object: three stacked prerendered
/// sprite layers per rotation stop — contact shadow, cast shadow (both
/// composited at [kDachshundShadowOpacity]), then the neutral-lit color
/// pass on top.
///
/// The layers are same-frame renders (one square ortho camera per stop), so
/// stacking them in one square box keeps them registered at any display
/// size. The frame is the WIDENED final_v2 one (1.75× final_v1's): the sun's
/// ~46° elevation throws the cast shadow roughly a body length past the
/// dog, so the frame is mostly breathing room for it — the dog himself
/// occupies only the central ~40%. Color ships at the 1344px master for
/// crispness under canvas zoom; the soft shadow blobs ship at 448px —
/// resolution they don't need. Neutral
/// lighting is deliberate (style bible): global tint/softness for
/// time-of-day arrives as a runtime layer, never baked into sprites. Light
/// direction matches the desk sun ([kDeskLightAzimuth], top-right → shadows
/// fall down-left) — baked into the renders, so every stop stays valid all
/// day.
///
/// Selection brightens the marble slightly — same philosophy as the
/// amethyst's specular boost: a figurine doesn't need a border to read as
/// picked up, and painting glow on the ground would fight the very shadows
/// that seat it on the desk.
class DachshundFigurine extends StatelessWidget {
  const DachshundFigurine({
    super.key,
    required this.size,
    this.stop = DachshundStop.threeQLeft,
    this.isSelected = false,
  });

  /// Display box (square: the sprite frames are square). Per the bundle
  /// manifest's `ppm_multiplier: 2` tiny-prop exception, true desk scale is
  /// HALF the render's px/m — with the widened 0.224 m frame, a
  /// 224-logical-px box shows the real 9 cm figurine at the desk's scale...
  /// but on this desk, size is ultimately whatever sparks joy (resize
  /// chips, like the amethyst).
  final Size size;

  /// Which prerendered rotation stop to show.
  final DachshundStop stop;

  final bool isSelected;

  /// Mild uniform brighten for the selected state (RGB × 1.12, alpha
  /// untouched).
  static const ColorFilter _selectedBrighten = ColorFilter.matrix(<double>[
    1.12, 0, 0, 0, 0, //
    0, 1.12, 0, 0, 0, //
    0, 0, 1.12, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);

  Widget _layer(String layer, {double opacity = 1.0}) {
    final image = Image.asset(
      'assets/desk_objects/dachshund/${stop.assetStem}_$layer.png',
      package: 'pin_and_paper_canvas',
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
    );
    return opacity == 1.0 ? image : Opacity(opacity: opacity, child: image);
  }

  @override
  Widget build(BuildContext context) {
    Widget color = _layer('color');
    if (isSelected) {
      color = ColorFiltered(colorFilter: _selectedBrighten, child: color);
    }
    return SizedBox.fromSize(
      size: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _layer('cast', opacity: kDachshundShadowOpacity),
          _layer('contact', opacity: kDachshundShadowOpacity),
          color,
        ],
      ),
    );
  }
}
