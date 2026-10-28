const std = @import("std");
const z_print = @import("z_print");

pub fn printStdout(comptime pattern: []const u8, args: anytype) !void {
    var buf: [4096]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);
    try z_print.z_print_mod.z_print(&writer, pattern, args);
    try z_print.stdio.writeStdout(writer.buffered());
}

pub fn printStderr(comptime pattern: []const u8, args: anytype) !void {
    var buf: [4096]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);
    try z_print.z_print_mod.z_print(&writer, pattern, args);
    try z_print.stdio.writeStderr(writer.buffered());
}
