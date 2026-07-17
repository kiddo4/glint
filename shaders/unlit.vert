uniform VertInfo {
  mat4 mvp;
  vec4 color;
}
vert_info;

in vec3 position;
in vec2 texture_coords;
out vec2 v_texture_coords;
out vec4 v_color;

void main() {
  v_texture_coords = texture_coords;
  v_color = vert_info.color;
  gl_Position = vert_info.mvp * vec4(position, 1.0);
}
