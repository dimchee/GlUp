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

const Reloader = glup.FileReloader(.{
    .sh = .{ "examples/model.glsl", struct {
        pub fn init(filePath: []const u8) !glup.Shader(Uniforms, glup.obj.Vertex) {
            return .initFromFile(filePath);
        }
        pub fn deinit(s: *glup.Shader(Uniforms, glup.obj.Vertex)) void {
            s.deinit();
        }
    } },
    .tex = .{ "examples/cube/texture.png", struct {
        pub fn init(filePath: []const u8) !glup.Texture {
            return glup.Texture.init(filePath, 0);
        }
        pub fn deinit(t: *glup.Texture) void {
            t.deinit();
        }
    } },
});
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const model = try glup.obj.Model.init("examples/cube/cube.obj", gpa.allocator());

    var app = try glup.App.init(800, 600, "Model Loading");
    const cube = glup.Mesh(glup.obj.Vertex).init(model.vertices, model.triangles);
    // for(model.vertices.items, 0..) |v, i| std.debug.print("{}v: {}\n", .{i, v});
    // for(model.triangles.items) |t| std.debug.print("tri: {}\n", .{t});
    // const texPath = x: {
    //     var it = model.materials.valueIterator();
    //     break :x it.next().?.map_Kd;
    // };
    var rld = try Reloader.init();

    var camera = glup.Camera.init(.{ 3, 3, -3 }, .{ -1, -1, 1 });
    glup.gl.Enable(glup.gl.DEPTH_TEST);
    // glup.Mouse.setFpsMode(app.window);
    while (app.windowOpened()) |window| {
        glup.gl.Clear(glup.gl.COLOR_BUFFER_BIT | glup.gl.DEPTH_BUFFER_BIT);
        glup.gl.ClearColor(1, 0, 0, 0);
        try rld.update();
        _ = window;
        // const mouseOffsets = glup.Mouse.getOffsets();
        // camera.update(.{
        //     .position = vec.scale(glup.Keyboard.movement3D(window), cameraSpeed),
        //     .rotation = vec.scale(mouseOffsets.position, rotationSensitivity),
        //     .zoom = mouseOffsets.scroll[1],
        // });
        rld.data.sh.use(.{
            .view = camera.view(),
            .projection = camera.projection(800, 600),
            .diffuse = rld.data.tex,
        });
        cube.draw();
    }
}
