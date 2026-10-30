//! PNG loader and image pre-processing for zqr-cli.
//! Uses isolated C99 libpng wrapper in c/png_read.c to decode images into
//! 8-bit grayscale pixels, and applies area-averaging downscaling if max(w, h) > 1024.

const std = @import("std");
const cli_options = @import("cli_options");

extern "c" fn zqr_png_read_gray8(
    png_data: [*]const u8,
    png_len: usize,
    out_pixels: *?[*]u8,
    out_width: *usize,
    out_height: *usize,
) c_int;

extern "c" fn zqr_png_free(pixels: ?[*]u8) void;

pub const LoadedImage = struct {
    pixels: []u8,
    width: usize,
    height: usize,
    allocator: ?std.mem.Allocator = null,

    pub fn deinit(self: *LoadedImage) void {
        if (self.allocator) |alloc| {
            alloc.free(self.pixels);
        } else {
            zqr_png_free(self.pixels.ptr);
        }
    }
};

pub const LoadError = error{
    NotPng,
    ImageTooLarge,
    OutOfMemory,
    PngDecodeFailed,
    PngNotSupported,
};

/// Loads PNG bytes from memory into 8-bit grayscale pixels.
pub fn loadPng(raw_bytes: []const u8) LoadError!LoadedImage {
    if (!cli_options.enable_png) {
        return error.PngNotSupported;
    }

    var out_ptr: ?[*]u8 = null;
    var w: usize = 0;
    var h: usize = 0;

    const rc = zqr_png_read_gray8(raw_bytes.ptr, raw_bytes.len, &out_ptr, &w, &h);
    if (rc != 0) {
        return switch (rc) {
            -2 => error.NotPng,
            -3 => error.ImageTooLarge,
            -4 => error.OutOfMemory,
            else => error.PngDecodeFailed,
        };
    }

    const ptr = out_ptr orelse return error.PngDecodeFailed;
    return LoadedImage{
        .pixels = ptr[0 .. w * h],
        .width = w,
        .height = h,
        .allocator = null,
    };
}

/// Downscales images exceeding 1024x1024 to fit proportionally within 1024x1024
/// using area box averaging. Box averaging preserves module contrast and edges.
pub fn downscaleIfNeeded(allocator: std.mem.Allocator, img: *LoadedImage) !void {
    if (img.width <= 1024 and img.height <= 1024) {
        return;
    }

    const scale_w: f64 = 1024.0 / @as(f64, @floatFromInt(img.width));
    const scale_h: f64 = 1024.0 / @as(f64, @floatFromInt(img.height));
    const scale: f64 = @min(scale_w, scale_h);

    const new_w: usize = @max(1, @as(usize, @intFromFloat(@round(@as(f64, @floatFromInt(img.width)) * scale))));
    const new_h: usize = @max(1, @as(usize, @intFromFloat(@round(@as(f64, @floatFromInt(img.height)) * scale))));

    const new_pixels = try allocator.alloc(u8, new_w * new_h);
    errdefer allocator.free(new_pixels);

    var dy: usize = 0;
    while (dy < new_h) : (dy += 1) {
        const sy0 = (dy * img.height) / new_h;
        const sy1 = @max(sy0 + 1, ((dy + 1) * img.height) / new_h);

        var dx: usize = 0;
        while (dx < new_w) : (dx += 1) {
            const sx0 = (dx * img.width) / new_w;
            const sx1 = @max(sx0 + 1, ((dx + 1) * img.width) / new_w);

            var sum: u64 = 0;
            var count: u64 = 0;
            var sy = sy0;
            while (sy < sy1) : (sy += 1) {
                var sx = sx0;
                while (sx < sx1) : (sx += 1) {
                    sum += img.pixels[sy * img.width + sx];
                    count += 1;
                }
            }
            new_pixels[dy * new_w + dx] = @intCast(sum / count);
        }
    }

    // Release old pixels and update img in-place
    img.deinit();
    img.pixels = new_pixels;
    img.width = new_w;
    img.height = new_h;
    img.allocator = allocator;
}
