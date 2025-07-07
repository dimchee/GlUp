const glup = @import("glup");
const std = @import("std");

const Vertex = struct { aPos: glup.Vec3 };
const Mesh = glup.Mesh(Vertex);
const Shader = glup.Shader(struct {}, Vertex);

pub fn main() !void {
    const vertices = [_]Vertex{
        .{ .aPos = .{ -0.5, -0.5, 0.0 } },
        .{ .aPos = .{ 0.5, -0.5, 0.0 } },
        .{ .aPos = .{ 0.0, 0.5, 0.0 } },
    };
    const triangles = [_]glup.Triangle{.{ 0, 1, 2 }};
    var app = try glup.App.init(800, 640, "Hello Triangle Example");
    var mesh = Mesh.init(&vertices, &triangles); // Maybe deinit?
    var shader = try Shader.init(
        "void main() { gl_Position = vec4(aPos, 1.0); }",
        "void main() { FragColor = vec4(1.0, 0.5, 0.2, 1.0); }",
    );
    while (app.windowOpened()) |_| {
        glup.gl.ClearColor(0.2, 0.3, 0.3, 1.0);
        glup.gl.Clear(glup.gl.COLOR_BUFFER_BIT);
        shader.use(.{});
        mesh.draw();
    }
}
