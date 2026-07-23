#define MAX_PUNCTUAL_LIGHTS 8

uniform sampler2D tex;
uniform sampler2D irradiance_map;
uniform sampler2D radiance_map;
uniform sampler2D shadow_map;

uniform FrameInfo {
  vec4 light_direction;
  vec4 lighting;
  vec4 camera_position;
  vec4 fog;
  mat4 shadow_view_projection;
  vec4 punctual_position_range[MAX_PUNCTUAL_LIGHTS];
  vec4 punctual_color_intensity[MAX_PUNCTUAL_LIGHTS];
  vec4 punctual_direction_outer_cos[MAX_PUNCTUAL_LIGHTS];
  vec4 punctual_inner_cos_flags[MAX_PUNCTUAL_LIGHTS];
}
frame_info;

uniform GraphMaterialInfo {
  // x: engine time in seconds; yzw reserved for future frame values.
  vec4 runtime;
  vec4 parameters[16];
}
graph_info;

in vec2 v_texture_coords;
in vec3 v_normal;
in vec4 v_base_color;
in vec4 v_material;
in vec3 v_world_position;
out vec4 frag_color;

struct GlintGraphSurface {
  vec4 base_color;
  float opacity;
  vec3 emissive;
  float metallic;
  float roughness;
  vec3 normal;
};

float glint_saturate(float value) { return clamp(value, 0.0, 1.0); }
vec2 glint_saturate(vec2 value) { return clamp(value, 0.0, 1.0); }
vec3 glint_saturate(vec3 value) { return clamp(value, 0.0, 1.0); }
vec4 glint_saturate(vec4 value) { return clamp(value, 0.0, 1.0); }

float glint_noise2d(vec2 point) {
  vec2 cell = floor(point);
  vec2 local = fract(point);
  local = local * local * (3.0 - 2.0 * local);
  float a = fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
  float b = fract(sin(dot(cell + vec2(1.0, 0.0),
      vec2(127.1, 311.7))) * 43758.5453);
  float c = fract(sin(dot(cell + vec2(0.0, 1.0),
      vec2(127.1, 311.7))) * 43758.5453);
  float d = fract(sin(dot(cell + vec2(1.0, 1.0),
      vec2(127.1, 311.7))) * 43758.5453);
  return mix(mix(a, b, local.x), mix(c, d, local.x), local.y);
}

