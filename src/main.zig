const std = @import("std");
const clap = @import("clap");

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const params = comptime [_]clap.Param(clap.Help){
        clap.parseParam("-h, --help            Display this help and exit.") catch unreachable,
        clap.parseParam("-o, --output <PATH>   Output file path (stdout is used if not specified).") catch unreachable,
        clap.parseParam("-s, --string          Specifies that the input is a Zig string literal.\nOutput will be the parsed string.") catch unreachable,
        clap.parseParam("-x, --hex             Specifies that the input is a series of hex bytes\nin string format (e.g. \"0A B4 10\").\nOutput will be a Zig string literal.") catch unreachable,
        clap.parseParam("<INPUT>               ") catch unreachable,
    };
    const parsers = comptime .{
        .PATH = clap.parsers.string,
        .INPUT = clap.parsers.string,
    };

    var diag = clap.Diagnostic{};
    var argres = clap.parse(clap.Help, &params, parsers, .{ .diagnostic = &diag, .allocator = allocator }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer argres.deinit();

    if (argres.args.help != 0) {
        const writer = std.io.getStdErr().writer();
        try writer.writeAll("Usage: zigescape ");
        try clap.usage(writer, clap.Help, &params);
        try writer.writeAll("\n\n");
        try writer.writeAll(
            \\<INPUT>: Either a path to a file, or a Zig string literal (if using --string),
            \\         or a series of hex bytes in string format (if using --hex).
            \\         If <INPUT> is not specified, then stdin is used.
        );
        try writer.writeAll("\n\n");
        try writer.writeAll("Available options:\n\n");
        try clap.help(writer, clap.Help, &params, .{
            .markdown_lite = false,
            .description_on_new_line = false,
            .description_indent = 4,
            .indent = 0,
            .spacing_between_parameters = 1,
        });
        return;
    }

    const outfile = outfile: {
        if (argres.args.output) |output_path| {
            break :outfile try std.fs.cwd().createFile(output_path, .{});
        } else {
            break :outfile std.io.getStdOut();
        }
    };
    const writer = outfile.writer();

    var data_allocated = false;
    const data = data: {
        if ((argres.args.string != 0 or argres.args.hex != 0) and argres.positionals.len > 0) {
            break :data argres.positionals[0];
        }
        const infile = infile: {
            if (argres.positionals.len > 0) {
                const path = argres.positionals[0];
                break :infile try std.fs.cwd().openFile(path, .{});
            } else {
                break :infile std.io.getStdIn();
            }
        };
        data_allocated = true;
        break :data try infile.readToEndAlloc(allocator, std.math.maxInt(usize));
    };
    defer if (data_allocated) allocator.free(data);

    if (argres.args.string != 0) {
        var line = data;
        if (std.mem.indexOfAny(u8, line, "\r\n")) |line_end| {
            line = line[0..line_end];
        }
        var line_allocated = false;
        // wrap in quotes if it's not already
        if (line.len < 2 or line[0] != '"' or line[line.len - 1] != '"') {
            var buf = try allocator.alloc(u8, line.len + 2);
            buf[0] = '"';
            @memcpy(buf[1..][0..line.len], line);
            buf[buf.len - 1] = '"';

            line = buf;
            line_allocated = true;
        }
        defer if (line_allocated) allocator.free(line);

        const parsed = try std.zig.string_literal.parseAlloc(allocator, line);
        defer allocator.free(parsed);

        try writer.writeAll(parsed);
    } else {
        var to_escape = data;
        if (argres.args.hex != 0) {
            var buf = std.ArrayList(u8).init(allocator);
            errdefer buf.deinit();
            var err_loc: ErrorLoc = undefined;
            parseHexToData(buf.writer(), data, &err_loc) catch |err| switch (err) {
                error.UnfinishedHexByte, error.UnexpectedChar => {
                    std.debug.print("{} at offset {}: '{s}'\n", .{ err, err_loc.start_index, std.fmt.fmtSliceEscapeUpper(err_loc.slice(data)) });
                    std.os.exit(1);
                },
                else => |e| return e,
            };
            to_escape = try buf.toOwnedSlice();
        }
        defer if (argres.args.hex != 0) allocator.free(to_escape);
        try writer.print("\"{}\"\n", .{std.zig.fmtEscapes(to_escape)});
    }
}

const ErrorLoc = struct {
    start_index: usize,
    end_index: usize,

    pub fn slice(self: ErrorLoc, data: []const u8) []const u8 {
        return data[self.start_index..self.end_index];
    }
};

fn parseHexToData(writer: anytype, hex_string: []const u8, err_loc: *ErrorLoc) !void {
    var byte: u8 = 0;
    var i: usize = 0;
    var hex_len: u2 = 0;
    while (i < hex_string.len) : (i += 1) {
        const c = hex_string[i];
        switch (c) {
            '0'...'9', 'a'...'f', 'A'...'F' => {
                if (byte != 0) byte *= 16;
                byte += std.fmt.charToDigit(c, 16) catch unreachable;
                hex_len += 1;
                if (hex_len == 2) {
                    hex_len = 0;
                    try writer.writeByte(byte);
                    byte = 0;
                }
            },
            ' ', '\t', '\r', '\n' => {
                if (hex_len != 0) {
                    err_loc.* = .{ .start_index = i - hex_len, .end_index = i };
                    return error.UnfinishedHexByte;
                }
            },
            else => {
                err_loc.* = .{ .start_index = i, .end_index = i + 1 };
                return error.UnexpectedChar;
            },
        }
    }
    if (hex_len != 0) {
        err_loc.* = .{ .start_index = i - hex_len, .end_index = i };
        return error.UnfinishedHexByte;
    }
}

test "parseHexToData" {
    var buf = std.ArrayList(u8).init(std.testing.allocator);
    defer buf.deinit();

    var err_loc: ErrorLoc = undefined;
    try parseHexToData(
        buf.writer(),
        "2f2f2120e29494e2 94 80 E2 94\t80 \t \t e2 94 00",
        &err_loc,
    );
    var base64_buf: [256]u8 = undefined;
    const base64_data = std.base64.standard.Encoder.encode(&base64_buf, buf.items);

    try std.testing.expectEqualSlices(
        u8,
        "Ly8hIOKUlOKUgOKUgOKUAA==",
        base64_data,
    );

    buf.clearRetainingCapacity();
    try std.testing.expectError(error.UnfinishedHexByte, parseHexToData(buf.writer(), "153 43 82", &err_loc));
    try std.testing.expectEqual(@as(usize, 2), err_loc.start_index);
    try std.testing.expectEqual(@as(usize, 3), err_loc.end_index);
    try std.testing.expectEqualSlices(u8, "3", err_loc.slice("153 43 82"));

    buf.clearRetainingCapacity();
    try std.testing.expectError(error.UnfinishedHexByte, parseHexToData(buf.writer(), "15 43 8", &err_loc));
    try std.testing.expectEqual(@as(usize, 6), err_loc.start_index);
    try std.testing.expectEqual(@as(usize, 7), err_loc.end_index);
    try std.testing.expectEqualSlices(u8, "8", err_loc.slice("15 43 8"));

    buf.clearRetainingCapacity();
    try std.testing.expectError(error.UnexpectedChar, parseHexToData(buf.writer(), "15 4Z 5c", &err_loc));
    try std.testing.expectEqual(@as(usize, 4), err_loc.start_index);
    try std.testing.expectEqual(@as(usize, 5), err_loc.end_index);
    try std.testing.expectEqualSlices(u8, "Z", err_loc.slice("15 4Z 5c"));
}
