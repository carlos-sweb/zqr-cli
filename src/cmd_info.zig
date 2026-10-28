const std = @import("std");
const zargs = @import("zargs");
const zqr = @import("zqr");
const io_util = @import("io_util.zig");
const print_util = @import("print_util.zig");

const Flag = zargs.Declarative.Flag;
const Positional = zargs.Declarative.Positional;

pub const InfoArgs = struct {
    read_from: Flag([]const u8, .{ .short = 'i', .long = "read-from", .help = "Read payload from file or '-' for stdin", .default = "" }),
    kanji: Flag(bool, .{ .long = "kanji", .help = "Enable JIS X 0208 Kanji mode", .default = false }),
    optimize: Flag(bool, .{ .help = "Optimal multi-mode DP segmentation", .default = true }),
    help: Flag(bool, .{ .short = 'h', .long = "help", .help = "Show this help and exit", .default = false }),
    data: Positional([]const u8, .{ .help = "Data payload to analyze", .default = "" }),
};

pub fn run(allocator: std.mem.Allocator, args: []const [:0]const u8) anyerror!void {
    var diag: zargs.Declarative.Diagnostics = .{};
    const parsed = zargs.Declarative.parseStruct(InfoArgs, allocator, args, &diag) catch |err| {
        try print_util.printStderr("{s:red:bold} invalid option: {s}\n", .{ "error:", diag.raw orelse diag.field orelse @errorName(err) });
        return err;
    };

    if (parsed.help.value) {
        const usage = try zargs.Declarative.usageAlloc(InfoArgs, allocator, "Usage: zqr info [OPTIONS] [DATA]\n\nOptions:");
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

    try print_util.printStdout("{s:cyan:bold} Payload Analysis\n", .{"zqr info:"});
    try print_util.printStdout("  Payload length: {u} bytes\n\n", .{payload.len});

    try print_util.printStdout("{s:bold}\n", .{"Minimum Version Required by Error Correction Level:"});

    const ecc_levels = [_]struct { name: []const u8, ecc: zqr.Ecc, desc: []const u8 }{
        .{ .name = "Low (L)", .ecc = .low, .desc = "~7% recovery" },
        .{ .name = "Medium (M)", .ecc = .medium, .desc = "~15% recovery (default)" },
        .{ .name = "Quartile (Q)", .ecc = .quartile, .desc = "~25% recovery" },
        .{ .name = "High (H)", .ecc = .high, .desc = "~30% recovery" },
    };

    inline for (ecc_levels) |lvl| {
        var buf: [zqr.Tier3.max_buffer_len]u8 = undefined;
        const res = zqr.Tier3.encodeAdvanced(&buf, payload, .{
            .ecc = lvl.ecc,
            .kanji = parsed.kanji.value,
            .optimize = parsed.optimize.value,
        });

        if (res) |matrix| {
            try print_util.printStdout("  {s:<15} Version {u:>2} ({u:>3}x{u:<3} modules) - {s}\n", .{
                lvl.name, matrix.version, matrix.size, matrix.size, lvl.desc,
            });
        } else |_| {
            try print_util.printStdout("  {s:<15} Exceeds Version 40 capacity (requires Structured Append)\n", .{
                lvl.name,
            });
        }
    }

    try print_util.printStdout("\n", .{});
}
