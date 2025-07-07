const std = @import("std");
const glup = @import("glup");
const cube = @import("cube.zig");
const vec = glup.zm.vec;

fn loop(window: *glup.glfw.Window, state: *State) callconv(.c) void {
    const rotationSensitivity = 0.002;
    const cameraSpeed = 0.05;
    glup.gl.Clear(glup.gl.COLOR_BUFFER_BIT | glup.gl.DEPTH_BUFFER_BIT);
    glup.gl.ClearColor(0.1, 0.1, 0.1, 1.0);

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
    const lightPos: glup.Vec3 = .{ 1.2, 1.0, 2.0 };
    state.shader.use(.{
        .model = glup.zm.Mat4f.identity(),
        .view = state.camera.view(),
        .projection = state.camera.projection(@intCast(width), @intCast(height)),
        .viewPos = state.camera.pos,
        .material = .{
            .ambient = .{ 1.0, 0.5, 0.31 },
            .diffuse = .{ 1.0, 0.5, 0.31 },
            .specular = .{ 0.5, 0.5, 0.5 },
            .shininess = 32.0,
        },
        .light = .{
            .position = lightPos,
            .ambient = .{ 0.2, 0.2, 0.2 },
            .diffuse = .{ 0.5, 0.5, 0.5 },
            .specular = .{ 1.0, 1.0, 1.0 },
        },
    });
    state.mesh.draw();
    state.lightShader.use(.{
        .model = glup.zm.Mat4f.translationVec3(lightPos)
            .multiply(glup.zm.Mat4f.scalingVec3(@splat(0.2))),
        .view = state.camera.view(),
        .projection = state.camera.projection(@intCast(width), @intCast(height)),
    });
    state.mesh.draw();
}

const Mat4 = glup.zm.Mat4f;
const Material = struct {
    ambient: glup.Vec3,
    diffuse: glup.Vec3,
    specular: glup.Vec3,
    shininess: f32,
};
const Light = struct {
    position: glup.Vec3,
    ambient: glup.Vec3,
    diffuse: glup.Vec3,
    specular: glup.Vec3,
};
const Uniforms = struct {
    model: Mat4,
    view: Mat4,
    projection: Mat4,
    material: Material,
    light: Light,
    viewPos: glup.Vec3,
};
const Shader = glup.Shader(Uniforms, cube.Vertex);
const LightUniforms = struct { model: Mat4, view: Mat4, projection: Mat4 };
const LightShader = glup.Shader(LightUniforms, cube.Vertex);
const State = struct {
    mesh: glup.Mesh(cube.Vertex),
    shader: Shader,
    lightShader: LightShader,
    camera: glup.Camera,
};

pub fn main() !void {
    var app = try glup.App.init(800, 640, "App");
    glup.gl.Enable(glup.gl.DEPTH_TEST);
    glup.Mouse.setFpsMode(app.window);

    var shWatch = glup.Watch.init("examples/materials.glsl");
    var state = State{
        .shader = try Shader.initFromFile(shWatch.path),
        .lightShader = try LightShader.init(
            "void main() { gl_Position = projection * view * model * vec4(aPos, 1.0); }",
            "void main() { FragColor = vec4(1.0); }",
        ),
        .mesh = glup.Mesh(cube.Vertex).init(&cube.vertices, &cube.triangles),
        .camera = glup.Camera.init(.{ 1, 2, 5 }, .{ -1, -2, -5 }),
    };

    while (app.windowOpened()) |window| {
        if (try shWatch.changed()) {
            state.shader.deinit();
            state.shader = try Shader
                .initFromFile(shWatch.path);
        }
        loop(window, &state);
    }
}
