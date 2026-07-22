import 'package:vector_math/vector_math.dart' as vm;

import '../math.dart';

/// Fixed pixel size of the shadow depth texture, independent of viewport
/// size. 1024 balances shadow crispness against the cost of an extra
/// full-scene depth pass every frame.
const kShadowMapSize = 1024;

/// The light-space view-projection matrix for a directional-light shadow
/// map: an orthographic frustum centered on [boundsCenter] with a half-size
/// of [radius] in every direction, looking along [lightDirection].
///
/// Shared by both GPU renderers ([boundsCenter]/[radius] mean different
/// things per renderer — the model's own bounds in the single-model
/// viewer, the camera's position and a fixed shadow distance in the game
/// loop — but the matrix construction is identical either way).
vm.Matrix4 directionalLightViewProjection({
  required Vector3 lightDirection,
  required Vector3 boundsCenter,
  required double radius,
}) {
  final direction = lightDirection.normalized;
  // Placed well outside the bounds so the whole shadow-casting volume sits
  // safely between the ortho frustum's near and far planes.
  final distance = radius * 2;
  final eye = vm.Vector3(
    boundsCenter.x - direction.x * distance,
    boundsCenter.y - direction.y * distance,
    boundsCenter.z - direction.z * distance,
  );
  final target = vm.Vector3(boundsCenter.x, boundsCenter.y, boundsCenter.z);
  // A light pointing (near-)straight up/down makes the default up vector
  // parallel to the view direction, which degenerates makeViewMatrix.
  final up = direction.y.abs() > .99
      ? vm.Vector3(0, 0, 1)
      : vm.Vector3(0, 1, 0);
  final view = vm.makeViewMatrix(eye, target, up);
  final projection = vm.makeOrthographicMatrix(
    -radius,
    radius,
    -radius,
    radius,
    .01,
    radius * 4,
  );
  return projection * view as vm.Matrix4;
}
