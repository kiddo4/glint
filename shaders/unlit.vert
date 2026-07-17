uniform VertInfo {
  mat4 mvp;
  vec4 color;
}
vert_info;

in vec3 position;
out vec4 v_color;

void main() {
  vec3 tint = vec3(0.72 + position.y * 0.12, 0.42 + position.x * 0.08, 0.05);
  v_color = vec4(tint, 1.0) * vert_info.color;
  gl_Position = vert_info.mvp * vec4(position, 1.0);
}
