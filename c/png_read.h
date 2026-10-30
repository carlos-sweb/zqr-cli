#ifndef ZQR_PNG_READ_H
#define ZQR_PNG_READ_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Decodes PNG raw bytes from memory into an 8-bit grayscale pixel buffer.
 *
 * Handles:
 *  - 1, 2, 4, 8, 16 bit grayscale (expanded/stripped to 8-bit)
 *  - Indexed / palette images (expanded to RGB, converted to grayscale)
 *  - RGB / RGBA (converted to grayscale using standard luminance weights: 0.299 R + 0.587 G + 0.114 B)
 *  - Alpha transparency (composited against white background: 255)
 *
 * Parameters:
 *  - png_data: pointer to PNG file buffer in memory
 *  - png_len: size of png_data in bytes
 *  - out_pixels: receives pointer to malloc'd buffer containing width * height grayscale bytes
 *  - out_width: receives image width in pixels
 *  - out_height: receives image height in pixels
 *
 * Returns:
 *   0 on success
 *  -1 on libpng decode error
 *  -2 if data does not match PNG signature
 *  -3 on invalid dimensions (e.g. 0 or > 16.8 MP)
 *  -4 on out of memory
 */
int zqr_png_read_gray8(
    const uint8_t *png_data,
    size_t png_len,
    uint8_t **out_pixels,
    size_t *out_width,
    size_t *out_height
);

void zqr_png_free(uint8_t *pixels);

#ifdef __cplusplus
}
#endif

#endif /* ZQR_PNG_READ_H */
