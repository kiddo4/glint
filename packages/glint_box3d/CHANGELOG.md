# Changelog

## 0.1.0

* Add the native Box3D backend for Glint's portable 3D physics contract.
* Honor full Glint query filters during native single-hit shape casts, enabling
  self-excluding character sweeps without genre-specific backend code.
* Publish persistent core contact state and fixed-step profiling through the
  shared physics-world infrastructure.
* Wake dynamic bodies after explicit transform changes so teleports invalidate
  stale sleeping contacts on the following native step.
* Support angular rigid bodies, compound/cooked colliders, joints, CCD,
  sleeping, events, spatial queries, filtering, interpolation, snapshots,
  deterministic replay verification, and stress workloads.
