const std = @import("std");
const clap = @import("clap");

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == false);
    const allocator = gpa.allocator();

    const params = comptime [_]clap.Param(clap.Help){
        clap.parseParam("-h, --help            Display this help and exit.") catch unreachable,
        clap.parseParam("-o, --output <PATH>   Output file path (stdout is used if not specified).") catch unreachable,
        clap.parseParam("-s, --string          Specifies that the input is a Zig string literal.\nOutput will be the parsed string.") catch unreachable,
        clap.parseParam("<INPUT>               ") catch unreachable,
    };

    var diag = clap.Diagnostic{};
    var args = clap.parse(clap.Help, &params, .{ .diagnostic = &diag, .allocator = allocator }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer args.deinit();

    if (args.flag("--help")) {
        const writer = std.io.getStdErr().writer();
        //try writer.writeAll("Usage: grindcov [options] -- <cmd> [<args>...]\n\n");
        //try writer.writeAll("Available options:\n");
        try writer.writeAll("Usage: zigescape ");
        try clap.usage(writer, &params);
        try writer.writeAll("\n\n");
        try writer.writeAll(
            \\<INPUT>: Either a path to a file or a Zig string literal (if using --string)
            \\         If <INPUT> is not specified, then stdin is used.
        );
        try writer.writeAll("\n\n");
        try writer.writeAll("Available options:\n");
        try clap.help(writer, &params);
        return;
    }

    const outfile = outfile: {
        if (args.option("--output")) |output_path| {
            break :outfile try std.fs.cwd().createFile(output_path, .{});
        } else {
            break :outfile std.io.getStdOut();
        }
    };
    const writer = outfile.writer();

    var data_allocated = false;
    const data = data: {
        if (args.flag("--string") and args.positionals().len > 0) {
            break :data args.positionals()[0];
        }
        const infile = infile: {
            if (args.positionals().len > 0) {
                const path = args.positionals()[0];
                break :infile try std.fs.cwd().openFile(path, .{});
            } else {
                break :infile std.io.getStdIn();
            }
        };
        data_allocated = true;
        break :data try infile.readToEndAlloc(allocator, std.math.maxInt(usize));
    };
    defer if (data_allocated) allocator.free(data);

    if (args.flag("--string")) {
        var line = data;
        if (std.mem.indexOfAny(u8, line, "\r\n")) |line_end| {
            line = line[0..line_end];
        }
        var line_allocated = false;
        // wrap in quotes if it's not already
        if (line.len < 2 or line[0] != '"' or line[line.len - 1] != '"') {
            var buf = try allocator.alloc(u8, line.len + 2);
            buf[0] = '"';
            std.mem.copy(u8, buf[1..], line);
            buf[buf.len - 1] = '"';

            line = buf;
            line_allocated = true;
        }
        defer if (line_allocated) allocator.free(line);

        const parsed = try std.zig.string_literal.parseAlloc(allocator, line);
        defer allocator.free(parsed);

        try writer.writeAll(parsed);
    } else {
        try writer.print("\"{}\"\n", .{std.zig.fmtEscapes(data)});
    }
}
