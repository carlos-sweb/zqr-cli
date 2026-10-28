const std = @import("std");
const zargs = @import("zargs");
const z_print = @import("z_print");
const zqr = @import("zqr");
const cli_options = @import("cli_options");
const print_util = @import("print_util.zig");

const color = @import("color.zig");
const io_util = @import("io_util.zig");
const render_terminal = @import("render_terminal.zig");

const Flag = zargs.Declarative.Flag;
const Positional = zargs.Declarative.Positional;

pub const Format = enum {
    auto,
    svg,
    png,
    ansi,
    ascii,
};

pub const EccLevel = enum {
    low,
    medium,
    quartile,
    high,
    l,
    m,
    q,
    h,

    pub fn toZqr(self: EccLevel) zqr.Ecc {
        return switch (self) {
            .low, .l => .low,
            .medium, .m => .medium,
            .quartile, .q => .quartile,
            .high, .h => .high,
        };
    }
};

pub const Fnc1Choice = enum {
    none,
    first,
    second,
};

pub const EncodeArgs = struct {
    output: Flag([]const u8, .{ .short = 'o', .long = "output", .help = "Output file path (default: stdout)", .default = "" }),
    format: Flag(Format, .{ .short = 'f', .long = "format", .help = "Output format: auto|svg|png|ansi|ascii (default: auto)", .default = .auto }),
    read_from: Flag([]const u8, .{ .short = 'i', .long = "read-from", .help = "Read payload from file or '-' for stdin", .default = "" }),
    ecc: Flag(EccLevel, .{ .short = 'e', .long = "ecc", .help = "Error correction level: low|medium|quartile|high (default: medium)", .default = .medium }),
    qr_version: Flag(u8, .{ .long = "qr-version", .help = "Force exact QR version (1..40)", .default = 0 }),
    min_version: Flag(u8, .{ .long = "min-version", .help = "Minimum QR version (default: 1)", .default = 1 }),
    max_version: Flag(u8, .{ .long = "max-version", .help = "Maximum QR version (default: 40)", .default = 40 }),
    mask: Flag(i8, .{ .short = 'm', .long = "mask", .help = "Forced mask pattern (0..7, default: -1 for auto)", .default = -1 }),
    kanji: Flag(bool, .{ .long = "kanji", .help = "Enable JIS X 0208 Kanji mode for Japanese text", .default = false }),
    optimize: Flag(bool, .{ .help = "Optimal multi-mode DP segmentation", .default = true }), // provides --no-optimize
    fnc1: Flag(Fnc1Choice, .{ .long = "fnc1", .help = "FNC1 mode: none|first (GS1)|second (AIM)", .default = .none }),
    fnc1_app: Flag([]const u8, .{ .long = "fnc1-app", .help = "Application Indicator for FNC1 second position", .default = "" }),
    eci: Flag(u32, .{ .long = "eci", .help = "ECI assignment number (0..999999)", .default = 1000000 }),
    structured: Flag([]const u8, .{ .short = 'S', .long = "structured", .help = "Structured Append: 'auto' or count 1..16", .default = "" }),
    scale: Flag(u8, .{ .short = 's', .long = "scale", .help = "Pixels per module for SVG/PNG (default: 8)", .default = 8 }),
    quiet_zone: Flag(u8, .{ .short = 'q', .long = "quiet-zone", .help = "Quiet zone margin in modules (default: 4)", .default = 4 }),
    fg: Flag([]const u8, .{ .long = "fg", .help = "Foreground color in hex (default: #000000FF)", .default = "#000000FF" }),
    bg: Flag([]const u8, .{ .long = "bg", .help = "Background color in hex (default: #FFFFFFFF)", .default = "#FFFFFFFF" }),
    help: Flag(bool, .{ .short = 'h', .long = "help", .help = "Show this help and exit", .default = false }),
    data: Positional([]const u8, .{ .help = "Data payload to encode", .default = "" }),
};

pub fn parseFnc1AppIndicator(str: []const u8) !u8 {
    if (str.len == 1) {
        const c = str[0];
        if ((c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z')) {
            return c + 100;
        } else {
            return error.InvalidFnc1AppIndicator;
        }
    } else if (str.len == 2) {
        if (str[0] >= '0' and str[0] <= '9' and str[1] >= '0' and str[1] <= '9') {
            return (str[0] - '0') * 10 + (str[1] - '0');
        } else {
            return error.InvalidFnc1AppIndicator;
        }
    } else {
        return error.InvalidFnc1AppIndicator;
    }
}

pub fn run(allocator: std.mem.Allocator, args: []const [:0]const u8) anyerror!void {
    var diag: zargs.Declarative.Diagnostics = .{};
    const parsed = zargs.Declarative.parseStruct(EncodeArgs, allocator, args, &diag) catch |err| {
        try print_util.printStderr("{s:red:bold} invalid option: {s}\n", .{ "error:", diag.raw orelse diag.field orelse @errorName(err) });
        return err;
    };

    if (parsed.help.value) {
        const usage = try zargs.Declarative.usageAlloc(EncodeArgs, allocator, "Usage: zqr encode [OPTIONS] [DATA]\n\nOptions:");
        defer allocator.free(usage);
        try io_util.stdoutWriter().writeAll(usage);
        return;
    }

    const pos_data = if (parsed.data.value.len > 0) parsed.data.value else null;
    const read_from = if (parsed.read_from.value.len > 0) parsed.read_from.value else null;

    const payload = io_util.readPayload(allocator, pos_data, read_from) catch |err| {
        if (err == error.MissingInputData) {
            try print_util.printStderr("{s:red:bold} no input data provided. Specify data as an argument, via -i <file>, or via pipe.\n", .{"error:"});
            return error.MissingInputData;
        }
        return err;
    };
    defer allocator.free(payload);

    // Resolve Colors
    const fg_color = color.parseHexColor(parsed.fg.value) catch {
        try print_util.printStderr("{s:red:bold} invalid foreground color '{s}'. Expected #RRGGBB or #RRGGBBAA.\n", .{ "error:", parsed.fg.value });
        return error.InvalidColorFormat;
    };
    const bg_color = color.parseHexColor(parsed.bg.value) catch {
        try print_util.printStderr("{s:red:bold} invalid background color '{s}'. Expected #RRGGBB or #RRGGBBAA.\n", .{ "error:", parsed.bg.value });
        return error.InvalidColorFormat;
    };

    // Resolve Version Bounds
    var min_v: u8 = parsed.min_version.value;
    var max_v: u8 = parsed.max_version.value;
    if (parsed.qr_version.value != 0) {
        if (parsed.qr_version.value < 1 or parsed.qr_version.value > 40) {
            try print_util.printStderr("{s:red:bold} --qr-version must be in range 1..40 (got {u}).\n", .{ "error:", parsed.qr_version.value });
            return error.InvalidVersion;
        }
        min_v = parsed.qr_version.value;
        max_v = parsed.qr_version.value;
    }

    if (min_v < 1 or min_v > 40 or max_v < 1 or max_v > 40 or min_v > max_v) {
        try print_util.printStderr("{s:red:bold} invalid version bounds (min: {u}, max: {u}). Must be 1..40 with min <= max.\n", .{ "error:", min_v, max_v });
        return error.InvalidVersion;
    }

    // Resolve Mask
    const forced_mask: ?u3 = if (parsed.mask.value >= 0 and parsed.mask.value <= 7)
        @intCast(parsed.mask.value)
    else if (parsed.mask.value == -1)
        null
    else {
        try print_util.printStderr("{s:red:bold} invalid mask pattern {d}. Must be -1 (auto) or 0..7.\n", .{ "error:", @as(i32, parsed.mask.value) });
        return error.InvalidMask;
    };

    // Resolve FNC1
    var fnc1_opt: ?zqr.Fnc1 = null;
    if (parsed.fnc1.value == .first) {
        fnc1_opt = .{ .mode = .first };
    } else if (parsed.fnc1.value == .second) {
        if (parsed.fnc1_app.value.len == 0) {
            try print_util.printStderr("{s:red:bold} --fnc1 second requires --fnc1-app <indicator>.\n", .{"error:"});
            return error.MissingFnc1AppIndicator;
        }
        const app_ind = parseFnc1AppIndicator(parsed.fnc1_app.value) catch {
            try print_util.printStderr("{s:red:bold} invalid --fnc1-app indicator '{s}'. Must be 2 digits ('00'..'99') or a single letter ('A'..'Z').\n", .{ "error:", parsed.fnc1_app.value });
            return error.InvalidFnc1AppIndicator;
        };
        fnc1_opt = .{ .mode = .second, .app_indicator = app_ind };
    }

    // Resolve ECI
    const eci_opt: ?u32 = if (parsed.eci.value < 1000000) parsed.eci.value else null;

    // Resolve Format
    var format: Format = parsed.format.value;
    const has_output_file = parsed.output.value.len > 0 and !std.mem.eql(u8, parsed.output.value, "-");

    if (format == .auto) {
        if (has_output_file) {
            const out_path = parsed.output.value;
            if (std.mem.endsWith(u8, out_path, ".svg")) {
                format = .svg;
            } else if (std.mem.endsWith(u8, out_path, ".png")) {
                format = .png;
            } else if (std.mem.endsWith(u8, out_path, ".txt") or std.mem.endsWith(u8, out_path, ".asc")) {
                format = .ascii;
            } else {
                format = .svg;
            }
        } else {
            if (io_util.isStdoutTty()) {
                format = .ansi;
            } else {
                format = .svg;
            }
        }
    }

    if (format == .png and !cli_options.enable_png) {
        try print_util.printStderr("{s:red:bold} PNG format is disabled in this binary. Recompile with -Denable-png=true or use SVG/ANSI format.\n", .{"error:"});
        return error.UnsupportedFormat;
    }

    const render_opts = zqr.render.RenderOptions{
        .quiet_zone = parsed.quiet_zone.value,
        .scale = parsed.scale.value,
        .foreground = fg_color,
        .background = bg_color,
    };

    // Check Structured Append
    const is_structured = parsed.structured.value.len > 0;
    if (is_structured) {
        if (!has_output_file) {
            try print_util.printStderr("{s:red:bold} Structured Append output to stdout is not supported; use --output with a file pattern (e.g. -o qr_\\{n\\}.png or -o qr.svg).\n", .{"error:"});
            return error.StructuredAppendStdoutNotSupported;
        }

        var forced_count: ?u8 = null;
        if (!std.mem.eql(u8, parsed.structured.value, "auto")) {
            const cnt = std.fmt.parseInt(u8, parsed.structured.value, 10) catch {
                try print_util.printStderr("{s:red:bold} invalid --structured count '{s}'. Must be 'auto' or 1..16.\n", .{ "error:", parsed.structured.value });
                return error.InvalidSymbolCount;
            };
            if (cnt < 1 or cnt > 16) {
                try print_util.printStderr("{s:red:bold} --structured count must be 1..16 (got {u}).\n", .{ "error:", cnt });
                return error.InvalidSymbolCount;
            }
            forced_count = cnt;
        }

        const seq_options = zqr.Tier3.SequenceOptions{
            .ecc = parsed.ecc.value.toZqr(),
            .min_version = min_v,
            .max_version = max_v,
            .mask = forced_mask,
            .kanji = parsed.kanji.value,
            .optimize = parsed.optimize.value,
            .fnc1 = fnc1_opt,
            .eci = eci_opt,
            .symbol_count = forced_count,
        };

        // Determine buffer size
        const module_storage = try allocator.alloc(u8, zqr.Tier3.max_sequence_buffer_len);
        defer allocator.free(module_storage);

        const seq_res = zqr.Tier3.encodeSequence(module_storage, payload, seq_options) catch |err| {
            try print_util.printStderr("{s:red:bold} Structured Append encoding failed: {s}\n", .{ "error:", @errorName(err) });
            return err;
        };

        for (0..seq_res.count) |i| {
            const out_path = try io_util.formatSequencePath(allocator, parsed.output.value, i, seq_res.count);
            defer allocator.free(out_path);

            const m = seq_res.matrices[i];

            if (format == .svg) {
                const svg_data = try zqr.render.renderSvg(allocator, m, render_opts);
                defer allocator.free(svg_data);
                try io_util.writeFile(out_path, svg_data);
            } else if (format == .png) {
                const png_data = try zqr.render.renderPng(allocator, m, render_opts);
                defer allocator.free(png_data);
                try io_util.writeFile(out_path, png_data);
            } else if (format == .ascii) {
                const fw = try io_util.openFileWriter(out_path);
                defer fw.close();
                try render_terminal.renderAscii(fw.writer(), m, render_opts.quiet_zone);
            } else {
                const fw = try io_util.openFileWriter(out_path);
                defer fw.close();
                try render_terminal.renderAnsi(fw.writer(), m, render_opts.quiet_zone);
            }

            var parity_str: [10]u8 = undefined;
            const parity_formatted = std.fmt.bufPrint(&parity_str, "0x{X:0>2}", .{seq_res.parity}) catch "0x??";

            try print_util.printStderr("Saved symbol {u}/{u} (Version {u}, parity {s}) to {s}\n", .{
                i + 1, seq_res.count, m.version, parity_formatted, out_path,
            });
        }
        return;
    }

    // Single Symbol Encoding
    const options = zqr.Tier3.Options{
        .ecc = parsed.ecc.value.toZqr(),
        .min_version = min_v,
        .max_version = max_v,
        .mask = forced_mask,
        .kanji = parsed.kanji.value,
        .optimize = parsed.optimize.value,
        .fnc1 = fnc1_opt,
        .eci = eci_opt,
    };

    var buf: [zqr.Tier3.max_buffer_len]u8 = undefined;
    const matrix = zqr.Tier3.encodeAdvanced(&buf, payload, options) catch |err| {
        try print_util.printStderr("{s:red:bold} QR encoding failed: {s}\n", .{ "error:", @errorName(err) });
        return err;
    };

    if (has_output_file) {
        if (format == .svg) {
            const svg_data = try zqr.render.renderSvg(allocator, matrix, render_opts);
            defer allocator.free(svg_data);
            try io_util.writeFile(parsed.output.value, svg_data);
        } else if (format == .png) {
            const png_data = try zqr.render.renderPng(allocator, matrix, render_opts);
            defer allocator.free(png_data);
            try io_util.writeFile(parsed.output.value, png_data);
        } else if (format == .ascii) {
            const fw = try io_util.openFileWriter(parsed.output.value);
            defer fw.close();
            try render_terminal.renderAscii(fw.writer(), matrix, render_opts.quiet_zone);
        } else {
            const fw = try io_util.openFileWriter(parsed.output.value);
            defer fw.close();
            try render_terminal.renderAnsi(fw.writer(), matrix, render_opts.quiet_zone);
        }
    } else {
        const stdout = io_util.stdoutWriter();
        if (format == .svg) {
            const svg_data = try zqr.render.renderSvg(allocator, matrix, render_opts);
            defer allocator.free(svg_data);
            try stdout.writeAll(svg_data);
        } else if (format == .png) {
            const png_data = try zqr.render.renderPng(allocator, matrix, render_opts);
            defer allocator.free(png_data);
            try stdout.writeAll(png_data);
        } else if (format == .ascii) {
            try render_terminal.renderAscii(stdout, matrix, render_opts.quiet_zone);
        } else {
            try render_terminal.renderAnsi(stdout, matrix, render_opts.quiet_zone);
        }
    }
}
