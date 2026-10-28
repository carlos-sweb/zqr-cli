const std = @import("std");

/// Returns true if stdout is connected to a terminal (TTY).
pub fn isStdoutTty() bool {
    return std.posix.system.isatty(std.posix.STDOUT_FILENO) != 0;
}

/// Returns true if stdin is connected to a terminal (TTY).
pub fn isStdinTty() bool {
    return std.posix.system.isatty(std.posix.STDIN_FILENO) != 0;
}

fn posixWrite(fd: std.posix.fd_t, data: []const u8) !usize {
    const rc = std.c.write(fd, data.ptr, data.len);
    if (rc < 0) return error.WriteFailed;
    return @intCast(rc);
}

fn posixRead(fd: std.posix.fd_t, buf: []u8) !usize {
    const rc = std.c.read(fd, buf.ptr, buf.len);
    if (rc < 0) return error.ReadFailed;
    return @intCast(rc);
}

pub const PosixWriter = struct {
    fd: std.posix.fd_t,

    pub fn writeAll(self: PosixWriter, data: []const u8) !void {
        var written: usize = 0;
        while (written < data.len) {
            const n = try posixWrite(self.fd, data[written..]);
            if (n == 0) return error.WriteZero;
            written += n;
        }
    }
};

pub fn stdoutWriter() PosixWriter {
    return .{ .fd = std.posix.STDOUT_FILENO };
}

pub fn stderrWriter() PosixWriter {
    return .{ .fd = std.posix.STDERR_FILENO };
}

pub fn readFdAlloc(allocator: std.mem.Allocator, fd: std.posix.fd_t) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(allocator);

    var buf: [4096]u8 = undefined;
    while (true) {
        const n = try posixRead(fd, &buf);
        if (n == 0) break;
        try list.appendSlice(allocator, buf[0..n]);
    }
    return list.toOwnedSlice(allocator);
}

pub fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const fd = try std.posix.openat(std.posix.AT.FDCWD, path, .{
        .ACCMODE = .RDONLY,
    }, 0);
    defer _ = std.posix.system.close(fd);
    return readFdAlloc(allocator, fd);
}

pub fn writeFile(path: []const u8, data: []const u8) !void {
    const fd = try std.posix.openat(std.posix.AT.FDCWD, path, .{
        .ACCMODE = .WRONLY,
        .CREAT = true,
        .TRUNC = true,
    }, 0o664);
    defer _ = std.posix.system.close(fd);

    var written: usize = 0;
    while (written < data.len) {
        const n = try posixWrite(fd, data[written..]);
        if (n == 0) return error.WriteZero;
        written += n;
    }
}

pub fn openFileWriter(path: []const u8) !struct {
    fd: std.posix.fd_t,
    pub fn close(self: @This()) void {
        _ = std.posix.system.close(self.fd);
    }
    pub fn writer(self: @This()) PosixWriter {
        return .{ .fd = self.fd };
    }
} {
    const fd = try std.posix.openat(std.posix.AT.FDCWD, path, .{
        .ACCMODE = .WRONLY,
        .CREAT = true,
        .TRUNC = true,
    }, 0o664);
    return .{ .fd = fd };
}

/// Reads payload data from positional argument, `--read-from` file, or stdin.
pub fn readPayload(allocator: std.mem.Allocator, pos_data: ?[]const u8, read_from: ?[]const u8) ![]u8 {
    if (read_from) |path| {
        if (std.mem.eql(u8, path, "-")) {
            return readFdAlloc(allocator, std.posix.STDIN_FILENO);
        } else {
            return readFileAlloc(allocator, path);
        }
    }

    if (pos_data) |data| {
        return allocator.dupe(u8, data);
    }

    // If stdin is piped, read from stdin
    if (!isStdinTty()) {
        const stdin_data = try readFdAlloc(allocator, std.posix.STDIN_FILENO);
        if (stdin_data.len > 0) return stdin_data;
    }

    return error.MissingInputData;
}

/// Formats a file output path for a given symbol index in a Structured Append sequence.
/// - If `path_pattern` contains `{n}`: replaces `{n}` with 1-based index (e.g. `qr_{n}.png` -> `qr_1.png`).
/// - If `path_pattern` contains `%d`: replaces `%d` with 1-based index.
/// - Otherwise: inserts `_01`, `_02`, etc., before the file extension (e.g. `qr.png` -> `qr_01.png`).
pub fn formatSequencePath(allocator: std.mem.Allocator, path_pattern: []const u8, idx: usize, total: usize) ![]u8 {
    _ = total;
    const num = idx + 1;

    if (std.mem.indexOf(u8, path_pattern, "{n}")) |pos| {
        const prefix = path_pattern[0..pos];
        const suffix = path_pattern[pos + 3 ..];
        return std.fmt.allocPrint(allocator, "{s}{d}{s}", .{ prefix, num, suffix });
    }

    if (std.mem.indexOf(u8, path_pattern, "%d")) |pos| {
        const prefix = path_pattern[0..pos];
        const suffix = path_pattern[pos + 2 ..];
        return std.fmt.allocPrint(allocator, "{s}{d}{s}", .{ prefix, num, suffix });
    }

    // Auto-insert `_01`, `_02` before extension
    const ext_pos = std.mem.lastIndexOfScalar(u8, path_pattern, '.');
    if (ext_pos) |pos| {
        const base = path_pattern[0..pos];
        const ext = path_pattern[pos..];
        return std.fmt.allocPrint(allocator, "{s}_{d:0>2}{s}", .{ base, num, ext });
    } else {
        return std.fmt.allocPrint(allocator, "{s}_{d:0>2}", .{ path_pattern, num });
    }
}

test "formatSequencePath replacements" {
    const testing = std.testing;
    const a = testing.allocator;

    const p1 = try formatSequencePath(a, "qr_{n}.png", 0, 3);
    defer a.free(p1);
    try testing.expectEqualStrings("qr_1.png", p1);

    const p2 = try formatSequencePath(a, "qr_%d.svg", 1, 3);
    defer a.free(p2);
    try testing.expectEqualStrings("qr_2.svg", p2);

    const p3 = try formatSequencePath(a, "code.png", 0, 3);
    defer a.free(p3);
    try testing.expectEqualStrings("code_01.png", p3);

    const p4 = try formatSequencePath(a, "output", 2, 3);
    defer a.free(p4);
    try testing.expectEqualStrings("output_03", p4);
}
