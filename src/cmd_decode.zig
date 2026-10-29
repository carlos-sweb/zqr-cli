const std = @import("std");
const zargs = @import("zargs");
const zqr = @import("zqr");
const print_util = @import("print_util.zig");
const io_util = @import("io_util.zig");

const Flag = zargs.Declarative.Flag;
const Positional = zargs.Declarative.Positional;

pub const DecodeArgs = struct {
    read_from: Flag([]const u8, .{ .short = 'i', .long = "read-from", .help = "Read matrix from file or '-' for stdin", .default = "" }),
    verbose: Flag(bool, .{ .short = 'v', .long = "verbose", .help = "Print symbol metadata to stderr", .default = false }),
    help: Flag(bool, .{ .short = 'h', .long = "help", .help = "Show this help and exit", .default = false }),
    input: Positional([]const u8, .{ .help = "Input file path (or '-' for stdin)", .default = "" }),
};

pub const ParseMatrixError = error{
    EmptyInput,
    NoDarkModulesFound,
    InvalidMatrixDimensions,
    InvalidRowLength,
    InvalidMatrixSize,
    NonSquareMatrix,
    InvalidChar,
};

pub const ParsedMatrix = struct {
    modules: []u8,
    size: u8,
};

/// Parses ASCII/ANSI text representation of a QR code into an S x S module array (0 or 1).
pub fn parseMatrixFromText(allocator: std.mem.Allocator, raw: []const u8) !ParsedMatrix {
    if (raw.len == 0) return error.EmptyInput;

    // Check if input uses Unicode half-blocks (▀ U+2580, bytes 0xE2 0x96 0x80) from ANSI rendering
    if (std.mem.indexOf(u8, raw, "\xe2\x96\x80") != null) {
        return parseAnsiHalfBlocks(allocator, raw);
    }

    return parseLineByLine(allocator, raw);
}

fn parseAnsiHalfBlocks(allocator: std.mem.Allocator, raw: []const u8) !ParsedMatrix {
    var raw_lines: std.ArrayList([]const u8) = .empty;
    defer raw_lines.deinit(allocator);

    var line_it = std.mem.splitScalar(u8, raw, '\n');
    while (line_it.next()) |line| {
        if (line.len > 0 and line[line.len - 1] == '\r') {
            try raw_lines.append(allocator, line[0 .. line.len - 1]);
        } else {
            try raw_lines.append(allocator, line);
        }
    }

    if (raw_lines.items.len == 0) return error.EmptyInput;

    var grid: std.ArrayList([]u8) = .empty;
    defer {
        for (grid.items) |row| allocator.free(row);
        grid.deinit(allocator);
    }

    for (raw_lines.items) |line| {
        if (line.len == 0) continue;

        var top_row: std.ArrayList(u8) = .empty;
        defer top_row.deinit(allocator);
        var bot_row: std.ArrayList(u8) = .empty;
        defer bot_row.deinit(allocator);

        var fg_dark = false;
        var bg_dark = false;
        var i: usize = 0;

        while (i < line.len) {
            if (line[i] == 0x1b and i + 1 < line.len and line[i + 1] == '[') {
                // ANSI escape sequence: \x1b[...m
                const esc_start = i + 2;
                var esc_end = esc_start;
                while (esc_end < line.len and line[esc_end] != 'm') : (esc_end += 1) {}
                if (esc_end < line.len) {
                    const params = line[esc_start..esc_end];
                    var param_it = std.mem.splitScalar(u8, params, ';');
                    while (param_it.next()) |p| {
                        const code = std.fmt.parseInt(u16, p, 10) catch 0;
                        if (code == 0) {
                            fg_dark = false;
                            bg_dark = false;
                        } else if (code == 30 or code == 38) {
                            fg_dark = true;
                        } else if (code == 97 or code == 37) {
                            fg_dark = false;
                        } else if (code == 40 or code == 48) {
                            bg_dark = true;
                        } else if (code == 107 or code == 47) {
                            bg_dark = false;
                        }
                    }
                    i = esc_end + 1;
                    continue;
                }
            }

            // Check UTF-8 ▀ (0xE2 0x96 0x80)
            if (i + 2 < line.len and line[i] == 0xe2 and line[i + 1] == 0x96 and line[i + 2] == 0x80) {
                try top_row.append(allocator, if (fg_dark) 1 else 0);
                try bot_row.append(allocator, if (bg_dark) 1 else 0);
                i += 3;
            } else if (line[i] == ' ') {
                try top_row.append(allocator, if (bg_dark) 1 else 0);
                try bot_row.append(allocator, if (bg_dark) 1 else 0);
                i += 1;
            } else {
                i += 1;
            }
        }

        if (top_row.items.len > 0) {
            try grid.append(allocator, try top_row.toOwnedSlice(allocator));
            try grid.append(allocator, try bot_row.toOwnedSlice(allocator));
        }
    }

    return extractMatrixFromGrid(allocator, grid.items, 1);
}

fn parseLineByLine(allocator: std.mem.Allocator, raw: []const u8) !ParsedMatrix {
    var raw_lines: std.ArrayList([]const u8) = .empty;
    defer raw_lines.deinit(allocator);

    var line_it = std.mem.splitScalar(u8, raw, '\n');
    while (line_it.next()) |line| {
        const clean = if (line.len > 0 and line[line.len - 1] == '\r') line[0 .. line.len - 1] else line;
        try raw_lines.append(allocator, clean);
    }

    if (raw_lines.items.len == 0) return error.EmptyInput;

    var grid: std.ArrayList([]u8) = .empty;
    defer {
        for (grid.items) |row| allocator.free(row);
        grid.deinit(allocator);
    }

    for (raw_lines.items) |line| {
        var row: std.ArrayList(u8) = .empty;
        defer row.deinit(allocator);

        var i: usize = 0;
        while (i < line.len) {
            // Skip ANSI escapes if present
            if (line[i] == 0x1b and i + 1 < line.len and line[i + 1] == '[') {
                i += 2;
                while (i < line.len and line[i] != 'm') : (i += 1) {}
                if (i < line.len) i += 1;
                continue;
            }

            const b = line[i];

            // Dark module representations
            if (b == '#' or b == '1' or b == 'X' or b == 'x' or b == '*') {
                try row.append(allocator, 1);
                i += 1;
            } else if (b == '.' or b == '0' or b == ' ' or b == '-' or b == '_') {
                // Light module representations
                try row.append(allocator, 0);
                i += 1;
            } else if (i + 2 < line.len and line[i] == 0xe2 and line[i + 1] == 0x96 and line[i + 2] == 0x88) {
                // UTF-8 █ (Full block U+2588) -> Dark
                try row.append(allocator, 1);
                i += 3;
            } else if (i + 2 < line.len and line[i] == 0xe2 and line[i + 1] == 0x9a and line[i + 2] == 0xa0) {
                // UTF-8 ■ (Black square U+25A0) -> Dark
                try row.append(allocator, 1);
                i += 3;
            } else if (i + 3 < line.len and line[i] == 0xe2 and line[i + 1] == 0xac and line[i + 2] == 0x9b) {
                // UTF-8 ⬛ (Black large square U+2B1B) -> Dark
                try row.append(allocator, 1);
                i += 4;
            } else if (i + 2 < line.len and line[i] == 0xe2 and line[i + 1] == 0x96 and line[i + 2] == 0x91) {
                // UTF-8 ░ (Light shade U+2591) -> Light
                try row.append(allocator, 0);
                i += 3;
            } else if (i + 2 < line.len and line[i] == 0xe2 and line[i + 1] == 0x9a and line[i + 2] == 0xa1) {
                // UTF-8 □ (White square U+25A1) -> Light
                try row.append(allocator, 0);
                i += 3;
            } else if (i + 3 < line.len and line[i] == 0xe2 and line[i + 1] == 0xac and line[i + 2] == 0x9c) {
                // UTF-8 ⬜ (White large square U+2B1C) -> Light
                try row.append(allocator, 0);
                i += 4;
            } else {
                // Other characters (e.g. tab, border decoration) ignored
                i += 1;
            }
        }

        try grid.append(allocator, try row.toOwnedSlice(allocator));
    }

    return extractMatrixFromGrid(allocator, grid.items, null);
}

fn extractMatrixFromGrid(allocator: std.mem.Allocator, grid: []const []const u8, forced_scale: ?usize) !ParsedMatrix {
    if (grid.len == 0) return error.EmptyInput;

    // Find bounding box of dark modules (value == 1)
    var min_row: usize = std.math.maxInt(usize);
    var max_row: usize = 0;
    var min_col: usize = std.math.maxInt(usize);
    var max_col: usize = 0;
    var found_dark = false;

    for (grid, 0..) |row, r| {
        for (row, 0..) |val, c| {
            if (val == 1) {
                found_dark = true;
                if (r < min_row) min_row = r;
                if (r > max_row) max_row = r;
                if (c < min_col) min_col = c;
                if (c > max_col) max_col = c;
            }
        }
    }

    if (!found_dark) return error.NoDarkModulesFound;

    const h = max_row - min_row + 1;
    const w_raw = max_col - min_col + 1;

    // In QR Model 2, the bounding box of dark modules spans exactly from the outer edge
    // of finder pattern 0 to the outer edge of finder patterns 1 and 2.
    // Therefore, height h must be exactly the QR matrix dimension: S = 17 + 4 * version.
    if (h < 21 or h > 177 or ((h - 17) % 4 != 0)) {
        return error.InvalidMatrixDimensions;
    }

    const s: u8 = @intCast(h);

    const scale: usize = if (forced_scale) |fs| fs else blk: {
        // Horizontal scale factor: typically 1 (single-char "#/.") or 2 ("##/  ", "██/  ")
        if (w_raw % h == 0) {
            break :blk w_raw / h;
        } else if (w_raw >= 2 * h - 1 and w_raw <= 2 * h + 1) {
            // Allow 1-column jitter in edge whitespace
            break :blk 2;
        } else if (w_raw >= h - 1 and w_raw <= h + 1) {
            break :blk 1;
        } else {
            return error.InvalidMatrixDimensions;
        }
    };

    if (scale == 0) return error.InvalidMatrixDimensions;

    const total_modules = @as(usize, s) * s;
    const out_modules = try allocator.alloc(u8, total_modules);
    errdefer allocator.free(out_modules);

    for (0..s) |r| {
        const grid_r = min_row + r;
        const row_slice = if (grid_r < grid.len) grid[grid_r] else &[_]u8{};

        for (0..s) |c| {
            const start_c = min_col + c * scale;

            // Sample module value using majority vote over scale columns
            var ones: usize = 0;
            var samples: usize = 0;
            for (0..scale) |k| {
                const col_idx = start_c + k;
                if (col_idx < row_slice.len) {
                    if (row_slice[col_idx] == 1) ones += 1;
                    samples += 1;
                }
            }

            const val: u8 = if (samples > 0 and ones * 2 >= samples) 1 else 0;
            out_modules[r * s + c] = val;
        }
    }

    return .{
        .modules = out_modules,
        .size = s,
    };
}

fn printVerboseInfo(meta: zqr.DecoderTier3.Metadata) !void {
    const ecc_name: []const u8 = switch (meta.ecc) {
        .low => "low",
        .medium => "medium",
        .quartile => "quartile",
        .high => "high",
    };

    var modes_buf: [128]u8 = undefined;
    var idx: usize = 0;
    var first = true;
    if ((meta.modes_used & 0x01) != 0) {
        @memcpy(modes_buf[idx .. idx + 7], "numeric");
        idx += 7;
        first = false;
    }
    if ((meta.modes_used & 0x02) != 0) {
        if (!first) {
            modes_buf[idx] = ',';
            idx += 1;
        }
        @memcpy(modes_buf[idx .. idx + 12], "alphanumeric");
        idx += 12;
        first = false;
    }
    if ((meta.modes_used & 0x04) != 0) {
        if (!first) {
            modes_buf[idx] = ',';
            idx += 1;
        }
        @memcpy(modes_buf[idx .. idx + 4], "byte");
        idx += 4;
        first = false;
    }
    if ((meta.modes_used & 0x08) != 0) {
        if (!first) {
            modes_buf[idx] = ',';
            idx += 1;
        }
        @memcpy(modes_buf[idx .. idx + 5], "kanji");
        idx += 5;
        first = false;
    }
    if ((meta.modes_used & 0x10) != 0) {
        if (!first) {
            modes_buf[idx] = ',';
            idx += 1;
        }
        @memcpy(modes_buf[idx .. idx + 3], "eci");
        idx += 3;
        first = false;
    }
    if ((meta.modes_used & 0x20) != 0) {
        if (!first) {
            modes_buf[idx] = ',';
            idx += 1;
        }
        @memcpy(modes_buf[idx .. idx + 4], "fnc1");
        idx += 4;
        first = false;
    }
    if ((meta.modes_used & 0x40) != 0) {
        if (!first) {
            modes_buf[idx] = ',';
            idx += 1;
        }
        @memcpy(modes_buf[idx .. idx + 17], "structured_append");
        idx += 17;
        first = false;
    }
    const modes_str = modes_buf[0..idx];

    try print_util.printStderr("version: {u}\n", .{meta.version});
    try print_util.printStderr("ecc: {s}\n", .{ecc_name});
    try print_util.printStderr("mask: {u}\n", .{meta.mask});
    try print_util.printStderr("modes_used: {s}\n", .{modes_str});
    try print_util.printStderr("errors_corrected_format: {u}\n", .{meta.errors_corrected_format});
    try print_util.printStderr("errors_corrected_version: {u}\n", .{meta.errors_corrected_version});
    try print_util.printStderr("errors_corrected_data: {u}\n", .{meta.errors_corrected_data});

    if (meta.sa) |sa| {
        try print_util.printStderr("has_sa: 1\n", .{});
        try print_util.printStderr("sa_position: {u}\n", .{sa.position});
        try print_util.printStderr("sa_total: {u}\n", .{sa.total});
        try print_util.printStderr("sa_parity: 0x{x:0>2}\n", .{sa.parity});
    } else {
        try print_util.printStderr("has_sa: 0\n", .{});
    }

    if (meta.eci) |eci| {
        try print_util.printStderr("has_eci: 1\n", .{});
        try print_util.printStderr("eci: {u}\n", .{eci});
    } else {
        try print_util.printStderr("has_eci: 0\n", .{});
    }

    if (meta.fnc1_mode) |mode| {
        try print_util.printStderr("has_fnc1: 1\n", .{});
        switch (mode) {
            .first => {
                try print_util.printStderr("fnc1_mode: first\n", .{});
            },
            .second => {
                try print_util.printStderr("fnc1_mode: second\n", .{});
                if (meta.fnc1_app_indicator) |app| {
                    try print_util.printStderr("fnc1_app_indicator: {u}\n", .{app});
                }
            },
        }
    } else {
        try print_util.printStderr("has_fnc1: 0\n", .{});
    }
}

pub fn printDecodeHelp() !void {
    try print_util.printStdout("{s:bold:cyan}zqr decode{s:reset} — Decode QR code matrix from ASCII or terminal text\n\n", .{ "", "" });
    try print_util.printStdout("{s:bold}USAGE:{s:reset}\n", .{""});
    try print_util.printStdout("  zqr decode [OPTIONS] [FILE]\n", .{});
    try print_util.printStdout("  zqr encode \"Hello\" -f ascii | zqr decode -\n\n", .{});
    try print_util.printStdout("{s:bold}OPTIONS:{s:reset}\n", .{""});
    try print_util.printStdout("  {s:bold}-i, --read-from <FILE>{s:reset}   Read input from file or '-' for stdin\n", .{ "", "" });
    try print_util.printStdout("  {s:bold}-v, --verbose{s:reset}            Print symbol metadata (version, ECC, mask, corrections) to stderr\n", .{ "", "" });
    try print_util.printStdout("  {s:bold}-h, --help{s:reset}               Display this help message\n\n", .{ "", "" });
    try print_util.printStdout("{s:bold}EXIT CODES:{s:reset}\n", .{""});
    try print_util.printStdout("  0: Success\n", .{});
    try print_util.printStdout("  1: Decode error (invalid matrix, damaged payload exceeding ECC)\n", .{});
    try print_util.printStdout("  2: I/O error (file not found, read failure, missing input)\n", .{});
}

pub fn run(allocator: std.mem.Allocator, args: []const [:0]const u8) anyerror!void {
    var diag: zargs.Declarative.Diagnostics = .{};
    const parsed = zargs.Declarative.parseStruct(DecodeArgs, allocator, args, &diag) catch |err| {
        try print_util.printStderr("{s:red:bold} invalid decode option: {s}\n", .{ "error:", diag.raw orelse diag.field orelse @errorName(err) });
        return err;
    };

    if (parsed.help.value) {
        try printDecodeHelp();
        return;
    }

    const target_input: ?[]const u8 = if (parsed.read_from.value.len > 0)
        parsed.read_from.value
    else if (parsed.input.value.len > 0)
        parsed.input.value
    else
        null;

    const raw_matrix_text = io_util.readPayload(allocator, null, target_input) catch |err| {
        try print_util.printStderr("{s:bold:red}error:{s:reset} failed to read input: {s}\n", .{ "", @errorName(err) });
        return error.InputOutput;
    };
    defer allocator.free(raw_matrix_text);

    const parsed_mat = parseMatrixFromText(allocator, raw_matrix_text) catch |err| {
        try print_util.printStderr("{s:bold:red}error:{s:reset} failed to parse QR matrix from text: {s}\n", .{ "", @errorName(err) });
        return error.DecodeFailed;
    };
    defer allocator.free(parsed_mat.modules);

    var out_buf: [zqr.DecoderTier3.max_decoded_len]u8 = undefined;
    const res = zqr.DecoderTier3.decode(parsed_mat.modules, parsed_mat.size, &out_buf) catch |err| {
        try print_util.printStderr("{s:bold:red}error:{s:reset} QR decode failed: {s}\n", .{ "", @errorName(err) });
        return error.DecodeFailed;
    };

    if (parsed.verbose.value) {
        try printVerboseInfo(res.metadata);
    }

    // Write decoded payload directly to stdout
    const stdout = io_util.stdoutWriter();
    stdout.writeAll(res.data) catch |err| {
        try print_util.printStderr("{s:bold:red}error:{s:reset} failed to write output: {s}\n", .{ "", @errorName(err) });
        return error.InputOutput;
    };
}
