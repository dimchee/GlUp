const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const lib = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize
    });
    
    const gl_bindings = @import("zigglgen").generateBindingsModule(b, .{ .api = .gles, .version = .@"3.2" });
    const glfw = b.dependency("zglfw", .{ .target = target, .optimize = optimize });
    const zalgebra = b.dependency("zalgebra", .{ .target = target, .optimize = optimize });
    const zigimg = b.dependency("zigimg", .{ .target = target, .optimize = optimize });
    lib.addImport("gl", gl_bindings);
    lib.addImport("glfw", glfw.module("glfw"));
    lib.addImport("zalgebra", zalgebra.module("zalgebra"));
    lib.addImport("zigimg", zigimg.module("zigimg"));
    lib.linkLibrary(glfw.artifact("zglfw"));


    const example = b.addExecutable(.{
        .name = "basic_example",
        .root_source_file = b.path("examples/basic/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    example.root_module.addImport("glup", lib);
    // example.root_module.linkLibrary(glfw.artifact("zglfw"));
    b.installArtifact(example);
    const run_cmd = b.addRunArtifact(example);
    run_cmd.step.dependOn(b.getInstallStep());
    b.step("run", "Run the app").dependOn(&run_cmd.step);
}
