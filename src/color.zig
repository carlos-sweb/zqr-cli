const std = @import("std");

/// Parses a hex color string into a 32-bit RGBA value.
/// Supported formats:
/// - "#RRGGBB" (alpha defaults to 0xFF)
/// - "#RRGGBBAA"
pub fn parseHexColor(input: []const u8) !u32 {
    if (!std.mem.startsWith(u8, input, "#")) {
        return error.InvalidColorFormat;
    }
    const raw = input[1..];

    if (raw.len == 6) {
        const rgb = std.fmt.parseInt(u24, raw, 16) catch return error.InvalidColorFormat;
        const r: u32 = (rgb >> 16) & 0xFF;
        const g: u32 = (rgb >> 8) & 0xFF;
        const b: u32 = rgb & 0xFF;
        return (r << 24) | (g << 16) | (b << 8) | 0xFF;
    } else if (raw.len == 8) {
        return std.fmt.parseInt(u32, raw, 16) catch return error.InvalidColorFormat;
    } else {
        return error.InvalidColorFormat;
    }
}

test "parseHexColor valid formats" {
    const testing = std.testing;
    try testing.expectEqual(@as(u32, 0x000000FF), try parseHexColor("#000000"));
    try testing.expectEqual(@as(u32, 0xFFFFFFFF), try parseHexColor("#FFFFFF"));
    try testing.expectEqual(@as(u32, 0x11223344), try parseHexColor("#11223344"));
}

test "parseHexColor invalid formats" {
    const testing = std.testing;
    try testing.expectError(error.InvalidColorFormat, parseHexColor("123456"));
    try testing.expectError(error.InvalidColorFormat, parseHexColor("#123"));
    try testing.expectError(error.InvalidColorFormat, parseHexColor("blue"));
    try testing.expectError(error.InvalidColorFormat, parseHexColor("#GGFFFF"));
}
