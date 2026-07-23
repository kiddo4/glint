#ifndef GLINT_BASIS_H_
#define GLINT_BASIS_H_

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#define GLINT_BASIS_EXPORT __declspec(dllexport)
#else
#define GLINT_BASIS_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// out_info: width, height, level_count, is_srgb, is_hdr.
GLINT_BASIS_EXPORT int32_t glint_basis_ktx2_info(
    const uint8_t* data, size_t data_size, uint32_t* out_info);
GLINT_BASIS_EXPORT int32_t glint_basis_ktx2_transcode_rgba8(
    const uint8_t* data, size_t data_size, uint32_t level,
    uint8_t* output, size_t output_size);

GLINT_BASIS_EXPORT int32_t glint_basis_file_info(
    const uint8_t* data, size_t data_size, uint32_t* out_info);
GLINT_BASIS_EXPORT int32_t glint_basis_file_transcode_rgba8(
    const uint8_t* data, size_t data_size, uint32_t level,
    uint8_t* output, size_t output_size);

GLINT_BASIS_EXPORT const char* glint_basis_last_error(void);

#ifdef __cplusplus
}
#endif

#endif

