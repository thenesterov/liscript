const std = @import("std");

const Step = std.Build.Step;
const ResolvedTarget = std.Build.ResolvedTarget;
const OptimizeMode = std.builtin.OptimizeMode;

const IsoclineCLibrary = struct {
    lib: *Step.Compile,
    module: *std.Build.Module,

    fn init(b: *std.Build, target: ResolvedTarget, optimize: OptimizeMode) !IsoclineCLibrary {
        const src_path = try IsoclineCLibrary.getSrcPath(b);

        const translate_c = b.addTranslateC(.{
            .root_source_file = IsoclineCLibrary.getHeaderFile(b, src_path),
            .target = target,
            .optimize = optimize,
        });

        translate_c.addIncludePath(.{ .cwd_relative = src_path });

        const lib = b.addLibrary(.{
            .name = "isocline",
            .linkage = .static,
            .root_module = b.createModule(.{
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            }),
        });

        lib.root_module.addCSourceFile(.{
            .file = IsoclineCLibrary.getSourceFile(b, src_path),
            .flags = &.{"-std=c11"},
        });

        return .{
            .lib = lib,
            .module = translate_c.createModule(),
        };
    }

    fn getSrcPath(b: *std.Build) ![]const u8 {
        return b.graph.environ_map.get("ISOCLINE_SRC") orelse error.NoIsoclineSrc;
    }

    fn getHeaderFile(b: *std.Build, src_path: []const u8) std.Build.LazyPath {
        const header_path = b.fmt("{s}/include/isocline.h", .{src_path});

        return .{ .cwd_relative = header_path };
    }

    fn getSourceFile(b: *std.Build, src_path: []const u8) std.Build.LazyPath {
        const source_path = b.fmt("{s}/src/isocline.c", .{src_path});

        return .{ .cwd_relative = source_path };
    }
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const str_utils = b.addModule("str-utils", .{
        .root_source_file = b.path("src/str/utils.zig"),
        .target = target,
    });

    const core = b.addModule("liscript-core", .{
        .root_source_file = b.path("src/core/root.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "str", .module = str_utils },
        },
    });

    const isocline_c: IsoclineCLibrary = try .init(b, target, optimize);

    const isocline = b.addModule("isocline", .{
        .root_source_file = b.path("src/isocline/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "isocline_c", .module = isocline_c.module },
        },
    });

    const repl = b.addExecutable(.{
        .name = "liscript-repl",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/repl/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "liscript", .module = core },
                .{ .name = "isocline", .module = isocline },
                .{ .name = "str", .module = str_utils },
            },
        }),
    });

    repl.root_module.linkLibrary(isocline_c.lib);

    b.installArtifact(repl);

    const run_repl_step = b.step("repl", "Run the repl");

    const run_repl_cmd = b.addRunArtifact(repl);
    run_repl_step.dependOn(&run_repl_cmd.step);

    run_repl_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_repl_cmd.addArgs(args);
    }
}
