uniform VertInfo {
  mat4 mvp;
  mat4 model;
  vec4 base_color;
  vec4 light_direction;
  vec4 lighting;
  vec4 camera_position;
  // rgb: linear fog color; w: fog end distance, 0 disables fog.
  vec4 fog;
}
vert_info;

in vec3 position;
in vec2 texture_coords;
in vec3 normal;
out vec2 v_texture_coords;
out vec3 v_normal;
out vec4 v_base_color;
out vec4 v_lighting;
out vec3 v_light_direction;
out float v_environment;
out vec3 v_world_position;
out vec3 v_camera_position;
out vec4 v_fog;

void main() {
  v_texture_coords = texture_coords;
  v_normal = normalize(mat3(vert_info.model) * normal);
  v_base_color = vert_info.base_color;
  v_lighting = vert_info.lighting;
  v_light_direction = normalize(vert_info.light_direction.xyz);
  v_environment = vert_info.light_direction.w;
  v_fog = vert_info.fog;
  v_world_position = (vert_info.model * vec4(position, 1.0)).xyz;
  v_camera_position = vert_info.camera_position.xyz;
  gl_Position = vert_info.mvp * vec4(position, 1.0);
}
