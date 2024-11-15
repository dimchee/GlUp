const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "default",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const gl_bindings = @import("zigglgen").generateBindingsModule(b, .{ .api = .gles, .version = .@"3.2" });
    const glfw = b.dependency("zglfw", .{ .target = target, .optimize = optimize });
    const zalgebra = b.dependency("zalgebra", .{ .target = target, .optimize = optimize });
    const zigimg = b.dependency("zigimg", .{ .target = target, .optimize = optimize });
    exe.root_module.addImport("gl", gl_bindings);
    exe.root_module.addImport("glfw", glfw.module("glfw"));
    exe.root_module.addImport("zalgebra", zalgebra.module("zalgebra"));
    exe.root_module.addImport("zigimg", zigimg.module("zigimg"));
    exe.linkLibrary(glfw.artifact("zglfw"));

    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    b.step("run", "Run the app").dependOn(&run_cmd.step);
}
