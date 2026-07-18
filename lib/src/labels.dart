import 'package:flutter/widgets.dart';

import 'math.dart';

/// What happens to a [Label3D] when the model blocks its anchor.
enum Label3DOcclusion {
  /// Fade to [Label3D.fadedOpacity] but stay readable.
  fade,

  /// Disappear entirely and stop receiving pointer events.
  hide,

  /// Stay fully visible regardless of the model.
  none,
}

/// A Flutter widget pinned to a point on a rendered model.
///
/// The [anchor] lives in the model's own coordinate space — the same space
/// [GlintRayHit.position] reports, so tapping the model is a practical way
/// to author anchors. Each frame the anchor is projected to screen space and
/// the [child] is centered there; when the model itself blocks the line of
/// sight from the camera to the anchor, [occlusion] decides its fate.
class Label3D {
  const Label3D({
    required this.anchor,
    required this.child,
    this.occlusion = Label3DOcclusion.fade,
    this.fadedOpacity = .25,
    this.offset = Offset.zero,
  });

  final Vector3 anchor;
  final Widget child;
  final Label3DOcclusion occlusion;

  /// Opacity while occluded under [Label3DOcclusion.fade].
  final double fadedOpacity;

  /// Screen-space nudge in logical pixels, applied after projection.
  final Offset offset;
}
