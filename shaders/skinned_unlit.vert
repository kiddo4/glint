// Skinned counterpart to unlit.vert, paired with the same UnlitFragment —
// skinning only changes vertex position/normal, so no fragment-shader
// changes are needed. Kept as a separate shader (not a branch in
// unlit.vert) so static geometry — the majority of any scene — never pays
// the per-vertex joint-blend cost.
uniform SkinnedDrawInfo {
  mat4 mvp;
  mat4 model;
  vec4 base_color;
  // x: metallic, y: roughness
  vec4 material;
  // Column-major joint matrices, already combined with each joint's
  // inverse bind matrix and expressed relative to this mesh's own node
  // space — see GlintGlbRig.jointMatrices.
  mat4 joint_matrices[64];
}
draw_info;

in vec3 position;
in vec2 texture_coords;
in vec3 normal;
// Up to 4 joint influences per vertex. Indices are floats (cast to int
// below) — no integer-typed vertex attribute is used elsewhere in this
// engine's Flutter GPU usage, so this stays consistent with the rest of
// the vertex format instead of introducing an unverified attribute type.
in vec4 joint_indices;
in vec4 joint_weights;
out vec2 v_texture_coords;
out vec3 v_normal;
out vec4 v_base_color;
out vec4 v_material;
out vec3 v_world_position;

void main() {
  mat4 skin_matrix =
      joint_weights.x * draw_info.joint_matrices[int(joint_indices.x)] +
      joint_weights.y * draw_info.joint_matrices[int(joint_indices.y)] +
      joint_weights.z * draw_info.joint_matrices[int(joint_indices.z)] +
      joint_weights.w * draw_info.joint_matrices[int(joint_indices.w)];
  vec4 skinned_position = skin_matrix * vec4(position, 1.0);
  vec3 skinned_normal = mat3(skin_matrix) * normal;

  v_texture_coords = texture_coords;
  v_normal = normalize(mat3(draw_info.model) * skinned_normal);
  v_base_color = draw_info.base_color;
  v_material = draw_info.material;
  v_world_position = (draw_info.model * skinned_position).xyz;
  gl_Position = draw_info.mvp * skinned_position;
}
