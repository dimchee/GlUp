const glup = @import("glup");

const FPS = 60.0;

pub fn main() !void {
    var x: @Vector(2, f32) = .{ 0, 0 };
    const window = try glup.Window.init(800, 640, "Texture Example", key_callback(&x));
    defer window.deinit();
    window.useProcTable();

    const Vertex = struct { aPos: glup.Vec3, aTexCoord: glup.Vec2 };
    const VUniforms = struct { pos: glup.Vec2 };
    const FUniforms = struct { texture0: glup.Texture };
    var sh = try glup.Shader(VUniforms, FUniforms, Vertex).init(
        "void main() { gl_Position = vec4(aPos + vec3(pos, 0.0), 1.0); TexCoord = aTexCoord; }",
        "void main() { FragColor = texture(texture0, TexCoord); }",
    );
    var mesh = glup.Mesh(Vertex).quad();
    var pos = glup.Vec2{ 0, 0 };
    var texture = try glup.Texture.init("tile.png");
    defer mesh.deinit();
    defer sh.deinit();
    defer texture.deinit();

    // gl.PolygonMode(gl.FRONT_AND_BACK, gl.LINE);
    glup.gl.Enable(glup.gl.COLOR_BUFFER_BIT);

    var lastFrameTime: f64 = 0;
    while (!glup.glfw.windowShouldClose(window.window)) {
        const newTime = glup.glfw.getTime();
        if (lastFrameTime + 1.0 / FPS < newTime)
            lastFrameTime = newTime
        else
            continue;

        pos += glup.Vec2{ 0.01, 0.01 } * x;
        // std.debug.print("{}\n", .{x});

        glup.gl.ClearColor(1, 0, 0, 1);
        glup.gl.Clear(glup.gl.COLOR_BUFFER_BIT);

        sh.use(
            .{ .pos = pos },
            .{ .texture0 = texture },
        );
        texture.bind();
        mesh.use();
        mesh.draw();

        glup.glfw.swapBuffers(window.window);
        glup.glfw.pollEvents();
    }
}

fn key_callback(x: *@Vector(2, f32)) glup.glfw.KeyFun {
    comptime var clj = struct {
        var dir: *@Vector(2, f32) = undefined;
        fn func(window: *glup.glfw.Window, key: i32, scancode: i32, action: i32, mods: i32) callconv(.C) void {
            _ = scancode;
            _ = mods;
            if (key == glup.glfw.KeyEscape and action == glup.glfw.Press)
                glup.glfw.setWindowShouldClose(window, true);
            if (key == glup.glfw.KeyW and action == glup.glfw.Press or key == glup.glfw.KeyS and action == glup.glfw.Release)
                dir.* += .{ 0, 1 };
            if (key == glup.glfw.KeyS and action == glup.glfw.Press or key == glup.glfw.KeyW and action == glup.glfw.Release)
                dir.* += .{ 0, -1 };
            if (key == glup.glfw.KeyD and action == glup.glfw.Press or key == glup.glfw.KeyA and action == glup.glfw.Release)
                dir.* += .{ 1, 0 };
            if (key == glup.glfw.KeyA and action == glup.glfw.Press or key == glup.glfw.KeyD and action == glup.glfw.Release)
                dir.* += .{ -1, 0 };
        }
    };
    clj.dir = x;
    return clj.func;
}
