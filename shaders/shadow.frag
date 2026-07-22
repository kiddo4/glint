// Writes window-space depth into the color attachment's red channel so it
// can be sampled downstream as a plain color texture (the same shape as
// the engine's existing irradiance/radiance sampling) instead of trying to
// read back a native depth+stencil texture, which isn't reliably
// sample-able as sampler2D in a later pass on this Flutter GPU version.
// The pass also has a transient depth attachment backing the depth test
// during rasterization here, but nothing ever samples that texture —
// only this manually-written value is read later.
out vec4 frag_color;

void main() {
  frag_color = vec4(gl_FragCoord.z, 0.0, 0.0, 1.0);
}
