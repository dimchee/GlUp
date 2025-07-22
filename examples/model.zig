const std = @import("std");
const glup = @import("glup");

const Vertex = struct {
    position: @Vector(3, f32),
    texCoord: @Vector(2, f32),
    normal: @Vector(3, f32),
};

/// All lines have to be longer than buff size!
const LineIterator = struct {
    file: std.fs.File,
    buff: [4096]u8,
    remains: ?[]const u8,
    end: usize,
    it: std.mem.SplitIterator(u8, .scalar),
    pub fn init(filePath: []const u8) !@This() {
        const file = try std.fs.cwd().openFile(filePath, .{});
        const it = std.mem.splitScalar(u8, "", '\n');
        return .{ .file = file, .buff = undefined, .remains = "", .end = 0, .it = it };
    }
    pub fn next(self: *@This()) !?[]const u8 {
        if (self.it.next()) |line| return line;
        if (self.remains) |rs| {
            for (self.buff[0..rs.len], rs) |*new, x| new.* = x;
            self.end = rs.len + try self.file.readAll(self.buff[rs.len..]);
            self.remains = null;
            if (std.mem.lastIndexOfScalar(u8, self.buff[0..self.end], '\n')) |lastNL| {
                self.it = std.mem.splitScalar(u8, self.buff[0..lastNL], '\n');
                self.remains = self.buff[(lastNL + 1)..self.end];
            }
        }
        return self.it.next();
    }
    pub fn deinit(self: @This()) void {
        self.file.close();
    }
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
    triangles: std.ArrayList(glup.Triangle),
    materials: std.StringHashMap(Material),
    fn init(arena: *std.heap.ArenaAllocator, allocator: std.mem.Allocator) @This() {
        const alloc = arena.allocator();
        return .{
            .positions = .init(alloc),
            .texCoords = .init(alloc),
            .normals = .init(alloc),
            .vertIndex = .init(alloc),
            .vertices = .init(allocator),
            .triangles = .init(allocator),
            .materials = .init(allocator),
        };
    }
    fn getAt(T: type, slice: []T, index: i64) T {
        return slice[if (index < 0) slice.len + 1 - @abs(index) else @intCast(index)];
    }
    fn parseVertex(self: *@This(), str: []const u8) !u32 {
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
    fn parseTriangle(self: *@This(), it: *Model.WordIt) !glup.Triangle {
        return .{
            try self.parseVertex(it.next().?),
            try self.parseVertex(it.next().?),
            try self.parseVertex(it.next().?),
        };
    }
};

const Model = struct {
    const WordIt = std.mem.TokenIterator(u8, .scalar);
    const Mode = enum { o, v, vt, vn, f, mtllib, usemtl, s };
    vertices: std.ArrayList(Vertex),
    triangles: std.ArrayList(glup.Triangle),
    materials: std.StringHashMap(Material),
    fn getVecF32(n: comptime_int, it: *WordIt) !@Vector(n, f32) {
        var sol: @Vector(n, f32) = undefined;
        for (0..n) |i| sol[i] = try std.fmt.parseFloat(f32, it.next().?);
        return sol;
    }
    fn processLine(sol: *ModelParser, head: []const u8, it: *WordIt) !void {
        if (std.meta.stringToEnum(Mode, head)) |x| switch (x) {
            .o => std.debug.print("Parsing Part: {s}\n", .{it.next().?}),
            .v => try sol.positions.append(try getVecF32(3, it)),
            .vt => try sol.texCoords.append(try getVecF32(2, it)),
            .vn => try sol.normals.append(try getVecF32(3, it)),
            .f => try sol.triangles.append(try sol.parseTriangle(it)),
            .s => {
                // Smoothing group
            },
            // ToDo c_allocator?
            .mtllib => try Material.process(it.next().?, &sol.materials),
            .usemtl => {},
        } else std.debug.print("Ignored head: {s}\n", .{head});
    }
    fn init(filePath: []const u8, allocator: std.mem.Allocator) !@This() {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        var sol: ModelParser = ModelParser.init(&arena, allocator);

        var ind: u32 = 0;
        var it = try LineIterator.init(filePath);
        defer it.deinit();
        while (try it.next()) |line| {
            var buff: [128]u8 = undefined;
            var wordIt = std.mem.tokenizeScalar(u8, line, ' ');
            if (wordIt.next()) |head| {
                processLine(&sol, head, &wordIt) catch
                    @panic(try std.fmt.bufPrint(&buff, "Error line: {}", .{ind}));
            }
            ind += 1;
        }
        return .{
            .vertices = sol.vertices,
            .triangles = sol.triangles,
            .materials = sol.materials,
        };
    }
    fn deinit(self: @This()) void {
        self.vertices.deinit();
        self.triangles.deinit();
    }
};

const Material = struct {
    Ns: f32,
    Ka: @Vector(3, f32),
    Kd: @Vector(3, f32),
    Ks: @Vector(3, f32),
    Ke: @Vector(3, f32),
    Ni: f32,
    d: f32,
    illum: f32,
    map_Kd: []const u8,
    map_Bump: []const u8,
    map_Ks: []const u8,
    const WordIt = std.mem.TokenIterator(u8, .scalar);
    const Mode = enum { newmtl, Ns, Ka, Kd, Ks, Ke, Ni, d, illum, map_Kd, map_Bump, map_Ks };
    fn processLine(current: *@This(), mode: Mode, it: *WordIt) !void {
        switch (mode) {
            .newmtl => {},
            .Ns => current.Ns = try std.fmt.parseFloat(f32, it.next().?),
            .Ka => current.Ka = try Model.getVecF32(3, it),
            .Kd => current.Kd = try Model.getVecF32(3, it),
            .Ks => current.Ks = try Model.getVecF32(3, it),
            .Ke => current.Ke = try Model.getVecF32(3, it),
            .Ni => current.Ni = try std.fmt.parseFloat(f32, it.next().?),
            .d => current.d = try std.fmt.parseFloat(f32, it.next().?),
            .illum => current.illum = try std.fmt.parseFloat(f32, it.next().?),
            .map_Kd => current.map_Kd = it.next().?,
            .map_Bump => current.map_Bump = it.next().?,
            .map_Ks => current.map_Ks = it.next().?,
        }
    }
    fn process(filePath: []const u8, map: *std.StringHashMap(Material)) !void {
        var ind: u32 = 0;
        var buff: [256]u8 = undefined;
        var current: *@This() = undefined;

        const path = try std.fmt.bufPrint(&buff, "examples/backpack/{s}", .{filePath});
        var it = try LineIterator.init(path);
        defer it.deinit();
        while (try it.next()) |line| {
            var wordIt = std.mem.tokenizeScalar(u8, line, ' ');
            if (wordIt.next()) |head| {
                if (std.meta.stringToEnum(Mode, head)) |x| switch (x) {
                    .newmtl => current = (try map.getOrPut(wordIt.next().?)).value_ptr,
                    else => processLine(current, x, &wordIt) catch
                        @panic(try std.fmt.bufPrint(&buff, "Error line: {}", .{ind})),
                } else std.debug.print("Ignored head: {s}\n", .{head});
            }
            ind += 1;
        }
    }
};

const vec = glup.zm.vec;
const rotationSensitivity = 0.002;
const cameraSpeed = 0.05;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const model = try Model.init("examples/backpack/backpack.obj", gpa.allocator());
    // {
    //     var it = model.materials.iterator();
    //     while(it.next()) |kv|
    //         std.debug.print("material: {s}\n{}", .{kv.key_ptr.*, kv.value_ptr});
    // }

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
