const std = @import("std");

const glup = @import("glup");

const Vertex = struct { aPos: glup.Vec3, aTexCoord: glup.Vec2 };
const Uniforms = struct {
    projection: glup.zm.Mat4f,
    view: glup.zm.Mat4f,
    model: glup.zm.Mat4f,
    texture1: glup.Texture,
    texture2: glup.Texture,
};
const Shader = glup.Shader(Uniforms, Vertex);
const Mesh = glup.Mesh(Vertex);
const State = struct {
    mesh: Mesh,
    shader: Shader,
    texture1: glup.Texture,
    texture2: glup.Texture,
    camera: Camera,
};
const Camera = struct {
    pos: glup.zm.Vec3f,
    dir: glup.zm.Vec3f,
    fovy: f32,
    lastMousePos: @Vector(2, f32),
    fn init(pos: glup.zm.Vec3f, dir: glup.zm.Vec3f) @This() {
        const fovy = std.math.degreesToRadians(60);
        return .{ .pos = pos, .dir = dir, .fovy = fovy, .lastMousePos = Mouse.pos };
    }
    fn view(self: @This()) glup.zm.Mat4f {
        return glup.zm.Mat4f.lookAt(self.pos, self.pos + self.dir, .{ 0, 1, 0 });
    }
    fn projection(self: @This()) glup.zm.Mat4f {
        return glup.zm.Mat4f.perspective(self.fovy, 4.0 / 3.0, 0.5, 100);
    }
    fn update(self: *@This(), window: *glup.glfw.Window) void {
        const limit = std.math.degreesToRadians(89);
        const cameraSpeed = 0.05;
        const sensitivity = 0.002;
        const cs: glup.zm.Vec3f = @splat(cameraSpeed);
        if (glup.glfw.getKey(window, glup.glfw.KeyW) == glup.glfw.Press)
            self.pos += cs * self.dir;
        if (glup.glfw.getKey(window, glup.glfw.KeyS) == glup.glfw.Press)
            self.pos -= cs * self.dir;
        if (glup.glfw.getKey(window, glup.glfw.KeyD) == glup.glfw.Press)
            self.pos += cs * glup.zm.vec.cross(self.dir, glup.zm.vec.up(f32));
        if (glup.glfw.getKey(window, glup.glfw.KeyA) == glup.glfw.Press)
            self.pos -= cs * glup.zm.vec.cross(self.dir, glup.zm.vec.up(f32));

        const offset = Mouse.pos - self.lastMousePos;
        self.lastMousePos = Mouse.pos;
        const yaw: f32 = std.math.atan2(self.dir[2], self.dir[0]) + sensitivity * offset[0];
        var pitch: f32 = std.math.asin(self.dir[1]) - sensitivity * offset[1];
        pitch = if (pitch > limit) limit else if (pitch < -limit) -limit else pitch;
        self.dir = .{
            std.math.cos(yaw) * std.math.cos(pitch),
            std.math.sin(pitch),
            std.math.sin(yaw) * std.math.cos(pitch),
        };
        const new_fovy = self.fovy - Mouse.scroll_offset[1] * 0.02;
        self.fovy = if (new_fovy < 0.01) 0.01 else if (new_fovy > 0.8) 0.8 else new_fovy;
        Mouse.scroll_offset = .{ 0, 0 };
    }
};

const Mouse = struct {
    var pos: @Vector(2, f32) = .{ undefined, undefined };
    var scroll_offset: @Vector(2, f32) = .{ undefined, undefined };
    fn pos_callback(_: *glup.glfw.Window, xpos: f64, ypos: f64) callconv(.C) void {
        pos = .{ @floatCast(xpos), @floatCast(ypos) };
    }
    fn scroll_callback(_: *glup.glfw.Window, xoffset: f64, yoffset: f64) callconv(.C) void {
        scroll_offset = .{ @floatCast(xoffset), @floatCast(yoffset) };
    }
};
fn init(window: *glup.glfw.Window) void {
    glup.gl.Enable(glup.gl.DEPTH_TEST);
    glup.glfw.setInputMode(window, glup.glfw.Cursor, glup.glfw.CursorDisabled);
    _ = glup.glfw.setCursorPosCallback(window, Mouse.pos_callback);
    _ = glup.glfw.setScrollCallback(window, Mouse.scroll_callback);
}

fn loop(window: *glup.glfw.Window, s: *State) void {
    s.camera.update(window);

    glup.gl.ClearColor(0.2, 0.3, 0.3, 1.0);
    glup.gl.Clear(glup.gl.COLOR_BUFFER_BIT | glup.gl.DEPTH_BUFFER_BIT);
    s.shader.use(.{
        .texture1 = s.texture1,
        .texture2 = s.texture2,
        .projection = s.camera.projection(),
        .view = s.camera.view(),
        .model = glup.zm.Mat4f.rotation(
            .{ 0.5, 1, 0 },
            @as(f32, @floatCast(glup.glfw.getTime())) * std.math.degreesToRadians(50),
        ),
    });
    s.texture1.bind();
    s.texture2.bind();
    s.mesh.use();
    s.mesh.draw();
}

pub fn main() !void {
    const vertices = [_]Vertex{
        .{ .aPos = .{ -0.5, -0.5, -0.5 }, .aTexCoord = .{ 0.0, 0.0 } },
        .{ .aPos = .{ 0.5, -0.5, -0.5 }, .aTexCoord = .{ 1.0, 0.0 } },
        .{ .aPos = .{ 0.5, 0.5, -0.5 }, .aTexCoord = .{ 1.0, 1.0 } },
        .{ .aPos = .{ 0.5, 0.5, -0.5 }, .aTexCoord = .{ 1.0, 1.0 } },
        .{ .aPos = .{ -0.5, 0.5, -0.5 }, .aTexCoord = .{ 0.0, 1.0 } },
        .{ .aPos = .{ -0.5, -0.5, -0.5 }, .aTexCoord = .{ 0.0, 0.0 } },
        .{ .aPos = .{ -0.5, -0.5, 0.5 }, .aTexCoord = .{ 0.0, 0.0 } },
        .{ .aPos = .{ 0.5, -0.5, 0.5 }, .aTexCoord = .{ 1.0, 0.0 } },
        .{ .aPos = .{ 0.5, 0.5, 0.5 }, .aTexCoord = .{ 1.0, 1.0 } },
        .{ .aPos = .{ 0.5, 0.5, 0.5 }, .aTexCoord = .{ 1.0, 1.0 } },
        .{ .aPos = .{ -0.5, 0.5, 0.5 }, .aTexCoord = .{ 0.0, 1.0 } },
        .{ .aPos = .{ -0.5, -0.5, 0.5 }, .aTexCoord = .{ 0.0, 0.0 } },
        .{ .aPos = .{ -0.5, 0.5, 0.5 }, .aTexCoord = .{ 1.0, 0.0 } },
        .{ .aPos = .{ -0.5, 0.5, -0.5 }, .aTexCoord = .{ 1.0, 1.0 } },
        .{ .aPos = .{ -0.5, -0.5, -0.5 }, .aTexCoord = .{ 0.0, 1.0 } },
        .{ .aPos = .{ -0.5, -0.5, -0.5 }, .aTexCoord = .{ 0.0, 1.0 } },
        .{ .aPos = .{ -0.5, -0.5, 0.5 }, .aTexCoord = .{ 0.0, 0.0 } },
        .{ .aPos = .{ -0.5, 0.5, 0.5 }, .aTexCoord = .{ 1.0, 0.0 } },
        .{ .aPos = .{ 0.5, 0.5, 0.5 }, .aTexCoord = .{ 1.0, 0.0 } },
        .{ .aPos = .{ 0.5, 0.5, -0.5 }, .aTexCoord = .{ 1.0, 1.0 } },
        .{ .aPos = .{ 0.5, -0.5, -0.5 }, .aTexCoord = .{ 0.0, 1.0 } },
        .{ .aPos = .{ 0.5, -0.5, -0.5 }, .aTexCoord = .{ 0.0, 1.0 } },
        .{ .aPos = .{ 0.5, -0.5, 0.5 }, .aTexCoord = .{ 0.0, 0.0 } },
        .{ .aPos = .{ 0.5, 0.5, 0.5 }, .aTexCoord = .{ 1.0, 0.0 } },
        .{ .aPos = .{ -0.5, -0.5, -0.5 }, .aTexCoord = .{ 0.0, 1.0 } },
        .{ .aPos = .{ 0.5, -0.5, -0.5 }, .aTexCoord = .{ 1.0, 1.0 } },
        .{ .aPos = .{ 0.5, -0.5, 0.5 }, .aTexCoord = .{ 1.0, 0.0 } },
        .{ .aPos = .{ 0.5, -0.5, 0.5 }, .aTexCoord = .{ 1.0, 0.0 } },
        .{ .aPos = .{ -0.5, -0.5, 0.5 }, .aTexCoord = .{ 0.0, 0.0 } },
        .{ .aPos = .{ -0.5, -0.5, -0.5 }, .aTexCoord = .{ 0.0, 1.0 } },
        .{ .aPos = .{ -0.5, 0.5, -0.5 }, .aTexCoord = .{ 0.0, 1.0 } },
        .{ .aPos = .{ 0.5, 0.5, -0.5 }, .aTexCoord = .{ 1.0, 1.0 } },
        .{ .aPos = .{ 0.5, 0.5, 0.5 }, .aTexCoord = .{ 1.0, 0.0 } },
        .{ .aPos = .{ 0.5, 0.5, 0.5 }, .aTexCoord = .{ 1.0, 0.0 } },
        .{ .aPos = .{ -0.5, 0.5, 0.5 }, .aTexCoord = .{ 0.0, 0.0 } },
        .{ .aPos = .{ -0.5, 0.5, -0.5 }, .aTexCoord = .{ 0.0, 1.0 } },
    };
    const triangles = [_]glup.Triangle{
        .{ 0, 1, 2 },
        .{ 3, 4, 5 },
        .{ 6, 7, 8 },
        .{ 9, 10, 11 },
        .{ 12, 13, 14 },
        .{ 15, 16, 17 },
        .{ 18, 19, 20 },
        .{ 21, 22, 23 },
        .{ 24, 25, 26 },
        .{ 27, 28, 29 },
        .{ 30, 31, 32 },
        .{ 33, 34, 35 },
    };

    const app = try glup.App.init(800, 600, "Camera Example");
    try app.run(.{ .loop = loop, .init = init, .state = State{
        .mesh = Mesh.init(&vertices, &triangles),
        .shader = try Shader.init(
            "void main() { gl_Position = projection * view * model * vec4(aPos, 1.0); TexCoord = aTexCoord; }",
            "void main() { FragColor = mix(texture(texture1, TexCoord), texture(texture2, TexCoord), 0.2); }",
        ),
        .texture1 = try glup.Texture.init("examples/textures/container.png", 0),
        .texture2 = try glup.Texture.init("examples/textures/awesomeface.png", 1),
        .camera = Camera.init(.{ 0, 0, -3 }, .{ 0, 0, 1 }),
    } });
}
