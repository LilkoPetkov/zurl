const __zepinj__ = @import(".zep/injector.zig");
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    __zepinj__.imp(b, exe_mod);

    const exe = b.addExecutable(.{
        .name = "zurl",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);
}
