const std = @import("std");

const glup = @import("glup");
const vec = glup.zm.vec;

const rotationSensitivity = 0.002;
const cameraSpeed = 0.05;

const Uniforms = struct {
    view: glup.zm.Mat4f,
    projection: glup.zm.Mat4f,
    diffuse: glup.Texture,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const model = try glup.obj.Model.init("examples/cube/cube.obj", gpa.allocator());

    var app = try glup.App.init(800, 600, "Model Loading");
    const cube = glup.Mesh(glup.obj.Vertex).init(model.vertices, model.triangles);
    // for(model.vertices.items, 0..) |v, i| std.debug.print("{}v: {}\n", .{i, v});
    // for(model.triangles.items) |t| std.debug.print("tri: {}\n", .{t});
    var shWatch = glup.Watch.init("examples/model.glsl");
    var sh = try glup.Shader(Uniforms, glup.obj.Vertex).initFromFile(shWatch.path);

    const texPath = x: {
        var it = model.materials.valueIterator();
        break :x it.next().?.map_Kd;
    };
    var texWatch = glup.Watch.init(texPath);
    var tex = try glup.Texture.init(texWatch.path, 0);

    var camera = glup.Camera.init(.{ 3, 3, -3 }, .{ -1, -1, 1 });
    glup.gl.Enable(glup.gl.DEPTH_TEST);
    glup.Mouse.setFpsMode(app.window);
    while (app.windowOpened()) |window| {
        glup.gl.Clear(glup.gl.COLOR_BUFFER_BIT | glup.gl.DEPTH_BUFFER_BIT);
        glup.gl.ClearColor(1, 0, 0, 0);

        if (try shWatch.changed()) {
            sh.deinit();
            sh = try glup.Shader(Uniforms, glup.obj.Vertex).initFromFile(shWatch.path);
        }
        if (try texWatch.changed()) {
            tex.deinit();
            tex = try glup.Texture.init(texWatch.path, 0);
        }
        const mouseOffsets = glup.Mouse.getOffsets();
        camera.update(.{
            .position = vec.scale(glup.Keyboard.movement3D(window), cameraSpeed),
            .rotation = vec.scale(mouseOffsets.position, rotationSensitivity),
            .zoom = mouseOffsets.scroll[1],
        });
        sh.use(.{
            .view = camera.view(),
            .projection = camera.projection(800, 600),
            .diffuse = tex,
        });
        cube.draw();
    }
}
