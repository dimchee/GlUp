const std = @import("std");
const glup = @import("glup");
const ztracy = @import("ztracy");

pub const Triangle = struct { u32, u32, u32 };

const Vertex = struct {
    position: @Vector(3, f32),
    texCoord: @Vector(2, f32),
    normal: @Vector(3, f32),
};

const ModelParser = struct {
    const UnfinishedVertex = struct {
        position: i64,
        texCoord: i64,
        normal: i64,
    };
    positions: std.ArrayList(@Vector(3, f32)),
    texCoords: std.ArrayList(@Vector(2, f32)),
    normals: std.ArrayList(@Vector(3, f32)),
    vertIndex: std.AutoHashMap(UnfinishedVertex, u32),
    vertices: std.ArrayList(Vertex),
    triangles: std.ArrayList(Triangle),
    fn init(arena: *std.heap.ArenaAllocator, allocator: std.mem.Allocator) @This() {
        const alloc = arena.allocator();
        return .{
            .positions = std.ArrayList(@Vector(3, f32)).init(alloc),
            .texCoords = std.ArrayList(@Vector(2, f32)).init(alloc),
            .normals = std.ArrayList(@Vector(3, f32)).init(alloc),
            .vertIndex = std.AutoHashMap(UnfinishedVertex, u32).init(alloc),
            .vertices = std.ArrayList(Vertex).init(allocator),
            .triangles = std.ArrayList(Triangle).init(allocator),
        };
    }
    fn getAt(T: type, slice: []T, index: i64) T {
        return slice[if (index < 0) slice.len + 1 - @abs(index) else @intCast(index)];
    }
    fn parseVertex(self: *@This(), str: []const u8) !u32 {
        const tracy_zone = ztracy.ZoneNC(@src(), "Parse Vertex", 0x00_ff_00_00);
        defer tracy_zone.End();
        var it = std.mem.splitScalar(u8, str, '/');
        const v = UnfinishedVertex{
            .position = try std.fmt.parseInt(i64, it.next().?, 10) - 1,
            .texCoord = try std.fmt.parseInt(i64, it.next().?, 10) - 1,
            .normal = try std.fmt.parseInt(i64, it.next().?, 10) - 1,
        };
        var ind: u32 = undefined;
        if (self.vertIndex.get(v)) |i| {
            ind = i;
        } else {
            ind = @intCast(self.vertices.items.len);
            try self.vertIndex.put(v, ind);
            try self.vertices.append(.{
                .position = getAt(@Vector(3, f32), self.positions.items, v.position),
                .texCoord = getAt(@Vector(2, f32), self.texCoords.items, v.texCoord),
                .normal = getAt(@Vector(3, f32), self.normals.items, v.normal),
            });
        }
        return ind;
    }
};

const Model = struct {
    vertices: std.ArrayList(Vertex),
    triangles: std.ArrayList(Triangle),
    fn processLine(sol: *ModelParser, line: []const u8) !void {
        const tracy_zone = ztracy.ZoneNC(@src(), "Process line", 0x00_ff_00_00);
        defer tracy_zone.End();
        var it = std.mem.tokenizeScalar(u8, line, ' ');
        if (it.next()) |head| {
            if (std.mem.eql(u8, head, "o")) {
                std.debug.print("Parsing Part: {s}\n", .{it.next().?});
            } else if (std.mem.eql(u8, head, "v")) {
                try sol.positions.append(.{
                    try std.fmt.parseFloat(f32, it.next().?),
                    try std.fmt.parseFloat(f32, it.next().?),
                    try std.fmt.parseFloat(f32, it.next().?),
                });
            } else if (std.mem.eql(u8, head, "vt")) {
                try sol.texCoords.append(.{
                    try std.fmt.parseFloat(f32, it.next().?),
                    try std.fmt.parseFloat(f32, it.next().?),
                });
            } else if (std.mem.eql(u8, head, "vn")) {
                try sol.normals.append(.{
                    try std.fmt.parseFloat(f32, it.next().?),
                    try std.fmt.parseFloat(f32, it.next().?),
                    try std.fmt.parseFloat(f32, it.next().?),
                });
            } else if (std.mem.eql(u8, head, "f")) {
                try sol.triangles.append(.{
                    try sol.parseVertex(it.next().?),
                    try sol.parseVertex(it.next().?),
                    try sol.parseVertex(it.next().?),
                });
            }
        }
    }
    fn init(filePath: []const u8, allocator: std.mem.Allocator) !@This() {
        const tracy_zone = ztracy.ZoneNC(@src(), "Start Parsing", 0x00_ff_00_00);
        defer tracy_zone.End();
        const file = try std.fs.cwd().openFile(filePath, .{});
        defer file.close();
        var buffered = std.io.bufferedReader(file.reader());
        var reader = buffered.reader();
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        var sol: ModelParser = ModelParser.init(&arena, allocator);
        var buff: [1024]u8 = undefined;
        var ind: u32 = 0;
        while (try reader.readUntilDelimiterOrEof(&buff, '\n')) |line| {
            var buf2: [128]u8 = undefined;
            processLine(&sol, line) catch @panic(try std.fmt.bufPrint(&buf2, "Error line: {}", .{ind}));
            ind += 1;
        }
        return .{ .vertices = sol.vertices, .triangles = sol.triangles };
    }
    fn deinit(self: @This()) void {
        self.vertices.deinit();
        self.triangles.deinit();
    }
};

// fn reading4(allocator: std.mem.Allocator) void {
//     _ = allocator;
//     const file = std.fs.cwd().openFile(filePath, .{}) catch
//         @panic("Couldn't open file");
//     defer file.close();
//     var cnt = Counter{};
//
//     var buff: [4096]u8 = undefined;
//     var start: usize = 0;
//     var end: usize = 0;
//     while (true) {
//         end = start + (file.readAll(buff[start..]) catch
//             @panic("Couldn't read"));
//         if (start == end) break;
//         if (std.mem.lastIndexOfScalar(u8, buff[0..end], '\n')) |lastNL| {
//             var it = std.mem.splitScalar(u8, buff[0..lastNL], '\n');
//             while (it.next()) |line| cnt.processLine(line);
//             start = end - lastNL;
//             for (buff[lastNL..end], buff[0..start]) |c, *x| x.* = c;
//         } else @panic("Line too long!");
//     }
//     cnt.processLine(buff[0..end]);
// }

const vec = glup.zm.vec;
const rotationSensitivity = 0.002;
const cameraSpeed = 0.05;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const model = try Model.init("examples/backpack/backpack.obj", gpa.allocator());
    // _ = model;

    var app = try glup.App.init(800, 600, "Model Loading");
    // const c = @import("cube.zig");
    const cube = glup.Mesh(Vertex).init(model.vertices.items, model.triangles.items);
    const sh = try glup.Shader(struct { view: glup.zm.Mat4f, projection: glup.zm.Mat4f }, Vertex).init(
        "void main() { gl_Position = projection * view * vec4(position, 1.0); }",
        "void main() { FragColor = vec4(1.0); }",
    );
    var camera = glup.Camera.init(.{ 0, 0, -3 }, .{ 0, 0, 1 });
    glup.gl.Enable(glup.gl.DEPTH_TEST);
    glup.Mouse.setFpsMode(app.window);
    while (app.windowOpened()) |window| {
        glup.gl.Clear(glup.gl.COLOR_BUFFER_BIT | glup.gl.DEPTH_BUFFER_BIT);
        glup.gl.ClearColor(1, 0, 0, 0);

        const mouseOffsets = glup.Mouse.getOffsets();
        camera.update(.{
            .position = vec.scale(glup.Keyboard.movement3D(window), cameraSpeed),
            .rotation = vec.scale(mouseOffsets.position, rotationSensitivity),
            .zoom = mouseOffsets.scroll[1],
        });
        sh.use(.{
            .view = camera.view(),
            .projection = camera.projection(800, 600),
        });
        cube.draw();
        // std.debug.print("test", .{});
    }
}
