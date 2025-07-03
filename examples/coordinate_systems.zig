const glup = @import("glup");
const std = @import("std");
const cube = @import("cube.zig");

// const Vertex = struct { aPos: glup.Vec3, aTexCoord: glup.Vec2 };
const Uniforms = struct {
    projection: glup.zm.Mat4f,
    view: glup.zm.Mat4f,
    model: glup.zm.Mat4f,
    texture1: glup.Texture,
    texture2: glup.Texture,
};
const Shader = glup.Shader(Uniforms, cube.Vertex);
const Mesh = glup.Mesh(cube.Vertex);

pub fn main() !void {

    var app = try glup.App.init(800, 640, "Transformations Example");
    var mesh = Mesh.init(&cube.vertices, &cube.triangles);
    var shader = try Shader.init(
        "void main() { gl_Position = projection * view * model * vec4(aPos, 1.0); TexCoord = aTexCoord; }",
        "void main() { FragColor = mix(texture(texture1, TexCoord), texture(texture2, TexCoord), 0.2); }",
    );
    var texture1 = try glup.Texture.init("examples/textures/container.png", 0);
    var texture2 = try glup.Texture.init("examples/textures/awesomeface.png", 1);
    while (app.windowOpened()) |_| {
        glup.gl.ClearColor(0.2, 0.3, 0.3, 1.0);
        glup.gl.Clear(glup.gl.COLOR_BUFFER_BIT | glup.gl.DEPTH_BUFFER_BIT);
        shader.use(.{
            .texture1 = texture1,
            .texture2 = texture2,
            .projection = glup.zm.Mat4f.perspective(std.math.degreesToRadians(45), 800 / 600, 0.1, 100),
            .view = glup.zm.Mat4f.translation(0, 0, -3),
            .model = glup.zm.Mat4f.rotation(.{ 0.5, 1, 0 }, @as(f32, @floatCast(glup.glfw.getTime())) * std.math.degreesToRadians(50)),
            // .transform = glup.zm.Mat4f.translation(0.5, -0.5, 0.0)
            //     .multiply(
            //     glup.zm.Mat4f.rotation(.{ 0, 0, 1 }, @floatCast(glup.glfw.getTime())),
            // ),
        });
        texture1.bind();
        texture2.bind();
        mesh.use();
        mesh.draw();
    }
}
