// Per-draw-call data: changes every mesh/submesh. Frame-scoped data
// (lights, camera, fog) lives in FrameInfo, declared and read directly by
// the fragment shader instead of forwarded through varyings — Metal caps
// interpolated fragment inputs at 60 components, and the punctual light
// array alone would need 64.
uniform DrawInfo {
  mat4 mvp;
  mat4 model;
  vec4 base_color;
  // x: metallic, y: roughness
  vec4 material;
}
draw_info;

in vec3 position;
in vec2 texture_coords;
in vec3 normal;
out vec2 v_texture_coords;
out vec3 v_normal;
out vec4 v_base_color;
out vec4 v_material;
out vec3 v_world_position;

void main() {
  v_texture_coords = texture_coords;
  v_normal = normalize(mat3(draw_info.model) * normal);
  v_base_color = draw_info.base_color;
  v_material = draw_info.material;
  v_world_position = (draw_info.model * vec4(position, 1.0)).xyz;
  gl_Position = draw_info.mvp * vec4(position, 1.0);
}
