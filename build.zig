const std = @import("std");

pub fn build(b: *std.Build) void {
    const opts = .{
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    };
    const lib = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = opts.target,
        .optimize = opts.optimize,
    });
    const gl_bindings = @import("zigglgen").generateBindingsModule(b, .{
        .api = .gles,
        .version = .@"3.2",
    });
    const glfw = b.dependency("zglfw", opts);
    const zm = b.dependency("zm", opts);
    const lodepng = b.dependency("lodepng", opts);

    const cp = b.addSystemCommand(&.{"cp"});
    cp.addFileArg(lodepng.path("lodepng.cpp"));
    cp.addFileArg(lodepng.path("lodepng.c"));
    b.getInstallStep().dependOn(&cp.step);

    lib.addCSourceFile(.{ .file = lodepng.path("lodepng.c") });

    lib.addIncludePath(lodepng.path(""));
    lib.link_libcpp = true;

    lib.addImport("gl", gl_bindings);
    lib.addImport("glfw", glfw.module("glfw"));
    lib.addImport("zm", zm.module("zm"));
    lib.linkLibrary(glfw.artifact("zglfw"));

    const example = b.addExecutable(.{
        .name = "example_texture",
        .root_source_file = b.path("examples/camera.zig"),
        .target = opts.target,
        .optimize = opts.optimize,
    });
    example.root_module.addImport("glup", lib);
    // example.root_module.linkLibrary(glfw.artifact("zglfw"));
    b.installArtifact(example);
    const run_cmd = b.addRunArtifact(example);
    run_cmd.step.dependOn(b.getInstallStep());
    b.step("run", "Run the app").dependOn(&run_cmd.step);
}
