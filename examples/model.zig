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
fn getFilePath(allocator: std.mem.Allocator, currentFilePath: []const u8, subPath: []const u8) ![]const u8 {
    // ToDo leak?
    return std.fmt.allocPrint(allocator, "{s}/{s}", .{
        std.fs.path.dirname(currentFilePath) orelse "",
        subPath,
    });
}
const WordIt = std.mem.TokenIterator(u8, .scalar);
fn parseVecF32(n: comptime_int, it: *WordIt) !@Vector(n, f32) {
    var sol: @Vector(n, f32) = undefined;
    for (0..n) |i| sol[i] = try std.fmt.parseFloat(f32, it.next().?);
    return sol;
}

const ObjParser = struct {
    const Mode = enum { o, v, vt, vn, f, mtllib, usemtl, s };
    positions: std.ArrayList(@Vector(3, f32)),
    texCoords: std.ArrayList(@Vector(2, f32)),
    normals: std.ArrayList(@Vector(3, f32)),
    vertices: std.ArrayList(struct { position: u32, texCoord: u32, normal: u32 }),
    triangles: std.ArrayList(glup.Triangle),
    materials: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
    filePath: []const u8,
    fn init(allocator: std.mem.Allocator, filePath: []const u8) @This() {
        return .{
            .allocator = allocator,
            .filePath = filePath,
            .positions = .init(allocator),
            .texCoords = .init(allocator),
            .normals = .init(allocator),
            .vertices = .init(allocator),
            .triangles = .init(allocator),
            .materials = .init(allocator),
        };
    }
    fn parseIndex(sliceLen: usize, str: []const u8) !u32 {
        const index: i32 = try std.fmt.parseInt(i32, str, 10) - 1;
        return if (index < 0) @as(u32, @intCast(sliceLen)) + 1 - @abs(index) else @abs(index);
    }
    fn parseVertex(self: *@This(), str: []const u8) !u32 {
        var it = std.mem.splitScalar(u8, str, '/');
        const ind: u32 = @intCast(self.vertices.items.len);
        try self.vertices.append(.{
            .position = try parseIndex(self.positions.items.len, it.next().?),
            .texCoord = try parseIndex(self.texCoords.items.len, it.next().?),
            .normal = try parseIndex(self.normals.items.len, it.next().?),
        });
        return ind;
    }
    fn parseTriangle(self: *@This(), it: *WordIt) !glup.Triangle {
        return .{
            try self.parseVertex(it.next().?),
            try self.parseVertex(it.next().?),
            try self.parseVertex(it.next().?),
        };
    }
    fn parseFilePath(self: *@This(), it: *WordIt) ![]const u8 {
        return getFilePath(self.allocator, self.filePath, it.next().?);
    }
    fn parseLine(self: *@This(), line: []const u8) !void {
        var it = std.mem.tokenizeScalar(u8, line, ' ');
        if (it.next()) |m| if (std.meta.stringToEnum(Mode, m)) |x| switch (x) {
            .o, .s, .usemtl => {},
            .mtllib => try self.materials.append(try self.parseFilePath(&it)),
            .v => try self.positions.append(try parseVecF32(3, &it)),
            .vt => try self.texCoords.append(try parseVecF32(2, &it)),
            .vn => try self.normals.append(try parseVecF32(3, &it)),
            .f => try self.triangles.append(try self.parseTriangle(&it)),
        };
    }
    fn parse(self: *@This()) !void {
        var it = try LineIterator.init(self.filePath);
        defer it.deinit();
        while (try it.next()) |line| try self.parseLine(line);
    }
    fn getVertices(self: *@This(), alloc: std.mem.Allocator) ![]Vertex {
        var sol = try alloc.alloc(Vertex, self.vertices.items.len);
        for (sol[0..], self.vertices.items) |*x, val|
            x.* = .{
                .position = self.positions.items[val.position],
                .normal = self.normals.items[val.normal],
                .texCoord = self.texCoords.items[val.texCoord],
            };
        return sol;
    }
};

const Model = struct {
    vertices: []Vertex,
    triangles: []glup.Triangle,
    materials: std.StringHashMap(Material),
    allocator: std.mem.Allocator,
    fn init(filePath: []const u8, allocator: std.mem.Allocator) !@This() {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        var obj = ObjParser.init(arena.allocator(), filePath);
        try obj.parse();
        var materials = std.StringHashMap(Material).init(allocator);
        for (obj.materials.items) |mtlPath| {
            var mtl = MtlParser.init(allocator, mtlPath);
            try mtl.parse(&materials);
        }

        return .{
            .allocator = allocator,
            .vertices = try ObjParser.getVertices(&obj, allocator),
            .triangles = try allocator.dupe(glup.Triangle, obj.triangles.items),
            .materials = materials,
        };
    }
    fn deinit(self: @This()) void {
        self.allocator.free(self.vertices);
        self.allocator.free(self.triangles);
        self.materials.deinit();
    }
};

const Material = struct {
    Ns: f32 = 0,
    Ka: @Vector(3, f32) = .{ 0, 0, 0 },
    Kd: @Vector(3, f32) = .{ 0, 0, 0 },
    Ks: @Vector(3, f32) = .{ 0, 0, 0 },
    Ke: @Vector(3, f32) = .{ 0, 0, 0 },
    Ni: f32 = 0,
    d: f32 = 0,
    illum: f32 = 0,
    map_Kd: []const u8 = "",
    map_Bump: []const u8 = "",
    map_Ks: []const u8 = "",
};

const MtlParser = struct {
    curMat: *Material,
    allocator: std.mem.Allocator,
    filePath: []const u8,
    const Mode = enum { newmtl, Ns, Ka, Kd, Ks, Ke, Ni, d, illum, map_Kd, map_Bump, map_Ks };
    fn init(allocator: std.mem.Allocator, filePath: []const u8) @This() {
        return .{ .allocator = allocator, .filePath = filePath, .curMat = undefined };
    }
    fn parseLine(self: *@This(), line: []const u8, map: *std.StringHashMap(Material)) !void {
        var it = std.mem.tokenizeScalar(u8, line, ' ');
        if (it.next()) |m| if (std.meta.stringToEnum(Mode, m)) |x| switch (x) {
            // .newmtl, .map_Kd, .map_Ks, .map_Bump => @panic("Already handled!"),
            .newmtl => self.curMat = (try map.getOrPutValue(
                try self.allocator.dupe(u8, it.next().?),
                .{},
            )).value_ptr,
            .Ns => self.curMat.Ns = try std.fmt.parseFloat(f32, it.next().?),
            .Ka => self.curMat.Ka = try parseVecF32(3, &it),
            .Kd => self.curMat.Kd = try parseVecF32(3, &it),
            .Ks => self.curMat.Ks = try parseVecF32(3, &it),
            .Ke => self.curMat.Ke = try parseVecF32(3, &it),
            .Ni => self.curMat.Ni = try std.fmt.parseFloat(f32, it.next().?),
            .d => self.curMat.d = try std.fmt.parseFloat(f32, it.next().?),
            .illum => self.curMat.illum = try std.fmt.parseFloat(f32, it.next().?),
            .map_Kd => self.curMat.map_Kd = try getFilePath(self.allocator, self.filePath, it.next().?),
            .map_Bump => self.curMat.map_Bump = try getFilePath(self.allocator, self.filePath, it.next().?),
            .map_Ks => self.curMat.map_Ks = try getFilePath(self.allocator, self.filePath, it.next().?),
        };
    }
    fn parse(self: *@This(), map: *std.StringHashMap(Material)) !void {
        var it = try LineIterator.init(self.filePath);
        defer it.deinit();
        while (try it.next()) |line| try self.parseLine(line, map);
    }
};

const vec = glup.zm.vec;
const rotationSensitivity = 0.002;
const cameraSpeed = 0.05;

const DirLight = struct {
    direction: glup.Vec3,
    ambient: glup.Vec3,
    diffuse: glup.Vec3,
    specular: glup.Vec3,
};

const Uniforms = struct {
    view: glup.zm.Mat4f,
    projection: glup.zm.Mat4f,
    diffuse: glup.Texture,
};

// var rld = Reloader(.{
//     .{ "examples/model.glsl", struct {
//         fn init(filePath: []const u8) glup.Shader(Uniforms, Vertex) {
//             return try glup.Shader(Uniforms, Vertex).initFromFile(filePath);
//         }
//         fn deinit(sh: glup.Shader(Uniforms, Vertex)) void {
//             sh.deinit();
//         }
//     } },
//     .{ "examples/model.glsl", struct {
//         fn init(filePath: []const u8) glup.Shader(Uniforms, Vertex) {
//             return try glup.Shader(Uniforms, Vertex).initFromFile(filePath);
//         }
//         fn deinit(sh: glup.Shader(Uniforms, Vertex)) void {
//             sh.deinit();
//         }
//     } },
// });

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const model = try Model.init("examples/cube/cube.obj", gpa.allocator());
    // for (model.vertices) |v| std.debug.print("v: {}\n", .{v});
    // for (model.triangles) |t| std.debug.print("t: {}\n", .{t});
    // {
    //     var it = model.materials.iterator();
    //     while (it.next()) |kv|
    //         std.debug.print("{s} => {}\n", .{ kv.key_ptr.*, kv.value_ptr.* });
    // }

    var app = try glup.App.init(800, 600, "Model Loading");
    const cube = glup.Mesh(Vertex).init(model.vertices, model.triangles);
    // for(model.vertices.items, 0..) |v, i| std.debug.print("{}v: {}\n", .{i, v});
    // for(model.triangles.items) |t| std.debug.print("tri: {}\n", .{t});
    var shWatch = glup.Watch.init("examples/model.glsl");
    var sh = try glup.Shader(Uniforms, Vertex).initFromFile(shWatch.path);

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
            sh = try glup.Shader(Uniforms, Vertex).initFromFile(shWatch.path);
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
        // std.debug.print("test", .{});
    }
}
