# glint_box3d

The high-performance Box3D backend for Glint's general-purpose physics API.
It provides real angular rigid bodies, CCD, sleeping, compound and cooked
colliders, five joint families, collision/trigger events, spatial queries,
fixed-step interpolation, and query filters that can exclude individual
bodies.

```dart
await GlintBox3dWorld.ensureInitialized();
final world = GlintBox3dWorld(fixedTimeStep: 1 / 120);
final body = world.createBody(
  const GlintRigidBodyConfig(position: Vector3(0, 3, 0)),
);
body.addCollider(
  const GlintBoxCollider(Vector3(.5, .5, .5)),
  material: const GlintPhysicsMaterial(density: 100),
);
```

`GlintRaycastVehicle` lives in `glint_engine`, consumes only the portable
contract, and is optional. The backend itself is suitable for any 3D game or
interactive simulation.
