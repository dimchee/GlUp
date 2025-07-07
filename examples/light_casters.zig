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
    var uniforms: Uniforms = .{
        .model = glup.zm.Mat4f.identity(),
        .view = state.camera.view(),
        .projection = state.camera.projection(@intCast(width), @intCast(height)),
        .viewPos = state.camera.pos,
        .material = .{
            .diffuse = state.texture_diffuse,
            .specular = state.texture_specular,
            .shininess = 32.0,
        },
        .dirLight = .{
            .direction = .{ -0.2, -1.0, -0.3 },
            .ambient = .{ 0.05, 0.05, 0.05 },
            .diffuse = .{ 0.4, 0.4, 0.4 },
            .specular = .{ 0.5, 0.5, 0.5 },
        },
        .spotLight = .{
            .position = state.camera.pos,
            .direction = state.camera.dir,
            .ambient = .{ 0.0, 0.0, 0.0 },
            .diffuse = .{ 1.0, 1.0, 1.0 },
            .specular = .{ 1.0, 1.0, 1.0 },
            .constant = 1.0,
            .linear = 0.09,
            .quadratic = 0.032,
            .cutOff = std.math.cos(std.math.rad_per_deg * 12.5),
            .outerCutOff = std.math.cos(std.math.rad_per_deg * 15),
        },
        .pointLight = undefined,
    };
    for (&uniforms.pointLight, state.light_positions) |*pointLight, pos| {
        pointLight.* = .{
            .position = pos,
            .ambient = .{ 0.05, 0.05, 0.05 },
            .diffuse = .{ 0.8, 0.8, 0.8 },
            .specular = .{ 1.0, 1.0, 1.0 },
            .constant = 1.0,
            .linear = 0.09,
            .quadratic = 0.032,
        };
    }
    for (state.cube_positions, 0..) |pos, i| {
        uniforms.model = glup.zm.Mat4f.translationVec3(pos)
            .multiply(glup.zm.Mat4f.rotation(
            .{ 1.0, 0.3, 0.5 },
            std.math.rad_per_deg * 20.0 * @as(f32, @floatFromInt(i)),
        ));
        state.shader.use(uniforms);
        state.mesh.draw();
    }
    for (state.light_positions) |pos| {
        state.lightShader.use(.{
            .model = glup.zm.Mat4f.translationVec3(pos)
                .multiply(glup.zm.Mat4f.scalingVec3(@splat(0.2))),
            .view = state.camera.view(),
            .projection = state.camera.projection(@intCast(width), @intCast(height)),
        });
        state.mesh.draw();
    }
}

const Mat4 = glup.zm.Mat4f;

const Material = struct {
    diffuse: glup.Texture,
    specular: glup.Texture,
    shininess: f32,
};

const DirLight = struct {
    direction: glup.Vec3,
    ambient: glup.Vec3,
    diffuse: glup.Vec3,
    specular: glup.Vec3,
};

const PointLight = struct {
    position: glup.Vec3,
    ambient: glup.Vec3,
    diffuse: glup.Vec3,
    specular: glup.Vec3,
    constant: f32,
    linear: f32,
    quadratic: f32,
};
const SpotLight = struct {
    position: glup.Vec3,
    direction: glup.Vec3,
    ambient: glup.Vec3,
    diffuse: glup.Vec3,
    specular: glup.Vec3,
    constant: f32,
    linear: f32,
    quadratic: f32,
    cutOff: f32,
    outerCutOff: f32,
};
const Uniforms = struct {
    model: Mat4,
    view: Mat4,
    projection: Mat4,
    viewPos: glup.Vec3,
    dirLight: DirLight,
    material: Material,
    pointLight: [4]PointLight,
    spotLight: SpotLight,
};
const Shader = glup.Shader(Uniforms, cube.Vertex);
const LightUniforms = struct { model: Mat4, view: Mat4, projection: Mat4 };
const LightShader = glup.Shader(LightUniforms, cube.Vertex);

const State = struct {
    mesh: glup.Mesh(cube.Vertex),
    shader: Shader,
    lightShader: LightShader,
    camera: glup.Camera,
    texture_diffuse: glup.Texture,
    texture_specular: glup.Texture,
    cube_positions: []const glup.Vec3,
    light_positions: [4]glup.Vec3,
};

pub fn main() !void {
    var app = try glup.App.init(800, 640, "App");
    glup.gl.Enable(glup.gl.DEPTH_TEST);
    glup.Mouse.setFpsMode(app.window);

    var shWatch = glup.Watch.init("examples/light_casters.glsl");
    var state = State{
        .shader = try Shader.initFromFile(shWatch.path),
        .lightShader = try LightShader.init(
            "void main() { gl_Position = projection * view * model * vec4(aPos, 1.0); }",
            "void main() { FragColor = vec4(1.0); }",
        ),
        .mesh = glup.Mesh(cube.Vertex).init(&cube.vertices, &cube.triangles),
        .camera = glup.Camera.init(.{ 1, 2, 5 }, .{ -1, -2, -5 }),
        .texture_diffuse = try glup.Texture.init("examples/textures/container2.png", 0),
        .texture_specular = try glup.Texture.init("examples/textures/container2_specular.png", 1),
        .cube_positions = &.{
            .{ 0.0, 0.0, 0.0 },
            .{ 2.0, 5.0, -15.0 },
            .{ -1.5, -2.2, -2.5 },
            .{ -3.8, -2.0, -12.3 },
            .{ 2.4, -0.4, -3.5 },
            .{ -1.7, 3.0, -7.5 },
            .{ 1.3, -2.0, -2.5 },
            .{ 1.5, 2.0, -2.5 },
            .{ 1.5, 0.2, -1.5 },
            .{ -1.3, 1.0, -1.5 },
        },
        .light_positions = .{
            .{ 0.7, 0.2, 2.0 },
            .{ 2.3, -3.3, -4.0 },
            .{ -4.0, 2.0, -12.0 },
            .{ 0.0, 0.0, -3.0 },
        },
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
