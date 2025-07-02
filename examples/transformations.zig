const glup = @import("glup");
const std = @import("std");

const Vertex = struct { aPos: glup.Vec3, aTexCoord: glup.Vec2 };
const Uniforms = struct {
    transform: glup.zm.Mat4f,
    texture1: glup.Texture,
    texture2: glup.Texture,
};
const Shader = glup.Shader(Uniforms, Vertex);
const Mesh = glup.Mesh(Vertex);

pub fn main() !void {
    const vertices = [_]Vertex{
        .{ .aPos = .{ 0.5, 0.5, 0.0 }, .aTexCoord = .{ 1, 1 } },
        .{ .aPos = .{ 0.5, -0.5, 0.0 }, .aTexCoord = .{ 1, 0 } },
        .{ .aPos = .{ -0.5, -0.5, 0.0 }, .aTexCoord = .{ 0, 0 } },
        .{ .aPos = .{ -0.5, 0.5, 0.0 }, .aTexCoord = .{ 0, 1 } },
    };
    const triangles = [_]glup.Triangle{ .{ 0, 1, 3 }, .{ 1, 2, 3 } };

    var mesh = Mesh.init(&vertices, &triangles);
    var shader = try Shader.init(
        "void main() { gl_Position = transform * vec4(aPos, 1.0); TexCoord = aTexCoord; }",
        "void main() { FragColor = mix(texture(texture1, TexCoord), texture(texture2, TexCoord), 0.2); }",
    );
    var texture1 = try glup.Texture.init("examples/textures/container.png", 0);
    var texture2 = try glup.Texture.init("examples/textures/awesomeface.png", 1);

    var app = try glup.App.init(800, 640, "Transformations Example");
    while (app.windowOpened()) |_| {
        glup.gl.ClearColor(0.2, 0.3, 0.3, 1.0);
        glup.gl.Clear(glup.gl.COLOR_BUFFER_BIT);
        shader.use(.{
            .texture1 = texture1,
            .texture2 = texture2,
            .transform = glup.zm.Mat4f.translation(0.5, -0.5, 0.0)
                .multiply(
                glup.zm.Mat4f.rotation(.{ 0, 0, 1 }, @floatCast(glup.glfw.getTime())),
            ),
        });
        texture1.bind();
        texture2.bind();
        mesh.use();
        mesh.draw();
    }
}
