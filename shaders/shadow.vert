// Depth-only pass: renders scene geometry from the light's point of view
// for a shadow map. Reuses the same interleaved vertex buffer as the main
// UnlitVertex pass (position, texture_coords, normal), so it declares the
// same attribute layout even though only position is used.
uniform ShadowDrawInfo {
  // model * light_view_projection
  mat4 light_mvp;
}
shadow_draw_info;

in vec3 position;
in vec2 texture_coords;
in vec3 normal;

void main() {
  gl_Position = shadow_draw_info.light_mvp * vec4(position, 1.0);
}
