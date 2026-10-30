#include "png_read.h"
#include <png.h>
#include <setjmp.h>
#include <stdlib.h>
#include <string.h>

struct png_mem_src {
    const uint8_t *data;
    size_t len;
    size_t offset;
};

static void png_mem_read(png_structp png_ptr, png_bytep out_bytes, png_size_t length) {
    struct png_mem_src *src = (struct png_mem_src *)png_get_io_ptr(png_ptr);
    if (!src || !src->data || src->offset + length > src->len) {
        png_error(png_ptr, "unexpected end of PNG buffer");
    }
    memcpy(out_bytes, src->data + src->offset, length);
    src->offset += length;
}

static void png_silent_error(png_structp png_ptr, png_const_charp error_msg) {
    (void)error_msg;
    longjmp(png_jmpbuf(png_ptr), 1);
}

static void png_silent_warning(png_structp png_ptr, png_const_charp warning_msg) {
    (void)png_ptr;
    (void)warning_msg;
}

int zqr_png_read_gray8(
    const uint8_t *png_data,
    size_t png_len,
    uint8_t **out_pixels,
    size_t *out_width,
    size_t *out_height
) {
    if (!png_data || png_len < 8 || !out_pixels || !out_width || !out_height) {
        return -1;
    }
    *out_pixels = NULL;
    *out_width = 0;
    *out_height = 0;

    if (png_sig_cmp((png_const_bytep)png_data, 0, 8) != 0) {
        return -2;
    }

    struct png_mem_src src = {
        .data = png_data,
        .len = png_len,
        .offset = 8,
    };

    png_structp png_ptr = png_create_read_struct(PNG_LIBPNG_VER_STRING, NULL, png_silent_error, png_silent_warning);
    if (!png_ptr) return -1;

    png_infop info_ptr = png_create_info_struct(png_ptr);
    if (!info_ptr) {
        png_destroy_read_struct(&png_ptr, NULL, NULL);
        return -1;
    }

    uint8_t *pixels = NULL;
    png_bytep *row_pointers = NULL;

    if (setjmp(png_jmpbuf(png_ptr))) {
        if (row_pointers) free(row_pointers);
        if (pixels) free(pixels);
        png_destroy_read_struct(&png_ptr, &info_ptr, NULL);
        return -1;
    }

    png_set_read_fn(png_ptr, &src, png_mem_read);
    png_set_sig_bytes(png_ptr, 8);

    png_read_info(png_ptr, info_ptr);

    png_uint_32 width = 0;
    png_uint_32 height = 0;
    int bit_depth = 0;
    int color_type = 0;

    png_get_IHDR(png_ptr, info_ptr, &width, &height, &bit_depth, &color_type, NULL, NULL, NULL);

    if (width == 0 || height == 0 || (uint64_t)width * (uint64_t)height > 16843008) {
        png_destroy_read_struct(&png_ptr, &info_ptr, NULL);
        return -3;
    }

    // 1. Strip 16-bit to 8-bit
    if (bit_depth == 16) {
        png_set_strip_16(png_ptr);
    }

    // 2. Expand paletted images to RGB
    if (color_type == PNG_COLOR_TYPE_PALETTE) {
        png_set_palette_to_rgb(png_ptr);
    }

    // 3. Expand low-bit grayscale (< 8 bit) to 8 bit
    if (color_type == PNG_COLOR_TYPE_GRAY && bit_depth < 8) {
        png_set_expand_gray_1_2_4_to_8(png_ptr);
    }

    // 4. Handle transparency: composite on white
    if (png_get_valid(png_ptr, info_ptr, PNG_INFO_tRNS)) {
        png_set_tRNS_to_alpha(png_ptr);
    }

    if ((color_type & PNG_COLOR_MASK_ALPHA) || png_get_valid(png_ptr, info_ptr, PNG_INFO_tRNS)) {
        png_color_16 my_background = { .gray = 255, .red = 255, .green = 255, .blue = 255 };
        png_set_background(png_ptr, &my_background, PNG_BACKGROUND_GAMMA_SCREEN, 0, 1.0);
    }

    // 5. Convert RGB/RGBA to grayscale using standard ITU-R BT.601 coefficients
    if (color_type & PNG_COLOR_MASK_COLOR) {
        png_set_rgb_to_gray(png_ptr, PNG_ERROR_ACTION_NONE, -1.0, -1.0);
    }

    // 6. Ensure alpha channel is stripped if background didn't remove it
    png_set_strip_alpha(png_ptr);

    png_read_update_info(png_ptr, info_ptr);

    size_t rowbytes = png_get_rowbytes(png_ptr, info_ptr);

    size_t total_bytes = (size_t)width * (size_t)height;
    pixels = (uint8_t *)malloc(total_bytes);
    if (!pixels) {
        png_destroy_read_struct(&png_ptr, &info_ptr, NULL);
        return -4;
    }

    row_pointers = (png_bytep *)malloc(sizeof(png_bytep) * height);
    if (!row_pointers) {
        free(pixels);
        png_destroy_read_struct(&png_ptr, &info_ptr, NULL);
        return -4;
    }

    if (rowbytes == width) {
        for (png_uint_32 y = 0; y < height; y++) {
            row_pointers[y] = pixels + (size_t)y * width;
        }
        png_read_image(png_ptr, row_pointers);
    } else {
        // Fallback for padded row stride
        uint8_t *temp_row = (uint8_t *)malloc(rowbytes);
        if (!temp_row) {
            free(row_pointers);
            free(pixels);
            png_destroy_read_struct(&png_ptr, &info_ptr, NULL);
            return -4;
        }
        for (png_uint_32 y = 0; y < height; y++) {
            png_read_row(png_ptr, temp_row, NULL);
            memcpy(pixels + (size_t)y * width, temp_row, width);
        }
        free(temp_row);
    }

    png_read_end(png_ptr, NULL);

    free(row_pointers);
    row_pointers = NULL;

    png_destroy_read_struct(&png_ptr, &info_ptr, NULL);

    *out_pixels = pixels;
    *out_width = width;
    *out_height = height;
    return 0;
}

void zqr_png_free(uint8_t *pixels) {
    if (pixels) free(pixels);
}
