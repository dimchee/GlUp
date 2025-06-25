const glup = @import("glup");

const Vertex = struct { aPos: glup.Vec3, aTexCoord: glup.Vec2 };
const Uniforms = struct { texture1: glup.Texture, texture2: glup.Texture };
const Shader = glup.Shader(Uniforms, Vertex);
const Mesh = glup.Mesh(Vertex);
const State = struct {
    mesh: Mesh,
    shader: Shader,
    texture1: glup.Texture,
    texture2: glup.Texture,
};

fn loop(s: *State) void {
    glup.gl.ClearColor(0.2, 0.3, 0.3, 1.0);
    glup.gl.Clear(glup.gl.COLOR_BUFFER_BIT);
    s.shader.use(.{ .texture1 = s.texture1, .texture2 = s.texture2 });
    s.texture1.bind();
    s.texture2.bind();
    s.mesh.use();
    s.mesh.draw();
}

pub fn main() !void {
    const vertices = [_]Vertex{
        .{ .aPos = .{ 0.5, 0.5, 0.0 }, .aTexCoord = .{ 1, 1 } },
        .{ .aPos = .{ 0.5, -0.5, 0.0 }, .aTexCoord = .{ 1, 0 } },
        .{ .aPos = .{ -0.5, -0.5, 0.0 }, .aTexCoord = .{ 0, 0 } },
        .{ .aPos = .{ -0.5, 0.5, 0.0 }, .aTexCoord = .{ 0, 1 } },
    };
    const triangles = [_]glup.Triangle{ .{ 0, 1, 3 }, .{ 1, 2, 3 } };

    const app = try glup.App.init(800, 640, "Textures Example");
    try app.run(.{ .loop = loop, .state = State{
        .mesh = Mesh.init(&vertices, &triangles),
        .shader = try Shader.init(
            "void main() { gl_Position = vec4(aPos, 1.0); TexCoord = aTexCoord; }",
            "void main() { FragColor = mix(texture(texture1, TexCoord), texture(texture2, TexCoord), 0.2); }",
        ),
        .texture1 = try glup.Texture.init("examples/textures/container.png", 0),
        .texture2 = try glup.Texture.init("examples/textures/awesomeface.png", 1),
    } });
}
