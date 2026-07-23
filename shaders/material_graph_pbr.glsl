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

// GGX diffuse+specular contribution from one light arriving along [l] with
// the given (already attenuated) linear [radiance]. Shared by the
// directional key light and every punctual light below.
vec3 shade_direct(vec3 n, vec3 v, vec3 l, vec3 albedo, float metallic,
    float roughness, vec3 radiance) {
  vec3 h = normalize(v + l);
  float n_dot_l = max(dot(n, l), 0.0);
  float n_dot_v = max(dot(n, v), 0.0);
  vec3 f0 = mix(vec3(0.04), albedo, metallic);
  vec3 f = fresnel_schlick(max(dot(h, v), 0.0), f0);
  float ndf = distribution_ggx(n, h, roughness);
  float geometry = geometry_schlick_ggx(n_dot_v, roughness) *
      geometry_schlick_ggx(n_dot_l, roughness);
  vec3 specular = (ndf * geometry * f) /
      max(4.0 * n_dot_v * n_dot_l, 0.0001);
  vec3 diffuse = (vec3(1.0) - f) * (1.0 - metallic) * albedo / PI;
  return (diffuse + specular) * radiance * n_dot_l;
}

// glTF KHR_lights_punctual windowed inverse-square attenuation: full
// inverse-square with no cutoff when range is 0, otherwise smoothly zeroed
// out by the light's range.
float range_attenuation(float distance, float range) {
  if (range <= 0.0) return 1.0 / max(distance * distance, 0.0001);
  return clamp(1.0 - pow(distance / range, 4.0), 0.0, 1.0) /
      max(distance * distance, 0.0001);
}

// How much of the directional light reaches [world_position]: 1.0 in full
// light, a fractional value in shadow (not 0, so shadowed surfaces still
// read ambient/IBL rather than going flat black). Points outside the
// shadow frustum are treated as unshadowed rather than clamped dark, since
// "off the edge of the shadow map" isn't the same claim as "occluded".
// shadow_map's red channel holds window-space depth written directly by
// the shadow pass's fragment shader (gl_FragCoord.z) — a plain color
// texture, not a sampled depth+stencil attachment.
float directional_shadow(vec3 world_position, float n_dot_l) {
  vec4 light_clip = frame_info.shadow_view_projection * vec4(world_position, 1.0);
  vec3 light_ndc = light_clip.xyz / light_clip.w;
  vec3 shadow_uv = light_ndc * 0.5 + 0.5;
  if (shadow_uv.x < 0.0 || shadow_uv.x > 1.0 || shadow_uv.y < 0.0 ||
      shadow_uv.y > 1.0 || shadow_uv.z < 0.0 || shadow_uv.z > 1.0) {
    return 1.0;
  }
  // Slope-scaled bias: surfaces closer to grazing the light need a larger
  // bias to avoid self-shadowing acne.
  float bias = max(0.0025 * (1.0 - n_dot_l), 0.0006);
  float occluder_depth = texture(shadow_map, shadow_uv.xy).r;
  return shadow_uv.z - bias > occluder_depth ? 0.35 : 1.0;
}

void main() {
  GlintGraphSurface surface = glint_graph_surface();
  // Graph base colors follow texture authoring conventions (sRGB); authored
  // glTF factors are already linear when packed by Glint.
  vec3 sampled_linear = pow(clamp(surface.base_color.rgb, 0.0, 1.0), vec3(2.2));
  vec4 albedo = vec4(v_base_color.rgb * sampled_linear,
      v_base_color.a * surface.base_color.a * surface.opacity);
  float roughness = clamp(surface.roughness, 0.04, 1.0);
  float metallic = clamp(surface.metallic, 0.0, 1.0);
  vec3 n = normalize(surface.normal);
  vec3 v = normalize(frame_info.camera_position.xyz - v_world_position);
  vec3 l = normalize(-frame_info.light_direction.xyz);
  float directional_n_dot_l = max(dot(n, l), 0.0);
  vec3 direct = shade_direct(
      n, v, l, albedo.rgb, metallic, roughness, vec3(frame_info.lighting.y));
  if (frame_info.lighting.w > 0.5) {
    direct *= directional_shadow(v_world_position, directional_n_dot_l);
  }

  // Fresnel term for the ambient/IBL branch below, reusing the directional
  // key light's half-vector the same way the original single-light shader
  // did — an approximation, but keeps ambient response the way it shipped.
  vec3 f0 = mix(vec3(0.04), albedo.rgb, metallic);
  vec3 f = fresnel_schlick(
      max(dot(normalize(v + l), v), 0.0), f0);

  int punctual_count = int(frame_info.lighting.z);
  for (int i = 0; i < MAX_PUNCTUAL_LIGHTS; i++) {
    if (i >= punctual_count) break;
    vec3 light_position = frame_info.punctual_position_range[i].xyz;
    float range = frame_info.punctual_position_range[i].w;
    vec3 light_color = frame_info.punctual_color_intensity[i].rgb;
    float intensity = frame_info.punctual_color_intensity[i].w;
    vec3 to_light = light_position - v_world_position;
    float light_distance = length(to_light);
    vec3 light_dir = to_light / max(light_distance, 0.0001);

    float is_spot = frame_info.punctual_inner_cos_flags[i].y;
    float cone_attenuation = 1.0;
    if (is_spot > 0.5) {
      vec3 spot_direction =
          normalize(frame_info.punctual_direction_outer_cos[i].xyz);
      float outer_cos = frame_info.punctual_direction_outer_cos[i].w;
      float inner_cos = frame_info.punctual_inner_cos_flags[i].x;
      float cos_angle = dot(-light_dir, spot_direction);
      cone_attenuation = clamp(
          (cos_angle - outer_cos) / max(inner_cos - outer_cos, 0.0001),
          0.0, 1.0);
    }

    vec3 radiance = light_color * intensity *
        range_attenuation(light_distance, range) * cone_attenuation;
    direct += shade_direct(
        n, v, light_dir, albedo.rgb, metallic, roughness, radiance);
  }

  vec3 ambient;
  if (frame_info.light_direction.w > 0.001) {
    // Image-based lighting: cosine-convolved irradiance for diffuse plus
    // roughness-matched prefiltered radiance for specular reflections.
    vec3 irradiance = decode_rgbm(texture(irradiance_map, equirect_uv(n)));
    vec3 diffuse_ibl = irradiance * albedo.rgb * (1.0 - f) * (1.0 - metallic);
    vec3 reflected = reflect(-v, n);
    vec2 brdf = environment_brdf(max(dot(n, v), 0.0), roughness);
    vec3 specular_ibl =
        sample_radiance(reflected, roughness) * (f0 * brdf.x + brdf.y);
    ambient = (diffuse_ibl + specular_ibl) * frame_info.light_direction.w;
  } else {
    // Hemisphere ambient: full strength for up-facing normals fading toward
    // the underside, so surfaces away from the key light still read as
    // curved form instead of flattening under a constant fill.
    float sky = 0.5 + 0.5 * n.y;
    ambient = albedo.rgb * frame_info.lighting.x * mix(0.3, 1.0, sky);
  }
  vec3 color = ambient + direct + surface.emissive;
  // Linear distance fog toward the horizon color; starts at 45% of the end
  // distance so the play area stays crisp while depth melts away.
  if (frame_info.fog.w > 0.0) {
    float distance_to_camera =
        length(v_world_position - frame_info.camera_position.xyz);
    float fog_factor = clamp(
        (distance_to_camera - frame_info.fog.w * 0.45) /
            (frame_info.fog.w * 0.55),
        0.0, 1.0);
    color = mix(color, frame_info.fog.rgb, fog_factor);
  }
  color = pow(clamp(color, 0.0, 1.0), vec3(1.0 / 2.2));
  frag_color = vec4(color, albedo.a);
}
