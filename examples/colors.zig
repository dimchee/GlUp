const std = @import("std");
const glup = @import("glup");
const cube = @import("cube.zig");

const EulerAngles = struct {
    angles: @Vector(3, f32), // yaw[0]  pitch[1] roll[2]
    fn toDir(self: @This()) @Vector(3, f32) {
        return .{
            std.math.cos(self.angles[0]) * std.math.cos(self.angles[1]),
            std.math.sin(self.angles[1]),
            std.math.sin(self.angles[0]) * std.math.cos(self.angles[1]),
        };
    }
    fn fromDir(dir: @Vector(3, f32)) @This() {
        return .{ .angles = .{ std.math.atan2(dir[2], dir[0]), std.math.asin(dir[1]), 0.0 } };
    }
};

const Camera = struct {
    const InputOffsets = struct {
        mousePos: glup.Vec2,
        mouseScroll: glup.Vec2,
        pos: glup.Vec3,
    };
    pos: glup.zm.Vec3f,
    dir: glup.zm.Vec3f,
    fovy: f32,
    fn init(pos: glup.zm.Vec3f, dir: glup.zm.Vec3f) @This() {
        const fovy = std.math.degreesToRadians(60);
        return .{ .pos = pos, .dir = dir, .fovy = fovy };
    }
    fn view(self: @This()) glup.zm.Mat4f {
        return glup.zm.Mat4f.lookAt(self.pos, self.pos + self.dir, glup.zm.vec.up(f32));
    }
    fn projection(self: @This(), width: usize, height: usize) glup.zm.Mat4f {
        const aspect = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height));
        return glup.zm.Mat4f.perspective(self.fovy, aspect, 0.5, 100);
    }
    fn update(self: *@This(), input: InputOffsets) void {
        const v = glup.zm.vec;
        const right = v.normalize(v.cross(self.dir, v.up(f32)));
        const up = v.normalize(v.cross(right, self.dir));
        self.pos += v.scale(right, input.pos[0]);
        self.pos += v.scale(up, input.pos[1]);
        self.pos += v.scale(self.dir, input.pos[2]);

        var ang = EulerAngles.fromDir(self.dir);
        ang.angles += .{ input.mousePos[0], -input.mousePos[1], 0.0 };
        const limit = std.math.degreesToRadians(89);
        ang.angles[1] = std.math.clamp(ang.angles[1], -limit, limit);
        self.dir = ang.toDir();
        self.fovy = std.math.clamp(self.fovy - input.mouseScroll[1] * 0.02, 0.01, 0.8);
    }
};

fn getAxis(window: *glup.glfw.Window) glup.Vec3 {
    var axis: glup.Vec3 = .{ 0, 0, 0 };
    if (glup.glfw.getKey(window, glup.glfw.KeyW) == glup.glfw.Press)
        axis[2] += 1;
    if (glup.glfw.getKey(window, glup.glfw.KeyS) == glup.glfw.Press)
        axis[2] -= 1;
    if (glup.glfw.getKey(window, glup.glfw.KeyD) == glup.glfw.Press)
        axis[0] += 1;
    if (glup.glfw.getKey(window, glup.glfw.KeyA) == glup.glfw.Press)
        axis[0] -= 1;
    if (glup.glfw.getKey(window, glup.glfw.KeySpace) == glup.glfw.Press)
        axis[1] += 1;
    if (glup.glfw.getKey(window, glup.glfw.KeyLeftShift) == glup.glfw.Press)
        axis[1] -= 1;
    return axis;
}

const Mouse = struct {
    pos: @Vector(2, f32) = .{ undefined, undefined },
    scroll: @Vector(2, f32) = .{ undefined, undefined },
    fn posCallback(comptime self: *@This()) glup.glfw.CursorPosFun {
        return struct {
            fn callback(_: *glup.glfw.Window, xpos: f64, ypos: f64) callconv(.C) void {
                self.pos = .{ @floatCast(xpos), @floatCast(ypos) };
            }
        }.callback;
    }
    fn scrollCallback(comptime self: *@This()) glup.glfw.ScrollFun {
        return struct {
            fn callback(_: *glup.glfw.Window, xoffset: f64, yoffset: f64) callconv(.C) void {
                self.scroll += .{ @floatCast(xoffset), @floatCast(yoffset) };
            }
        }.callback;
    }
};

fn loop(window: *glup.glfw.Window, state: *State) callconv(.c) void {
    const rotationSensitivity = 0.002;
    const cameraSpeed = 0.05;
    glup.gl.Clear(glup.gl.COLOR_BUFFER_BIT | glup.gl.DEPTH_BUFFER_BIT);
    glup.gl.ClearColor(0, 0, 1, 1);

    state.camera.update(.{
        .pos = getAxis(window) * @as(glup.Vec3, @splat(cameraSpeed)),
        .mouseScroll = (state.mouse.scroll - state.lastMouseScroll),
        .mousePos = (state.mouse.pos - state.lastMousePos) *
            @as(glup.Vec2, @splat(rotationSensitivity)),
    });
    state.lastMousePos = state.mouse.pos;
    state.lastMouseScroll = state.mouse.scroll;

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
    camera: Camera,
    mouse: *Mouse,
    lastMousePos: @Vector(2, f32) = undefined,
    lastMouseScroll: @Vector(2, f32) = undefined,
};

var mouse = Mouse{};

pub fn main() !void {
    var rld = try Rld.init();
    var app = try glup.App.init(800, 640, "App");
    glup.gl.Enable(glup.gl.DEPTH_TEST);
    glup.glfw.setInputMode(app.window, glup.glfw.Cursor, glup.glfw.CursorDisabled);
    _ = glup.glfw.setCursorPosCallback(app.window, mouse.posCallback());
    _ = glup.glfw.setScrollCallback(app.window, mouse.scrollCallback());

    var state = State{
        .shader = try Shader.initFromFile("examples/colors_shader.glsl"),
        .lightShader = try Shader.init(
            "void main() { gl_Position = projection * view * model * vec4(aPos, 1.0); }",
            "void main() { FragColor = vec4(1.0); }",
        ),
        .mesh = glup.Mesh(cube.Vertex).init(&cube.vertices, &cube.triangles),
        .camera = Camera.init(.{ 0, 0, -5 }, .{ 0, 0, 1 }),
        .mouse = &mouse,
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
