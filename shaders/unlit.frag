uniform sampler2D tex;
uniform sampler2D irradiance_map;
uniform sampler2D radiance_map;

in vec2 v_texture_coords;
in vec3 v_normal;
in vec4 v_base_color;
in vec4 v_lighting;
in vec3 v_light_direction;
in float v_environment;
in vec3 v_world_position;
in vec3 v_camera_position;
in vec4 v_fog;
out vec4 frag_color;

const float PI = 3.14159265359;
// Must match GlintEnvironment's atlas layout and RGBM range.
const float RADIANCE_LEVELS = 5.0;
const float RGBM_RANGE = 6.0;

vec3 decode_rgbm(vec4 encoded) {
  return encoded.rgb * encoded.a * RGBM_RANGE;
}

vec2 equirect_uv(vec3 direction) {
  return vec2(atan(direction.z, direction.x) / (2.0 * PI) + 0.5,
      acos(clamp(direction.y, -1.0, 1.0)) / PI);
}

// Samples the vertically stacked blur bands, interpolating by roughness.
vec3 sample_radiance(vec3 direction, float roughness) {
  vec2 uv = equirect_uv(direction);
  float level = roughness * (RADIANCE_LEVELS - 1.0);
  float lower = floor(level);
  float upper = min(lower + 1.0, RADIANCE_LEVELS - 1.0);
  // Inset by half a band texel so filtering never bleeds across bands.
  float inset = 0.5 / 64.0;
  float band_v = clamp(uv.y, inset, 1.0 - inset);
  vec3 a = decode_rgbm(texture(radiance_map,
      vec2(uv.x, (lower + band_v) / RADIANCE_LEVELS)));
  vec3 b = decode_rgbm(texture(radiance_map,
      vec2(uv.x, (upper + band_v) / RADIANCE_LEVELS)));
  return mix(a, b, level - lower);
}

// Lazarov's analytic environment BRDF approximation (no lookup table).
vec2 environment_brdf(float n_dot_v, float roughness) {
  vec4 c0 = vec4(-1.0, -0.0275, -0.572, 0.022);
  vec4 c1 = vec4(1.0, 0.0425, 1.04, -0.04);
  vec4 r = roughness * c0 + c1;
  float a004 = min(r.x * r.x, exp2(-9.28 * n_dot_v)) * r.x + r.y;
  return vec2(-1.04, 1.04) * a004 + r.zw;
}

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
  vec3 ambient;
  if (v_environment > 0.001) {
    // Image-based lighting: cosine-convolved irradiance for diffuse plus
    // roughness-matched prefiltered radiance for specular reflections.
    vec3 irradiance = decode_rgbm(texture(irradiance_map, equirect_uv(n)));
    vec3 diffuse_ibl = irradiance * albedo.rgb * (1.0 - f) * (1.0 - metallic);
    vec3 reflected = reflect(-v, n);
    vec2 brdf = environment_brdf(n_dot_v, roughness);
    vec3 specular_ibl =
        sample_radiance(reflected, roughness) * (f0 * brdf.x + brdf.y);
    ambient = (diffuse_ibl + specular_ibl) * v_environment;
  } else {
    // Hemisphere ambient: full strength for up-facing normals fading toward
    // the underside, so surfaces away from the key light still read as
    // curved form instead of flattening under a constant fill.
    float sky = 0.5 + 0.5 * n.y;
    ambient = albedo.rgb * v_lighting.x * mix(0.3, 1.0, sky);
  }
  vec3 color = ambient + direct;
  // Linear distance fog toward the horizon color; starts at 45% of the end
  // distance so the play area stays crisp while depth melts away.
  if (v_fog.w > 0.0) {
    float distance_to_camera = length(v_world_position - v_camera_position);
    float fog_factor = clamp(
        (distance_to_camera - v_fog.w * 0.45) / (v_fog.w * 0.55), 0.0, 1.0);
    color = mix(color, v_fog.rgb, fog_factor);
  }
  color = pow(clamp(color, 0.0, 1.0), vec3(1.0 / 2.2));
  frag_color = vec4(color, albedo.a);
}
