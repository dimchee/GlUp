const std = @import("std");

pub fn build(b: *std.Build) void {
    const opts = .{
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    };
    const mod = b.createModule(.{
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

    mod.addCSourceFile(.{ .file = lodepng.path("lodepng.c") });

    mod.addIncludePath(lodepng.path(""));
    mod.link_libcpp = true;

    mod.addImport("gl", gl_bindings);
    mod.addImport("glfw", glfw.module("glfw"));
    mod.addImport("zm", zm.module("zm"));
    mod.linkLibrary(glfw.artifact("zglfw"));

    for (examples) |name| {
        const path = std.fmt.allocPrint(b.allocator, "examples/{s}.zig", .{name});
        const example = b.addExecutable(.{
            .name = name,
            .root_source_file = b.path(path catch @panic("...")),
            .target = opts.target,
            .optimize = opts.optimize,
            .link_libc = true, // https://ziggit.dev/t/debugging-and-allocating-memory-in-code-loaded-from-dynamic-libraries/2639
            // .use_lld = false, // https://github.com/Not-Nik/raylib-zig/issues/219
            // .use_lld = false not working (glfw error)
        });
        example.root_module.addImport("glup", mod);
        b.installArtifact(example);
        const run_cmd = b.addRunArtifact(example);
        b.step(name, "Run example").dependOn(&run_cmd.step);
        if (std.mem.eql(u8, name, "hot-reloading")) {
            b.step("run", "Run").dependOn(&run_cmd.step);
            const example_mod = b.createModule(.{
                .root_source_file = b.path(path catch @panic("...")),
                .target = opts.target,
                .optimize = opts.optimize,
                .link_libc = true, // https://ziggit.dev/t/debugging-and-allocating-memory-in-code-loaded-from-dynamic-libraries/2639
            });
            example_mod.addImport("glup", mod);
            example_mod.addImport("gl", gl_bindings);
            example_mod.addImport("glfw", glfw.module("glfw"));
            example_mod.addImport("zm", zm.module("zm"));
            const so = b.addLibrary(.{
                .linkage = .dynamic,
                .name = "reloadable",
                .root_module = example_mod,
            });
            const so_art = b.addInstallArtifact(so, .{});
            b.step("hot", "Compile shared library").dependOn(&so_art.step);
        }
    }
}

const examples = [_][]const u8{
    "window",
    "triangle",
    "shaders",
    "textures",
    "transformations",
    "coordinate_systems",
    "camera",
    "hot-reloading",
};
