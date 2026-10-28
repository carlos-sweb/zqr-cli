const std = @import("std");
const zqr = @import("zqr");
const color = @import("color.zig");
const io_util = @import("io_util.zig");
const cmd_encode = @import("cmd_encode.zig");
const render_terminal = @import("render_terminal.zig");

test "color parser: #RRGGBB and #RRGGBBAA" {
    const testing = std.testing;

    // Standard 6-digit hex (#RRGGBB -> default AA=0xFF)
    const c1 = try color.parseHexColor("#000000");
    try testing.expectEqual(@as(u32, 0x000000FF), c1);

    const c2 = try color.parseHexColor("#FFFFFF");
    try testing.expectEqual(@as(u32, 0xFFFFFFFF), c2);

    const c3 = try color.parseHexColor("#112233");
    try testing.expectEqual(@as(u32, 0x112233FF), c3);

    // 8-digit hex with custom alpha
    const c4 = try color.parseHexColor("#11223380");
    try testing.expectEqual(@as(u32, 0x11223380), c4);

    const c5 = try color.parseHexColor("#abcdef00");
    try testing.expectEqual(@as(u32, 0xABCDEF00), c5);

    // Errors
    try testing.expectError(error.InvalidColorFormat, color.parseHexColor(""));
    try testing.expectError(error.InvalidColorFormat, color.parseHexColor("123456")); // missing #
    try testing.expectError(error.InvalidColorFormat, color.parseHexColor("#123")); // too short
    try testing.expectError(error.InvalidColorFormat, color.parseHexColor("#1234567")); // 7 chars
    try testing.expectError(error.InvalidColorFormat, color.parseHexColor("#123456789")); // 9 chars
    try testing.expectError(error.InvalidColorFormat, color.parseHexColor("#GG0000")); // invalid hex digit
}

test "io_util: formatSequencePath patterns" {
    const testing = std.testing;
    const a = testing.allocator;

    const p1 = try io_util.formatSequencePath(a, "qr_{n}.png", 0, 3);
    defer a.free(p1);
    try testing.expectEqualStrings("qr_1.png", p1);

    const p2 = try io_util.formatSequencePath(a, "qr_%d.svg", 1, 3);
    defer a.free(p2);
    try testing.expectEqualStrings("qr_2.svg", p2);

    const p3 = try io_util.formatSequencePath(a, "code.png", 0, 3);
    defer a.free(p3);
    try testing.expectEqualStrings("code_01.png", p3);

    const p4 = try io_util.formatSequencePath(a, "output", 2, 3);
    defer a.free(p4);
    try testing.expectEqualStrings("output_03", p4);
}

test "cmd_encode: parseFnc1AppIndicator digits and letters" {
    const testing = std.testing;

    // Two digits ("00".."99")
    try testing.expectEqual(@as(u8, 0), try cmd_encode.parseFnc1AppIndicator("00"));
    try testing.expectEqual(@as(u8, 5), try cmd_encode.parseFnc1AppIndicator("05"));
    try testing.expectEqual(@as(u8, 42), try cmd_encode.parseFnc1AppIndicator("42"));
    try testing.expectEqual(@as(u8, 99), try cmd_encode.parseFnc1AppIndicator("99"));

    // Single letter ('A'..'Z' -> c + 100)
    try testing.expectEqual(@as(u8, 'A' + 100), try cmd_encode.parseFnc1AppIndicator("A"));
    try testing.expectEqual(@as(u8, 'Z' + 100), try cmd_encode.parseFnc1AppIndicator("Z"));
    try testing.expectEqual(@as(u8, 'a' + 100), try cmd_encode.parseFnc1AppIndicator("a"));
    try testing.expectEqual(@as(u8, 'z' + 100), try cmd_encode.parseFnc1AppIndicator("z"));

    // Errors
    try testing.expectError(error.InvalidFnc1AppIndicator, cmd_encode.parseFnc1AppIndicator(""));
    try testing.expectError(error.InvalidFnc1AppIndicator, cmd_encode.parseFnc1AppIndicator("1")); // single digit
    try testing.expectError(error.InvalidFnc1AppIndicator, cmd_encode.parseFnc1AppIndicator("123")); // three digits
    try testing.expectError(error.InvalidFnc1AppIndicator, cmd_encode.parseFnc1AppIndicator("AB")); // two letters
    try testing.expectError(error.InvalidFnc1AppIndicator, cmd_encode.parseFnc1AppIndicator("?")); // punctuation
}

test "render_terminal: ASCII and ANSI rendering" {
    const testing = std.testing;
    const a = testing.allocator;

    var buf: [zqr.Tier1.max_buffer_len]u8 = undefined;
    const qr = try zqr.Tier1.encode(&buf, "TEST", .low);

    // ASCII rendering
    var ascii_list: std.ArrayList(u8) = .empty;
    defer ascii_list.deinit(a);

    const ListWriter = struct {
        list: *std.ArrayList(u8),
        allocator: std.mem.Allocator,
        pub fn writeAll(self: @This(), bytes: []const u8) !void {
            try self.list.appendSlice(self.allocator, bytes);
        }
    };

    try render_terminal.renderAscii(ListWriter{ .list = &ascii_list, .allocator = a }, qr, 2);
    try testing.expect(ascii_list.items.len > 0);
    try testing.expect(std.mem.indexOf(u8, ascii_list.items, "##") != null);

    // ANSI rendering
    var ansi_list: std.ArrayList(u8) = .empty;
    defer ansi_list.deinit(a);

    try render_terminal.renderAnsi(ListWriter{ .list = &ansi_list, .allocator = a }, qr, 2);
    try testing.expect(ansi_list.items.len > 0);
    try testing.expect(std.mem.indexOf(u8, ansi_list.items, "▀") != null);
}
