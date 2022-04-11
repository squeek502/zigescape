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

    if (argres.args.help) {
        const writer = std.io.getStdErr().writer();
        try writer.writeAll("Usage: zigescape ");
        try clap.usage(writer, clap.Help, &params);
        try writer.writeAll("\n\n");
        try writer.writeAll(
            \\<INPUT>: Either a path to a file or a Zig string literal (if using --string)
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
        if (argres.args.string and argres.positionals.len > 0) {
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

    if (argres.args.string) {
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
