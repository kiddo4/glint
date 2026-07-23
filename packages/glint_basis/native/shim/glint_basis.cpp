#include "glint_basis.h"

#include <limits>
#include <mutex>
#include <string>

#include "basisu_transcoder.h"

namespace {

thread_local std::string g_error;
std::once_flag g_init_once;

int32_t fail(int32_t code, const char* message) {
  g_error = message;
  return code;
}

bool valid_input(const uint8_t* data, size_t data_size) {
  return data != nullptr && data_size > 0 &&
         data_size <= std::numeric_limits<uint32_t>::max();
}

void ensure_initialized() {
  std::call_once(g_init_once, [] { basist::basisu_transcoder_init(); });
}

}  // namespace

extern "C" {

int32_t glint_basis_ktx2_info(
    const uint8_t* data, size_t data_size, uint32_t* out_info) {
  if (!valid_input(data, data_size) || out_info == nullptr) {
    return fail(1, "Invalid KTX2 input or output pointer.");
  }
  ensure_initialized();
  basist::ktx2_transcoder transcoder;
  if (!transcoder.init(data, static_cast<uint32_t>(data_size))) {
    return fail(2, "Basis Universal rejected the KTX2 container.");
  }
  out_info[0] = transcoder.get_width();
  out_info[1] = transcoder.get_height();
  out_info[2] = transcoder.get_levels();
  out_info[3] = transcoder.is_srgb() ? 1u : 0u;
  out_info[4] = transcoder.is_hdr() ? 1u : 0u;
  g_error.clear();
  return 0;
}

int32_t glint_basis_ktx2_transcode_rgba8(
    const uint8_t* data, size_t data_size, uint32_t level,
    uint8_t* output, size_t output_size) {
  if (!valid_input(data, data_size) || output == nullptr) {
    return fail(1, "Invalid KTX2 input or output pointer.");
  }
  ensure_initialized();
  basist::ktx2_transcoder transcoder;
  if (!transcoder.init(data, static_cast<uint32_t>(data_size))) {
    return fail(2, "Basis Universal rejected the KTX2 container.");
  }
  if (transcoder.is_hdr()) {
    return fail(3, "HDR Basis textures cannot be transcoded to RGBA8.");
  }
  if (level >= transcoder.get_levels()) {
    return fail(4, "KTX2 mip level is out of range.");
  }
  basist::ktx2_image_level_info info;
  if (!transcoder.get_image_level_info(info, level, 0, 0)) {
    return fail(5, "Unable to inspect the requested KTX2 mip level.");
  }
  const size_t required = static_cast<size_t>(info.m_orig_width) *
                          static_cast<size_t>(info.m_orig_height) * 4u;
  if (output_size < required) {
    return fail(6, "RGBA8 output buffer is too small.");
  }
  if (!transcoder.start_transcoding()) {
    return fail(7, "Unable to start KTX2 transcoding.");
  }
  const uint32_t pixels = info.m_orig_width * info.m_orig_height;
  if (!transcoder.transcode_image_level(
          level, 0, 0, output, pixels,
          basist::transcoder_texture_format::cTFRGBA32)) {
    return fail(8, "KTX2 to RGBA8 transcoding failed.");
  }
  g_error.clear();
  return 0;
}

int32_t glint_basis_file_info(
    const uint8_t* data, size_t data_size, uint32_t* out_info) {
  if (!valid_input(data, data_size) || out_info == nullptr) {
    return fail(1, "Invalid Basis input or output pointer.");
  }
  ensure_initialized();
  basist::basisu_transcoder transcoder;
  const uint32_t size = static_cast<uint32_t>(data_size);
  if (!transcoder.validate_header(data, size)) {
    return fail(2, "Basis Universal rejected the file header.");
  }
  basist::basisu_image_level_info level_info;
  if (!transcoder.get_image_level_info(data, size, level_info, 0, 0)) {
    return fail(5, "Unable to inspect the Basis image.");
  }
  out_info[0] = level_info.m_orig_width;
  out_info[1] = level_info.m_orig_height;
  out_info[2] = transcoder.get_total_image_levels(data, size, 0);
  out_info[3] = 1u;
  out_info[4] = basist::basis_tex_format_is_hdr(
                    transcoder.get_basis_tex_format(data, size))
                    ? 1u
                    : 0u;
  g_error.clear();
  return 0;
}

int32_t glint_basis_file_transcode_rgba8(
    const uint8_t* data, size_t data_size, uint32_t level,
    uint8_t* output, size_t output_size) {
  if (!valid_input(data, data_size) || output == nullptr) {
    return fail(1, "Invalid Basis input or output pointer.");
  }
  ensure_initialized();
  basist::basisu_transcoder transcoder;
  const uint32_t size = static_cast<uint32_t>(data_size);
  const uint32_t levels = transcoder.get_total_image_levels(data, size, 0);
  if (levels == 0 || level >= levels) {
    return fail(4, "Basis mip level is out of range.");
  }
  if (basist::basis_tex_format_is_hdr(
          transcoder.get_basis_tex_format(data, size))) {
    return fail(3, "HDR Basis textures cannot be transcoded to RGBA8.");
  }
  basist::basisu_image_level_info info;
  if (!transcoder.get_image_level_info(data, size, info, 0, level)) {
    return fail(5, "Unable to inspect the requested Basis mip level.");
  }
  const size_t required = static_cast<size_t>(info.m_orig_width) *
                          static_cast<size_t>(info.m_orig_height) * 4u;
  if (output_size < required) {
    return fail(6, "RGBA8 output buffer is too small.");
  }
  if (!transcoder.start_transcoding(data, size)) {
    return fail(7, "Unable to start Basis transcoding.");
  }
  const uint32_t pixels = info.m_orig_width * info.m_orig_height;
  if (!transcoder.transcode_image_level(
          data, size, 0, level, output, pixels,
          basist::transcoder_texture_format::cTFRGBA32)) {
    return fail(8, "Basis to RGBA8 transcoding failed.");
  }
  g_error.clear();
  return 0;
}

const char* glint_basis_last_error(void) { return g_error.c_str(); }

}  // extern "C"

