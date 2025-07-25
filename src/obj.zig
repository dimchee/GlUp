const std = @import("std");
const glup = @import("root.zig");

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
pub const Vertex = struct {
    position: @Vector(3, f32),
    texCoord: @Vector(2, f32),
    normal: @Vector(3, f32),
};

/// # Vertex data
/// - [x] geometric vertices (v)
/// - [x] texture vertices (vt)
/// - [x] vertex normals (vn)
/// - [ ] parameter space vertices (vp)
/// # Free-form curve/surface attributes
/// - [ ] rational or non-rational forms of curve or surface type: basis matrix, Bezier, B-spline, Cardinal, Taylor (cstype)
/// - [ ] degree (deg)
/// - [ ] basis matrix (bmat)
/// - [ ] step size (step)
/// # Elements
/// - [ ] point (p)
/// - [ ] line (l)
/// - [x] face (f)
/// - [ ] curve (curv)
/// - [ ] 2D curve (curv2)
/// - [ ] surface (surf)
/// # Free-form curve/surface body statements
/// - [ ] parameter values (parm)
/// - [ ] outer trimming loop (trim)
/// - [ ] inner trimming loop (hole)
/// - [ ] special curve (scrv)
/// - [ ] special point (sp)
/// - [ ] end statement (end)
/// # Connectivity between free-form surfaces
/// - [ ] connect (con)
/// # Grouping
/// - [x] group name (g)
/// - [x] smoothing group (s)
/// - [ ] merging group (mg)
/// - [x] object name (o)
/// # Display/render attributes
/// - [ ] bevel interpolation (bevel)
/// - [ ] color interpolation (c_interp)
/// - [ ] dissolve interpolation (d_interp)
/// - [ ] level of detail (lod)
/// - [x] material name (usemtl)
/// - [x] material library (mtllib)
/// - [ ] shadow casting (shadow_obj)
/// - [ ] ray tracing (trace_obj)
/// - [ ] curve approximation technique (ctech)
/// - [ ] surface approximation technique (stech)
/// For details, see https://paulbourke.net/dataformats/obj/
/// Compare to https://aras-p.info/blog/2022/05/14/comparing-obj-parse-libraries/
const ObjParser = struct {
    const Mode = enum { v, vt, vn, f, g, s, o, usemtl, mtllib };
    positions: std.ArrayList(@Vector(3, f32)),
    texCoords: std.ArrayList(@Vector(2, f32)),
    normals: std.ArrayList(@Vector(3, f32)),
    vertices: std.ArrayList(struct { position: u32, texCoord: u32, normal: u32 }),
    triangles: std.ArrayList(glup.Triangle),
    materials: std.ArrayList([]const u8),
    groupNames: []const []const u8,
    objectName: ?[]const u8,
    material: ?[]const u8,
    allocator: std.mem.Allocator,
    filePath: []const u8,
    fn init(allocator: std.mem.Allocator, filePath: []const u8) @This() {
        return .{
            .material = null,
            .objectName = null,
            .groupNames = &[_][]const u8{"default"},
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
        var sol: u32 = 0;
        for (if (str[0] == '-') str[1..] else str) |c| if (std.ascii.isDigit(c)) {
            sol = 10 * sol + c - '0';
        } else {
            return std.fmt.ParseIntError.InvalidCharacter;
        };
        return if (str[0] == '-') @as(u32, @intCast(sliceLen)) - sol else sol - 1;
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
    const Face = union(enum) { triangle: glup.Triangle, quad: [2]glup.Triangle };
    // ToDo maybe no normals or texCoords
    // ToDo more than 4 vertices
    fn parseFace(self: *@This(), it: *WordIt) !Face {
        const tri = .{
            try self.parseVertex(it.next().?),
            try self.parseVertex(it.next().?),
            try self.parseVertex(it.next().?),
        };
        return if (it.next()) |v| .{ .quad = .{
            tri, .{ tri[0], tri[2], try self.parseVertex(v) },
        } } else .{ .triangle = tri };
    }
    fn parseFilePath(self: *@This(), word: []const u8) ![]const u8 {
        return getFilePath(self.allocator, self.filePath, word);
    }
    fn parseLine(self: *@This(), line: []const u8) !void {
        var it = std.mem.tokenizeScalar(u8, line, ' ');
        if (it.next()) |m| if (std.meta.stringToEnum(Mode, m)) |x| switch (x) {
            .g => {
                var names = std.ArrayList([]const u8).init(self.allocator);
                while (it.next()) |name| try names.append(try self.allocator.dupe(u8, name));
                self.groupNames = names.items;
            },
            .s => {}, // Don't understand yet?
            .o => self.objectName = try self.allocator.dupe(u8, it.next().?),
            .usemtl => self.material = it.next().?,
            .mtllib => while (it.next()) |word|
                try self.materials.append(try self.parseFilePath(word)),
            .v => try self.positions.append(try parseVecF32(3, &it)), // ToDo w component?
            .vt => try self.texCoords.append(try parseVecF32(2, &it)), // ToDo can be 1D, or 3D
            .vn => try self.normals.append(try parseVecF32(3, &it)),
            .f => switch (try self.parseFace(&it)) {
                .triangle => |t| try self.triangles.append(t),
                .quad => |q| try self.triangles.appendSlice(&q),
            },
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

pub const Model = struct {
    vertices: []Vertex,
    triangles: []glup.Triangle,
    materials: std.StringHashMap(Material),
    allocator: std.mem.Allocator,
    pub fn init(filePath: []const u8, allocator: std.mem.Allocator) !@This() {
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
    pub fn deinit(self: @This()) void {
        self.allocator.free(self.vertices);
        self.allocator.free(self.triangles);
        self.materials.deinit();
    }
};

const Material = struct {
    Ka: @Vector(3, f32) = .{ 1, 1, 1 },
    Kd: @Vector(3, f32) = .{ 1, 1, 1 },
    Ks: @Vector(3, f32) = .{ 1, 1, 1 },
    Ke: @Vector(3, f32) = .{ 1, 1, 1 },
    Tf: @Vector(3, f32) = .{ 0, 0, 0 },
    illum: u8 = 1,
    d: f32 = 1,
    Ns: f32 = 1,
    sharpness: f32 = 0,
    Ni: f32 = 1,
    map_Kd: []const u8 = "",
    map_Bump: []const u8 = "",
    map_Ks: []const u8 = "",
};

/// # Name statement:
/// - newmtl my_mtl
///
/// # Color and illumination statements:
/// - Ka 0.0435 0.0435 0.0435
///     - [x] Ka r (g b)
///     - [ ] Ka spectral file.rfl factor
///     - [ ] Ka xyz x y z
/// - Kd 0.1086 0.1086 0.1086
///     - [x] Kd r (g b)
///     - [ ] Kd spectral file.rfl factor
///     - [ ] Kd xyz x y z
/// - Ks 0.0000 0.0000 0.0000
///     - [x] Ks r (g b)
///     - [ ] Ks spectral file.rfl factor
///     - [ ] Ks xyz x y z
/// - Tf 0.9885 0.9885 0.9885
///     - [x] Tf r g b
///     - [ ] Tf spectral file.rfl factor
///     - [ ] Tf xyz x y z
/// - illum 6
///     - [x] illum illum_#
/// - d -halo 0.6600
///     - [x] d factor
///     - [ ] d -halo factor
/// - Ns 10.0000
///     - [x] Ns exponent
/// - sharpness 60
///     - [x] sharpness value
/// - Ni 1.19713
///     - [x] Ni optical_density
///
/// # Texture map statements:
/// - Common Texture Options
///     - [ ] -blendu on | off
///     - [ ] -blendv on | off
///     - [ ] -clamp on | off
///     - [ ] -mm base gain
///     - [ ] -o u v w
///     - [ ] -s u v w
///     - [ ] -t u v w
///     - [ ] -texres value
/// - map_Ka -s 1 1 1 -o 0 0 0 -mm 0 1 chrome.mpc
///     - [ ] map_Ka -options args filename
///     - [ ] Extra Option: -cc on | off
/// - map_Kd -s 1 1 1 -o 0 0 0 -mm 0 1 chrome.mpc
///     - [x] map_Kd -options args filename
///     - [ ] Extra Option: -cc on | off
/// - map_Ks -s 1 1 1 -o 0 0 0 -mm 0 1 chrome.mpc
///     - [x] map_Ks -options args filename
///     - [ ] Extra Option: -cc on | off
/// - map_Ns -s 1 1 1 -o 0 0 0 -mm 0 1 wisp.mps
///     - [ ] map_Ns -options args filename
///     - [ ] Extra Option: -imfchan r | g | b | m | l | z
/// - map_d -s 1 1 1 -o 0 0 0 -mm 0 1 wisp.mps
///     - [ ] map_d -options args filename
///     - [ ] Extra Option: -imfchan r | g | b | m | l | z
/// - [ ] map_aat on
/// - disp -s 1 1 .5 wisp.mps
///     - [ ] disp -options args filename
///     - [ ] Extra Option: -imfchan r | g | b | m | l | z
/// - decal -s 1 1 1 -o 0 0 0 -mm 0 1 sand.mps
///     - [ ] decal -options args filename
///     - [ ] Extra Option: -imfchan r | g | b | m | l | z
/// - bump -s 1 1 1 -o 0 0 0 -bm 1 sand.mpb
///     - [ ] bump -options args filename
///     - [ ] Extra Option: -imfchan r | g | b | m | l | z
///     - [ ] Extra Option: -bm mult
///
/// # Reflection map statement:
/// - Common Texture Options
/// - refl -type sphere -mm 0 1 clouds.mpc
///     - [ ] refl -type sphere -options args filename
///     - [ ] refl -type cube_side -options args filenames
///     - [ ] Extra Option: -cc on | off
/// For details, see https://paulbourke.net/dataformats/mtl/
const MtlParser = struct {
    curMat: *Material,
    allocator: std.mem.Allocator,
    filePath: []const u8,
    const Mode = enum { newmtl, Ka, Kd, Ks, Ke, Tf, illum, d, Ns, sharpness, Ni, map_Kd, map_Bump, map_Ks };
    fn init(allocator: std.mem.Allocator, filePath: []const u8) @This() {
        return .{ .allocator = allocator, .filePath = filePath, .curMat = undefined };
    }
    fn parseLine(self: *@This(), line: []const u8, map: *std.StringHashMap(Material)) !void {
        var it = std.mem.tokenizeScalar(u8, line, ' ');
        if (it.next()) |m| if (std.meta.stringToEnum(Mode, m)) |x| switch (x) {
            .newmtl => self.curMat = (try map.getOrPutValue(
                try self.allocator.dupe(u8, it.next().?),
                .{},
            )).value_ptr,
            .Ka => self.curMat.Ka = try parseVecF32(3, &it),
            .Kd => self.curMat.Kd = try parseVecF32(3, &it),
            .Ks => self.curMat.Ks = try parseVecF32(3, &it),
            .Ke => self.curMat.Ke = try parseVecF32(3, &it),
            .Tf => self.curMat.Tf = try parseVecF32(3, &it),
            .illum => self.curMat.illum = try std.fmt.parseUnsigned(u8, it.next().?, 10),
            .d => self.curMat.d = try std.fmt.parseFloat(f32, it.next().?),
            .Ns => self.curMat.Ns = try std.fmt.parseFloat(f32, it.next().?),
            .sharpness => self.curMat.sharpness = try std.fmt.parseFloat(f32, it.next().?),
            .Ni => self.curMat.Ni = try std.fmt.parseFloat(f32, it.next().?),
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
