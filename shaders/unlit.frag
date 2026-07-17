uniform sampler2D tex;

in vec2 v_texture_coords;
in vec3 v_normal;
in vec4 v_base_color;
in vec4 v_lighting;
in vec3 v_light_direction;
in vec3 v_world_position;
in vec3 v_camera_position;
out vec4 frag_color;

const float PI = 3.14159265359;

float distribution_ggx(vec3 n, vec3 h, float roughness) {
  float a = roughness * roughness;
  float a2 = a * a;
  float n_dot_h = max(dot(n, h), 0.0);
  float denominator = n_dot_h * n_dot_h * (a2 - 1.0) + 1.0;
  return a2 / max(PI * denominator * denominator, 0.0001);
}

float geometry_schlick_ggx(float n_dot_v, float roughness) {
  float r = roughness + 1.0;
  float k = (r * r) / 8.0;
  return n_dot_v / max(n_dot_v * (1.0 - k) + k, 0.0001);
}

vec3 fresnel_schlick(float cos_theta, vec3 f0) {
  return f0 + (1.0 - f0) * pow(1.0 - cos_theta, 5.0);
}

void main() {
  vec4 sampled = texture(tex, v_texture_coords);
  // glTF base-color textures are authored in sRGB. Flutter GPU's host-visible
  // texture is unorm, so decode it explicitly before doing PBR lighting.
  vec3 sampled_linear = pow(sampled.rgb, vec3(2.2));
  vec4 albedo = vec4(v_base_color.rgb * sampled_linear,
      v_base_color.a * sampled.a);
  float roughness = clamp(v_lighting.w, 0.04, 1.0);
  float metallic = clamp(v_lighting.z, 0.0, 1.0);
  vec3 n = normalize(v_normal);
  vec3 v = normalize(v_camera_position - v_world_position);
  vec3 l = normalize(-v_light_direction);
  vec3 h = normalize(v + l);
  float n_dot_l = max(dot(n, l), 0.0);
  float n_dot_v = max(dot(n, v), 0.0);
  vec3 f0 = mix(vec3(0.04), albedo.rgb, metallic);
  vec3 f = fresnel_schlick(max(dot(h, v), 0.0), f0);
  float ndf = distribution_ggx(n, h, roughness);
  float geometry = geometry_schlick_ggx(n_dot_v, roughness) *
      geometry_schlick_ggx(n_dot_l, roughness);
  vec3 specular = (ndf * geometry * f) /
      max(4.0 * n_dot_v * n_dot_l, 0.0001);
  vec3 diffuse = (vec3(1.0) - f) * (1.0 - metallic) * albedo.rgb / PI;
  vec3 direct = (diffuse + specular) * v_lighting.y * n_dot_l;
  vec3 ambient = albedo.rgb * v_lighting.x;
  vec3 color = ambient + direct;
  // Filmic exposure keeps bright yellow saturated without clipping highlights.
  color = vec3(1.0) - exp(-color * 1.35);
  color = pow(color, vec3(1.0 / 2.2));
  frag_color = vec4(color, albedo.a);
}
