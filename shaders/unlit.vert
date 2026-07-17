uniform VertInfo {
  mat4 mvp;
  vec4 color;
}
vert_info;

in vec2 position;
out vec4 v_color;

void main() {
  v_color = vert_info.color;
  gl_Position = vert_info.mvp * vec4(position, 0.0, 1.0);
}
