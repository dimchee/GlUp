const glup = @import("glup");
const std = @import("std");

const Vertex = struct { aPos: glup.Vec3 };
const Mesh = glup.Mesh(Vertex);
const Shader = glup.Shader(struct {}, struct {}, Vertex);
const State = struct { mesh: Mesh, shader: Shader};

fn loop(s: *State) void {
    glup.gl.ClearColor(0.2, 0.3, 0.3, 1.0);
    glup.gl.Clear(glup.gl.COLOR_BUFFER_BIT);
    s.shader.use(.{}, .{});
    s.mesh.use();
    s.mesh.draw();
}

pub fn main() !void {
    const vertices = [_]Vertex{
        .{ .aPos = .{ -0.5, -0.5, 0.0 } },
        .{ .aPos = .{ 0.5, -0.5, 0.0 } },
        .{ .aPos = .{ 0.0, 0.5, 0.0 } },
    };
    const triangles = [_]glup.Triangle{.{ 0, 1, 2 }};
    const app = try glup.App.init(800, 640, "Hello Triangle Example");
    try app.run(.{
        .loop = loop,
        .state = State{
            .mesh = Mesh.init(&vertices, &triangles), // Maybe deinit?
            .shader = try Shader.init(
                "void main() { gl_Position = vec4(aPos, 1.0); }",
                "void main() { FragColor = vec4(1.0, 0.5, 0.2, 1.0); }",
            ),
        },
    });
}
