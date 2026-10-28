const std = @import("std");
const zqr = @import("zqr");
const QrMatrix = zqr.QrMatrix;

/// Helper to test if a module is dark (1) at padded coordinates (including quiet zone).
fn isModuleDark(matrix: QrMatrix, qz: usize, px: usize, py: usize) bool {
    const size: usize = matrix.size;
    if (px < qz or px >= qz + size or py < qz or py >= qz + size) {
        return false; // quiet zone is light
    }
    const mx = px - qz;
    const my = py - qz;
    return matrix.modules[my * size + mx] == 1;
}

/// Renders a QrMatrix as high-contrast ANSI text using Unicode half-blocks (▀ U+2580).
/// Combines two vertical modules into each character cell for a 1:1 aspect ratio.
/// Uses explicit ANSI colors (black on bright white) to ensure reliable scanning
/// across both dark and light terminal color schemes.
pub fn renderAnsi(writer: anytype, matrix: QrMatrix, quiet_zone: u8) !void {
    const qz: usize = quiet_zone;
    const size: usize = matrix.size;
    const dim: usize = size + 2 * qz;

    var y: usize = 0;
    while (y < dim) : (y += 2) {
        var x: usize = 0;
        while (x < dim) : (x += 1) {
            const top_dark = isModuleDark(matrix, qz, x, y);
            const bot_dark = if (y + 1 < dim) isModuleDark(matrix, qz, x, y + 1) else false;

            if (top_dark and bot_dark) {
                // Both black
                try writer.writeAll("\x1b[30;40m▀\x1b[0m");
            } else if (!top_dark and !bot_dark) {
                // Both white
                try writer.writeAll("\x1b[97;107m▀\x1b[0m");
            } else if (top_dark and !bot_dark) {
                // Top black, bottom white
                try writer.writeAll("\x1b[30;107m▀\x1b[0m");
            } else {
                // Top white, bottom black
                try writer.writeAll("\x1b[97;40m▀\x1b[0m");
            }
        }
        try writer.writeAll("\n");
    }
}

/// Renders a QrMatrix as plain ASCII text using "##" for dark modules and "  " for light modules.
/// No ANSI escape sequences are used.
pub fn renderAscii(writer: anytype, matrix: QrMatrix, quiet_zone: u8) !void {
    const qz: usize = quiet_zone;
    const size: usize = matrix.size;
    const dim: usize = size + 2 * qz;

    var y: usize = 0;
    while (y < dim) : (y += 1) {
        var x: usize = 0;
        while (x < dim) : (x += 1) {
            if (isModuleDark(matrix, qz, x, y)) {
                try writer.writeAll("##");
            } else {
                try writer.writeAll("  ");
            }
        }
        try writer.writeAll("\n");
    }
}

test "renderAscii line count and character content" {
    const mods = [_]u8{ 1, 0, 0, 1 };
    const m = QrMatrix{
        .version = 1,
        .size = 2,
        .ecc = .low,
        .mask = 0,
        .mode = .byte,
        .modules = &mods,
    };

    var buf: [512]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);
    try renderAscii(&writer, m, 1);

    const out = writer.buffered();
    // dim = 2 + 2*1 = 4. 4 lines of 4*2 = 8 chars + '\n' = 9 chars * 4 = 36 bytes.
    try std.testing.expectEqual(@as(usize, 36), out.len);
}
