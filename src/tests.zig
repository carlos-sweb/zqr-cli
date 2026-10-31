//! Integration and unit tests for zqr-cli (encode, decode, PNG, pipes, colors).

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

test "cli output correctness: cmd_encode matches z-libqr directly" {
    const testing = std.testing;
    const a = testing.allocator;

    const test_out = "/tmp/zqr_correctness_test.txt";
    defer _ = std.c.unlink(test_out);

    // 1. Run CLI command: zqr encode "HELLO WORLD" -e high -m 2 -f ascii -o /tmp/zqr_correctness_test.txt
    const args = [_][:0]const u8{
        "HELLO WORLD",
        "-e",
        "high",
        "-m",
        "2",
        "-f",
        "ascii",
        "-o",
        test_out,
    };
    try cmd_encode.run(a, &args);

    // Read generated CLI output
    const cli_output = try io_util.readFileAlloc(a, test_out);
    defer a.free(cli_output);

    // 2. Generate expected output directly using z-libqr v1.3.0
    var buf: [zqr.Tier3.max_buffer_len]u8 = undefined;
    const expected_matrix = try zqr.Tier3.encodeAdvanced(&buf, "HELLO WORLD", .{
        .ecc = .high,
        .mask = 2,
    });

    var expected_list: std.ArrayList(u8) = .empty;
    defer expected_list.deinit(a);

    const ListWriter = struct {
        list: *std.ArrayList(u8),
        allocator: std.mem.Allocator,
        pub fn writeAll(self: @This(), bytes: []const u8) !void {
            try self.list.appendSlice(self.allocator, bytes);
        }
    };
    try render_terminal.renderAscii(ListWriter{ .list = &expected_list, .allocator = a }, expected_matrix, 4);

    // 3. Verify exact byte-for-byte match
    try testing.expectEqualStrings(expected_list.items, cli_output);

    // 4. Also verify default options: zqr encode "HELLO WORLD" -f ascii -o test_out
    const default_args = [_][:0]const u8{
        "HELLO WORLD",
        "-f",
        "ascii",
        "-o",
        test_out,
    };
    try cmd_encode.run(a, &default_args);

    const cli_default_output = try io_util.readFileAlloc(a, test_out);
    defer a.free(cli_default_output);

    const expected_default_matrix = try zqr.Tier3.encodeAdvanced(&buf, "HELLO WORLD", .{
        .ecc = .medium,
    });

    var expected_default_list: std.ArrayList(u8) = .empty;
    defer expected_default_list.deinit(a);

    try render_terminal.renderAscii(ListWriter{ .list = &expected_default_list, .allocator = a }, expected_default_matrix, 4);
    try testing.expectEqualStrings(expected_default_list.items, cli_default_output);
}

const cmd_decode = @import("cmd_decode.zig");
const png_loader = @import("png_loader.zig");

test "cmd_decode: matrix parser formats (##/  , #/., 1/0, █/ , ANSI)" {
    const testing = std.testing;
    const a = testing.allocator;

    const payload = "DECODER VERIFICATION 2026";
    var buf: [zqr.Tier3.max_buffer_len]u8 = undefined;
    const m = try zqr.Tier3.encodeAdvanced(&buf, payload, .{
        .ecc = .quartile,
    });

    const ListWriter = struct {
        list: *std.ArrayList(u8),
        allocator: std.mem.Allocator,
        pub fn writeAll(self: @This(), bytes: []const u8) !void {
            try self.list.appendSlice(self.allocator, bytes);
        }
    };

    // 1. Standard ASCII (## and '  ')
    var ascii_list: std.ArrayList(u8) = .empty;
    defer ascii_list.deinit(a);
    try render_terminal.renderAscii(ListWriter{ .list = &ascii_list, .allocator = a }, m, 3);

    const parsed_ascii = try cmd_decode.parseMatrixFromText(a, ascii_list.items);
    defer a.free(parsed_ascii.modules);
    try testing.expectEqual(m.size, parsed_ascii.size);

    var dec_buf: [1024]u8 = undefined;
    const res_ascii = try zqr.DecoderTier3.decode(parsed_ascii.modules, parsed_ascii.size, &dec_buf);
    try testing.expectEqualStrings(payload, res_ascii.data);
    try testing.expectEqual(m.version, res_ascii.metadata.version);
    try testing.expectEqual(zqr.Ecc.quartile, res_ascii.metadata.ecc);

    // 2. ANSI half-blocks (▀ and escape sequences)
    var ansi_list: std.ArrayList(u8) = .empty;
    defer ansi_list.deinit(a);
    try render_terminal.renderAnsi(ListWriter{ .list = &ansi_list, .allocator = a }, m, 2);

    const parsed_ansi = try cmd_decode.parseMatrixFromText(a, ansi_list.items);
    defer a.free(parsed_ansi.modules);
    try testing.expectEqual(m.size, parsed_ansi.size);

    const res_ansi = try zqr.DecoderTier3.decode(parsed_ansi.modules, parsed_ansi.size, &dec_buf);
    try testing.expectEqualStrings(payload, res_ansi.data);

    // 3. Dot and Hash (# and .) without quiet zone
    var dot_hash: std.ArrayList(u8) = .empty;
    defer dot_hash.deinit(a);
    const size = @as(usize, m.size);
    for (0..size) |r| {
        for (0..size) |c| {
            const is_dark = m.modules[r * size + c] == 1;
            try dot_hash.append(a, if (is_dark) '#' else '.');
        }
        try dot_hash.append(a, '\n');
    }

    const parsed_dh = try cmd_decode.parseMatrixFromText(a, dot_hash.items);
    defer a.free(parsed_dh.modules);
    try testing.expectEqual(m.size, parsed_dh.size);
    const res_dh = try zqr.DecoderTier3.decode(parsed_dh.modules, parsed_dh.size, &dec_buf);
    try testing.expectEqualStrings(payload, res_dh.data);

    // 4. Binary 1 and 0 (with leading/trailing quiet zone lines)
    var bin_list: std.ArrayList(u8) = .empty;
    defer bin_list.deinit(a);
    try bin_list.appendSlice(a, "00000000000000000000000000000\n00000000000000000000000000000\n");
    for (0..size) |r| {
        try bin_list.appendSlice(a, "0000");
        for (0..size) |c| {
            const is_dark = m.modules[r * size + c] == 1;
            try bin_list.append(a, if (is_dark) '1' else '0');
        }
        try bin_list.appendSlice(a, "0000\n");
    }
    try bin_list.appendSlice(a, "00000000000000000000000000000\n");

    const parsed_bin = try cmd_decode.parseMatrixFromText(a, bin_list.items);
    defer a.free(parsed_bin.modules);
    try testing.expectEqual(m.size, parsed_bin.size);
    const res_bin = try zqr.DecoderTier3.decode(parsed_bin.modules, parsed_bin.size, &dec_buf);
    try testing.expectEqualStrings(payload, res_bin.data);

    // 5. Full block █ (UTF-8 0xE2 0x96 0x88) and space
    var block_list: std.ArrayList(u8) = .empty;
    defer block_list.deinit(a);
    for (0..size) |r| {
        for (0..size) |c| {
            const is_dark = m.modules[r * size + c] == 1;
            if (is_dark) {
                try block_list.appendSlice(a, "█");
            } else {
                try block_list.appendSlice(a, " ");
            }
        }
        try block_list.append(a, '\n');
    }

    // 6. Asymmetric quiet zone: 6 modules on left, 2 on right, 3 on top, 1 on bottom
    var asym_list: std.ArrayList(u8) = .empty;
    defer asym_list.deinit(a);
    // 3 lines top
    try asym_list.appendSlice(a, "\n\n\n");
    for (0..size) |r| {
        // 6 modules left (12 spaces)
        try asym_list.appendSlice(a, "            ");
        for (0..size) |c| {
            const is_dark = m.modules[r * size + c] == 1;
            try asym_list.appendSlice(a, if (is_dark) "##" else "  ");
        }
        // 2 modules right (4 spaces)
        try asym_list.appendSlice(a, "    \n");
    }
    // 1 line bottom
    try asym_list.appendSlice(a, "\n");

    const parsed_asym = try cmd_decode.parseMatrixFromText(a, asym_list.items);
    defer a.free(parsed_asym.modules);
    try testing.expectEqual(m.size, parsed_asym.size);
    const res_asym = try zqr.DecoderTier3.decode(parsed_asym.modules, parsed_asym.size, &dec_buf);
    try testing.expectEqualStrings(payload, res_asym.data);
}

test "cmd_decode: error cases (empty, non-qr, invalid dimensions)" {
    const testing = std.testing;
    const a = testing.allocator;

    try testing.expectError(error.EmptyInput, cmd_decode.parseMatrixFromText(a, ""));
    try testing.expectError(error.NoDarkModulesFound, cmd_decode.parseMatrixFromText(a, "\n\n   \n\r\n"));
    try testing.expectError(error.NoDarkModulesFound, cmd_decode.parseMatrixFromText(a, "....... \n....... \n"));
    // 5x5 is too small (minimum QR is 21x21)
    const small_box =
        \\#####
        \\#...#
        \\#.#.#
        \\#...#
        \\#####
    ;
    try testing.expectError(error.InvalidMatrixDimensions, cmd_decode.parseMatrixFromText(a, small_box));
}

test "cmd_decode: PNG decoding end-to-end via png_loader" {
    const testing = std.testing;
    const a = testing.allocator;

    const payload = "ZQR CLI PNG DECODE TEST 2026";
    var buf: [zqr.Tier3.max_buffer_len]u8 = undefined;
    const m = try zqr.Tier3.encodeAdvanced(&buf, payload, .{
        .ecc = .medium,
    });

    const png_data = try zqr.render.renderPng(a, m, .{
        .scale = 4,
        .quiet_zone = 4,
    });
    defer a.free(png_data);

    // 1. Verify loadPng decodes into grayscale pixels
    var img = try png_loader.loadPng(png_data);
    defer img.deinit();

    const expected_dim: usize = (@as(usize, m.size) + 8) * 4;
    try testing.expectEqual(expected_dim, img.width);
    try testing.expectEqual(expected_dim, img.height);
    try testing.expectEqual(expected_dim * expected_dim, img.pixels.len);

    // 2. Decode pixels through DecoderTier3
    var dec_buf: [1024]u8 = undefined;
    const res = try zqr.DecoderTier3.decodeImageAlloc(a, img.pixels, img.width, img.height, &dec_buf);
    try testing.expectEqualStrings(payload, res.data);
    try testing.expectEqual(m.version, res.metadata.version);
    try testing.expectEqual(zqr.Ecc.medium, res.metadata.ecc);
}

test "cmd_decode: PNG downscaling for high-resolution images (> 1024x1024)" {
    const testing = std.testing;
    const a = testing.allocator;

    const payload = "HIGH RESOLUTION DOWNSCALE TEST";
    var buf: [zqr.Tier3.max_buffer_len]u8 = undefined;
    const m = try zqr.Tier3.encodeAdvanced(&buf, payload, .{
        .ecc = .quartile,
    });

    // (25 + 8) * 35 = 1155x1155 px (> 1024)
    const png_data = try zqr.render.renderPng(a, m, .{
        .scale = 35,
        .quiet_zone = 4,
    });
    defer a.free(png_data);

    var img = try png_loader.loadPng(png_data);
    defer img.deinit();

    try testing.expect(img.width > 1024);
    try testing.expect(img.height > 1024);

    // Downscale to <= 1024x1024
    try png_loader.downscaleIfNeeded(a, &img);

    try testing.expect(img.width <= 1024);
    try testing.expect(img.height <= 1024);
    try testing.expectEqual(@as(usize, 1024), img.width);
    try testing.expectEqual(@as(usize, 1024), img.height);

    // Verify downscaled image decodes cleanly
    var dec_buf: [1024]u8 = undefined;
    const res = try zqr.DecoderTier3.decodeImageAlloc(a, img.pixels, img.width, img.height, &dec_buf);
    try testing.expectEqualStrings(payload, res.data);
    try testing.expectEqual(m.version, res.metadata.version);
}

test "cmd_decode: CLI execution with PNG and ASCII files" {
    const testing = std.testing;
    const a = testing.allocator;

    const payload = "CLI FILE ROUNDTRIP 12345";
    const png_file = "/tmp/zqr_test_roundtrip.png";
    const dec_file = "/tmp/zqr_test_roundtrip.txt";
    defer _ = std.c.unlink(png_file);
    defer _ = std.c.unlink(dec_file);

    // 1. Encode PNG to file
    const enc_args = [_][:0]const u8{
        payload,
        "-f",
        "png",
        "-o",
        png_file,
    };
    try cmd_encode.run(a, &enc_args);

    // 2. Decode PNG via cmd_decode.run to output file
    const dec_args = [_][:0]const u8{
        "-i",
        png_file,
        "-o",
        dec_file,
    };
    try cmd_decode.run(a, &dec_args);

    const decoded_payload = try io_util.readFileAlloc(a, dec_file);
    defer a.free(decoded_payload);
    try testing.expectEqualStrings(payload, decoded_payload);

    // 3. Invalid PNG extension with text content must fail with DecodeFailed
    const fake_png = "/tmp/zqr_fake.png";
    defer _ = std.c.unlink(fake_png);
    try io_util.writeFile(fake_png, "NOT A REAL PNG FILE AT ALL");

    const fake_args = [_][:0]const u8{
        "-i",
        fake_png,
    };
    try testing.expectError(error.DecodeFailed, cmd_decode.run(a, &fake_args));

    // 4. Missing file must fail with InputOutput
    const missing_args = [_][:0]const u8{
        "-i",
        "/tmp/non_existent_file_xyz_123.png",
    };
    try testing.expectError(error.InputOutput, cmd_decode.run(a, &missing_args));
}

test "cmd_encode: --dot-shape and --eye-shape flags" {
    const testing = std.testing;
    const a = testing.allocator;

    const svg_file = "/tmp/zqr_shapes_test.svg";
    defer _ = std.c.unlink(svg_file);

    const args = [_][:0]const u8{
        "SMOOTH BLOB TEST",
        "-f",
        "svg",
        "--dot-shape",
        "rounded",
        "--eye-shape",
        "rounded",
        "-o",
        svg_file,
    };
    try cmd_encode.run(a, &args);

    const svg_content = try io_util.readFileAlloc(a, svg_file);
    defer a.free(svg_content);

    try testing.expect(std.mem.indexOf(u8, svg_content, "<filter") == null);
    try testing.expect(std.mem.indexOf(u8, svg_content, "stroke-linejoin") == null);
    try testing.expect(std.mem.indexOf(u8, svg_content, " C") != null);
    try testing.expect(std.mem.indexOf(u8, svg_content, "<circle") != null);
}
