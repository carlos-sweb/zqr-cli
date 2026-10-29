const std = @import("std");
const zargs = @import("zargs");
const z_print = @import("z_print");
const print_util = @import("print_util.zig");

const cmd_encode = @import("cmd_encode.zig");
const cmd_decode = @import("cmd_decode.zig");
const cmd_info = @import("cmd_info.zig");

pub const VERSION = "0.2.0";
pub const ZQR_VERSION = "1.4.0";

fn printVersion() !void {
    try print_util.printStdout("zqr {s} (z-libqr {s})\n", .{ VERSION, ZQR_VERSION });
}

fn printRootHelp() !void {
    try print_util.printStdout("{s:bold:cyan}zqr{s:reset} — QR Code Model 2 encoder and renderer (v{s})\n\n", .{ "", "", VERSION });
    try print_util.printStdout("{s:bold}USAGE:{s:reset}\n", .{""});
    try print_util.printStdout("  zqr <COMMAND> [OPTIONS] [DATA]\n", .{});
    try print_util.printStdout("  zqr -V, --version\n", .{});
    try print_util.printStdout("  zqr -h, --help\n\n", .{});

    try print_util.printStdout("{s:bold}COMMANDS:{s:reset}\n", .{""});
    try print_util.printStdout("  {s:bold:green}encode{s:reset}, {s:bold:green}e{s:reset}    Encode data and render to SVG, PNG, ANSI, or ASCII\n", .{ "", "", "", "" });
    try print_util.printStdout("  {s:bold:green}decode{s:reset}, {s:bold:green}d{s:reset}    Decode QR code matrix from ASCII or terminal text\n", .{ "", "", "", "" });
    try print_util.printStdout("  {s:bold:green}info{s:reset}, {s:bold:green}i{s:reset}      Analyze payload capacity, minimum versions, and optimal segments\n\n", .{ "", "", "", "" });

    try print_util.printStdout("{s:bold}EXAMPLES:{s:reset}\n", .{""});
    try print_util.printStdout("  # Display QR code in terminal using ANSI half-blocks:\n", .{});
    try print_util.printStdout("  zqr encode \"Hello World\"\n\n", .{});
    try print_util.printStdout("  # Pipe encode to decode roundtrip:\n", .{});
    try print_util.printStdout("  zqr encode \"Hello World\" -f ascii | zqr decode -\n\n", .{});
    try print_util.printStdout("  # Generate scalable SVG vector:\n", .{});
    try print_util.printStdout("  zqr encode \"https://example.com\" -o code.svg\n\n", .{});
    try print_util.printStdout("  # Decode from ASCII file with symbol metadata:\n", .{});
    try print_util.printStdout("  zqr decode -i qr.txt --verbose\n\n", .{});
    try print_util.printStdout("  # Analyze minimum version required across ECC levels:\n", .{});
    try print_util.printStdout("  zqr info \"Text to analyze\"\n\n", .{});
    try print_util.printStdout("Run '{s:bold}zqr <COMMAND> --help{s:reset}' for detailed options on each command.\n", .{ "", "" });
}

fn rootAction(allocator: std.mem.Allocator, args: []const [:0]const u8) anyerror!void {
    _ = allocator;
    if (args.len == 0 or std.mem.eql(u8, args[0], "-h") or std.mem.eql(u8, args[0], "--help")) {
        try printRootHelp();
        return;
    }
    if (std.mem.eql(u8, args[0], "-V") or std.mem.eql(u8, args[0], "--version")) {
        try printVersion();
        return;
    }
    // If unknown command or flag at root level
    try print_util.printStderr("{s:bold:red}error:{s:reset} unknown command or option '{s}'. See 'zqr --help'.\n", .{ "", args[0] });
    return error.InvalidCommand;
}

pub const root_command = zargs.Commands.Command{
    .name = "zqr",
    .help = "QR Code Model 2 encoder and renderer",
    .children = &.{
        .{
            .name = "encode",
            .alias = "e",
            .help = "Encode data and render to SVG, PNG, ANSI, or ASCII",
            .action = cmd_encode.run,
        },
        .{
            .name = "decode",
            .alias = "d",
            .help = "Decode QR code matrix from ASCII or terminal text",
            .action = cmd_decode.run,
        },
        .{
            .name = "info",
            .alias = "i",
            .help = "Analyze payload capacity, versions, and optimal segments",
            .action = cmd_info.run,
        },
    },
    .action = rootAction,
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    var it = init.minimal.args.iterate();
    const args = try zargs.collectProcessArgs(allocator, &it);
    defer allocator.free(args);

    if (args.len == 0) {
        try printRootHelp();
        return;
    }

    if (std.mem.eql(u8, args[0], "-V") or std.mem.eql(u8, args[0], "--version")) {
        try printVersion();
        return;
    }

    if (std.mem.eql(u8, args[0], "-h") or std.mem.eql(u8, args[0], "--help")) {
        try printRootHelp();
        return;
    }

    zargs.Commands.dispatch(root_command, allocator, args) catch |err| {
        const exit_code: u8 = switch (err) {
            error.InputOutput, error.MissingInputData, error.FileNotFound, error.AccessDenied, error.ReadFailed, error.WriteFailed => 2,
            else => 1,
        };
        std.process.exit(exit_code);
    };
}

test {
    _ = @import("tests.zig");
}
