const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardOptimizeOption(.{});

    const clap = b.dependency("clap", .{
        .target = target,
        .optimize = mode,
    });
    const clap_module = clap.module("clap");

    const exe = b.addExecutable(.{
        .name = "zigescape",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = mode,
    });
    exe.root_module.addImport("clap", clap_module);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    {
        const release_step = b.step("release", "Build release binaries for all supported targets");
        const release_targets = &[_]std.Target.Query{
            .{ .cpu_arch = .x86_64, .os_tag = .macos },
            .{ .cpu_arch = .aarch64, .os_tag = .macos },
            .{ .cpu_arch = .aarch64, .os_tag = .linux },
            .{ .cpu_arch = .x86_64, .os_tag = .linux },
            .{ .cpu_arch = .x86, .os_tag = .linux },
            .{ .cpu_arch = .x86_64, .os_tag = .windows },
            .{ .cpu_arch = .x86, .os_tag = .windows },
        };
        for (release_targets) |release_target| {
            const resolved_release_target = b.resolveTargetQuery(release_target);
            const clap_release = b.dependency("clap", .{
                .target = resolved_release_target,
                .optimize = .ReleaseFast,
            });
            const release_exe = b.addExecutable(.{
                .name = "zigescape",
                .root_source_file = .{ .path = "src/main.zig" },
                .target = resolved_release_target,
                .optimize = .ReleaseFast,
                .single_threaded = true,
                .strip = true,
            });
            release_exe.root_module.addImport("clap", clap_release.module("clap"));

            const triple = release_target.zigTriple(b.allocator) catch unreachable;
            const install_dir = "release";
            const release_install = b.addInstallArtifact(
                release_exe,
                .{ .dest_dir = .{
                    .override = .{ .custom = install_dir },
                } },
            );
            release_install.dest_sub_path = b.fmt("{s}-{s}", .{
                triple, release_install.dest_sub_path,
            });
            release_step.dependOn(&release_install.step);
        }
    }
}
