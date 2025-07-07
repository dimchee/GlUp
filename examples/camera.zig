const std = @import("std");
const glup = @import("glup");
const cube = @import("cube.zig");

const Uniforms = struct {
    projection: glup.zm.Mat4f,
    view: glup.zm.Mat4f,
    model: glup.zm.Mat4f,
    texture1: glup.Texture,
    texture2: glup.Texture,
};
const Shader = glup.Shader(Uniforms, cube.Vertex);
const Mesh = glup.Mesh(cube.Vertex);
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

pub fn main() !void {
    var app = try glup.App.init(800, 600, "Camera Example");
    glup.gl.Enable(glup.gl.DEPTH_TEST);
    glup.glfw.setInputMode(app.window, glup.glfw.Cursor, glup.glfw.CursorDisabled);
    _ = glup.glfw.setCursorPosCallback(app.window, Mouse.pos_callback);
    _ = glup.glfw.setScrollCallback(app.window, Mouse.scroll_callback);
    var mesh = Mesh.init(&cube.vertices, &cube.triangles);
    var shader = try Shader.init(
        "out vec2 TexCoord; void main() { gl_Position = projection * view * model * vec4(aPos, 1.0); TexCoord = aTexCoord; }",
        "in  vec2 TexCoord; void main() { FragColor = mix(texture(texture1, TexCoord), texture(texture2, TexCoord), 0.2); }",
    );
    const texture1 = try glup.Texture.init("examples/textures/container.png", 0);
    const texture2 = try glup.Texture.init("examples/textures/awesomeface.png", 1);
    var camera = Camera.init(.{ 0, 0, -3 }, .{ 0, 0, 1 });
    while (app.windowOpened()) |window| {
        camera.update(window);

        glup.gl.ClearColor(0.2, 0.3, 0.3, 1.0);
        glup.gl.Clear(glup.gl.COLOR_BUFFER_BIT | glup.gl.DEPTH_BUFFER_BIT);
        shader.use(.{
            .texture1 = texture1,
            .texture2 = texture2,
            .projection = camera.projection(),
            .view = camera.view(),
            .model = glup.zm.Mat4f.rotation(
                .{ 0.5, 1, 0 },
                @as(f32, @floatCast(glup.glfw.getTime())) * std.math.degreesToRadians(50),
            ),
        });
        mesh.draw();
    }
}
