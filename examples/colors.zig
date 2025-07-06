const std = @import("std");
const glup = @import("glup");
const cube = @import("cube.zig");
const vec = glup.zm.vec;

fn loop(window: *glup.glfw.Window, state: *State) callconv(.c) void {
    const rotationSensitivity = 0.002;
    const cameraSpeed = 0.05;
    glup.gl.Clear(glup.gl.COLOR_BUFFER_BIT | glup.gl.DEPTH_BUFFER_BIT);
    glup.gl.ClearColor(0, 0, 1, 1);

    var movement: @Vector(3, f32) = .{ 0, 0, 0 };
    for (glup.Keyboard.getActions(window, @Vector(3, f32), &.{
        .{ .key = glup.glfw.KeyW, .action = .{ 0, 0, 1 } },
        .{ .key = glup.glfw.KeyS, .action = .{ 0, 0, -1 } },
        .{ .key = glup.glfw.KeyD, .action = .{ 1, 0, 0 } },
        .{ .key = glup.glfw.KeyA, .action = .{ -1, 0, 0 } },
        .{ .key = glup.glfw.KeySpace, .action = .{ 0, 1, 0 } },
        .{ .key = glup.glfw.KeyLeftShift, .action = .{ 0, -1, 0 } },
    })) |v| movement += v;
    const mouseOffsets = glup.Mouse.getOffsets();
    state.camera.update(.{
        .position = vec.scale(movement, cameraSpeed),
        .rotation = vec.scale(mouseOffsets.position, rotationSensitivity),
        .zoom = mouseOffsets.scroll[1],
    });

    var width: c_int = undefined;
    var height: c_int = undefined;
    glup.glfw.getWindowSize(window, &width, &height);
    state.shader.use(.{
        .model = glup.zm.Mat4f.identity(),
        .view = state.camera.view(),
        .projection = state.camera.projection(@intCast(width), @intCast(height)),
        .objectColor = .{ 1.0, 0.5, 0.31 },
        .lightColor = .{ 1.0, 1.0, 1.0 },
    });
    state.mesh.draw();
    state.lightShader.use(.{
        .model = glup.zm.Mat4f.translation(1.2, 1.0, 2.0)
            .multiply(glup.zm.Mat4f.scalingVec3(@splat(0.2))),
        .view = state.camera.view(),
        .projection = state.camera.projection(@intCast(width), @intCast(height)),
        .objectColor = .{ 1.0, 0.0, 0.0 },
        .lightColor = .{ 1.0, 1.0, 1.0 },
    });
    state.mesh.draw();
}

const Mat = glup.zm.Mat4f;

const Uniforms = struct {
    model: Mat,
    view: Mat,
    projection: Mat,
    objectColor: glup.Vec3,
    lightColor: glup.Vec3,
};
const Shader = glup.Shader(Uniforms, cube.Vertex);

const Rld = glup.Reloader(.{ .loop = &loop }, glup.App.postReload);
comptime {
    _ = Rld;
}

const State = struct {
    mesh: glup.Mesh(cube.Vertex),
    shader: Shader,
    lightShader: Shader,
    camera: glup.Camera,
};


pub fn main() !void {
    var rld = try Rld.init();
    var app = try glup.App.init(800, 640, "App");
    glup.gl.Enable(glup.gl.DEPTH_TEST);
    glup.Mouse.setFpsMode(app.window);

    var state = State{
        .shader = try Shader.initFromFile("examples/colors_shader.glsl"),
        .lightShader = try Shader.init(
            "void main() { gl_Position = projection * view * model * vec4(aPos, 1.0); }",
            "void main() { FragColor = vec4(1.0); }",
        ),
        .mesh = glup.Mesh(cube.Vertex).init(&cube.vertices, &cube.triangles),
        .camera = glup.Camera.init(.{ 0, 0, -5 }, .{ 0, 0, 1 }),
    };
    var shWatch = glup.Watch.init("examples/colors_shader.glsl");

    while (app.windowOpened()) |window| {
        try rld.reload();
        if (try shWatch.changed()) {
            state.shader.deinit();
            state.shader = try Shader.initFromFile("examples/colors_shader.glsl");
        }
        rld.reg.loop(window, &state);
    }
}
