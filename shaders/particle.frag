uniform sampler2D particle_texture;

in vec2 v_texture_coords;
in vec4 v_color;
out vec4 frag_color;

void main() {
  vec4 sampled = texture(particle_texture, v_texture_coords);
  vec3 linear_color = pow(sampled.rgb, vec3(2.2)) * v_color.rgb;
  frag_color = vec4(
      pow(clamp(linear_color, 0.0, 1.0), vec3(1.0 / 2.2)),
      sampled.a * v_color.a);
}

