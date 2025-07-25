const std = @import("std");
pub const gl = @import("gl");
pub const glfw = @import("glfw");
pub const zm = @import("zm");
pub const obj = @import("obj.zig");

pub const Vec2 = zm.Vec2f;
pub const Vec3 = zm.Vec3f;
pub const Vec4 = zm.Vec4f;

pub const Utils = struct {
    fn infoLog(id: u32, comptime msg: []const u8, log: anytype) void {
        var buff: [512:0]u8 = .{0} ** 512;
        log(id, 512, null, &buff);
        std.log.err(msg, .{buff[0..std.mem.len(@as([*:0]u8, &buff))]});
    }
    fn fileContent(fileName: []const u8) ![]u8 {
        return std.fs.cwd().readFileAlloc(std.heap.c_allocator, fileName, 100000);
    }
    fn generate(gen: fn (c_int, [*]u32) void) u32 {
        var x: [1]u32 = undefined;
        gen(1, &x);
        return x[0];
    }
    fn depointer(T: type) type {
        const ti = @typeInfo(T);
        return if (ti == .pointer) ti.pointer.child else T;
    }
    // set .is_comptime = false, passing merged to run works
    fn Merge(X: type, Y: type) type {
        const xfs = @typeInfo(X).@"struct".fields;
        const yfs = @typeInfo(Y).@"struct".fields;
        return @Type(.{ .@"struct" = .{
            .layout = .auto,
            .fields = xfs ++ yfs,
            .is_tuple = false,
            .decls = &.{},
        } });
    }

    pub fn merge(x: anytype, y: anytype) Merge(@TypeOf(x), @TypeOf(y)) {
        const T = Merge(@TypeOf(x), @TypeOf(y));
        var sol: T = undefined;
        inline for (@typeInfo(@TypeOf(x)).@"struct".fields) |field|
            @field(sol, field.name) = @field(x, field.name);
        inline for (@typeInfo(@TypeOf(y)).@"struct".fields) |field|
            @field(sol, field.name) = @field(y, field.name);
        return sol;
    }
    fn nameToGlsl(str: []const u8) []const u8 {
        const ind = std.mem.lastIndexOfScalar(u8, str, '.') orelse -1;
        return str[ind + 1 ..];
    }
};

pub const Texture = struct {
    id: u32,
    slot: u32,
    pub fn init(filePath: []const u8, slot: u32) !@This() {
        std.debug.assert(slot < 32);
        const id = Utils.generate(gl.GenTextures);
        gl.BindTexture(gl.TEXTURE_2D, id);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
        var image: [*c]u8 = undefined;
        var width: u32 = undefined;
        var height: u32 = undefined;

        const png = @cImport(@cInclude("lodepng.h"));
        const c = @cImport(@cInclude("stdlib.h"));
        const err = png.lodepng_decode32_file(&image, &width, &height, filePath.ptr);
        defer c.free(image);

        const Color = packed struct { r: u8, g: u8, b: u8, a: u8 };
        const pixels = @as([*c]Color, @alignCast(@ptrCast(image)));
        var buff: [4096]Color = undefined;
        for (0..height/2) |i| {
            const j = height - i - 1;
            @memcpy(buff[0..width], pixels[width*i..width*(i+1)]);
            @memcpy(pixels[width*i..width*(i+1)], pixels[width*j..width*(j+1)]);
            @memcpy(pixels[width*j..width*(j+1)], buff[0..width]);
        }
        // std.mem.reverse(Color, pixels[0 .. width * height]);
        // TODO Leaking memory
        if (err != 0) {
            std.debug.print("Error: {s}", .{png.lodepng_error_text(err)});
        }
        gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGB, @intCast(width), @intCast(height), 0, gl.RGBA, gl.UNSIGNED_BYTE, image);
        gl.GenerateMipmap(gl.TEXTURE_2D);

        return .{ .id = id, .slot = slot };
    }
    fn bind(self: *const @This()) void {
        gl.ActiveTexture(gl.TEXTURE0 + self.slot);
        gl.BindTexture(gl.TEXTURE_2D, self.id);
    }
    pub fn deinit(self: @This()) void {
        var id = [_]u32{self.id};
        gl.DeleteTextures(1, &id);
    }
};

// ToDo make guard for 'uniform' keyword in shaders:
//      forbidden - should use generation from zig
pub fn Shader(Uniforms: type, Vertex: type) type {
    return struct {
        id: u32,
        const attributes: []const u8 = x: {
            var sol: []const u8 = "";
            for (std.meta.fields(Vertex), 0..) |field, i|
                sol = sol ++ std.fmt.comptimePrint(
                    "\nlayout (location = {}) in {s} {s};",
                    .{ i, toType(field.type), field.name },
                );
            break :x sol;
        };
        const uniforms: []const u8 = x: {
            var sol: []const u8 = "";
            var i = 0;
            for (std.meta.fields(Uniforms)) |field|
                sol = sol ++ createTypes(field.type);
            for (std.meta.fields(Uniforms)) |field| {
                sol = sol ++ std.fmt.comptimePrint(
                    "\nlayout (location = {}) uniform {s} {s};",
                    .{ i, toType(field.type), field.name },
                );
                i += uniformLen(field.type);
            }
            break :x sol;
        };
        fn uniformLen(t: type) u32 {
            const ti = @typeInfo(t);
            if (ti == .array)
                return ti.array.len * uniformLen(ti.array.child)
            else if (ti == .@"struct") {
                var sol = 0;
                for (ti.@"struct".fields) |field|
                    sol += uniformLen(field.type);
                return sol;
            } else return 1;
        }
        fn createTypes(t: type) []const u8 {
            const ti = @typeInfo(t);
            switch (t) {
                zm.Mat4f => return "",
                Texture => return "",
                else => {},
            }
            if (ti == .array) return createTypes(ti.array.child);
            if (ti != .@"struct") return "";
            comptime {
                var sol: []const u8 = "";
                for (@typeInfo(t).@"struct".fields) |field|
                    sol = sol ++ createTypes(field.type);
                sol = sol ++ "\nstruct " ++ Utils.nameToGlsl(@typeName(t)) ++ " {\n";
                for (std.meta.fields(t)) |field| {
                    sol = sol ++ "    " ++ toType(field.type) ++ " " ++ field.name ++ ";\n";
                }
                return sol ++ "};";
            }
        }
        fn toType(t: type) []const u8 {
            const ti = @typeInfo(t);
            return switch (t) {
                f32 => "float",
                @Vector(2, f32) => "vec2",
                @Vector(3, f32) => "vec3",
                @Vector(4, f32) => "vec4",
                zm.Mat4f => "mat4",
                Texture => "sampler2D",
                else => if (ti == .array)
                    std.fmt.comptimePrint("{s}[{}]", .{ toType(ti.array.child), ti.array.len })
                else if (ti == .@"struct")
                    Utils.nameToGlsl(@typeName(t))
                else
                    @compileError("Unknown type: " ++ @typeName(t)),
            };
        }
        pub fn initFromFile(file: []const u8) !@This() {
            const content = try Utils.fileContent(file);
            const v = std.mem.indexOf(u8, content, "#vertex").?;
            const f = std.mem.indexOf(u8, content, "#fragment").?;
            if (v < f) {
                return init(
                    content[v + "#vertex".len .. f],
                    content[f + "#fragment".len ..],
                );
            } else {
                return init(
                    content[f + "#fragment".len .. v],
                    content[v + "#vertex".len ..],
                );
            }
        }
        pub fn init(vertexSource: []const u8, fragmentSource: []const u8) !@This() {
            const vertexSrc = try std.mem.join(std.heap.page_allocator, "\n", &.{
                "#version 320 es",
                "precision mediump float;",
                attributes,
                uniforms,
                vertexSource,
            });
            const fragmentSrc = try std.mem.join(std.heap.page_allocator, "\n", &.{
                "#version 320 es",
                "precision mediump float;",
                "out vec4 FragColor;",
                uniforms,
                fragmentSource,
            });
            {
                const file = try std.fs.cwd().createFile(
                    "output.glsl",
                    .{ .read = true },
                );
                defer file.close();

                try file.writeAll(fragmentSrc);
                try file.writeAll("\n============\n");
                try file.writeAll(vertexSrc);
            }
            var success: i32 = undefined;
            const vs = vs: {
                const vs: u32 = gl.CreateShader(gl.VERTEX_SHADER);
                gl.ShaderSource(vs, 1, &.{vertexSrc.ptr}, null);
                gl.CompileShader(vs);
                gl.GetShaderiv(vs, gl.COMPILE_STATUS, &success);
                if (success == gl.FALSE) Utils.infoLog(vs, "Shader didn't compile: {s}", gl.GetShaderInfoLog);
                break :vs vs;
            };

            const fs = fs: {
                const fs: u32 = gl.CreateShader(gl.FRAGMENT_SHADER);
                gl.ShaderSource(fs, 1, &.{fragmentSrc.ptr}, null);
                gl.CompileShader(fs);
                gl.GetShaderiv(fs, gl.COMPILE_STATUS, &success);
                if (success == gl.FALSE) Utils.infoLog(fs, "Shader didn't compile: {s}", gl.GetShaderInfoLog);
                break :fs fs;
            };
            const sh = sh: {
                const sh: u32 = gl.CreateProgram();
                gl.AttachShader(sh, vs);
                gl.AttachShader(sh, fs);
                gl.DeleteShader(vs);
                gl.DeleteShader(fs);
                gl.LinkProgram(sh);
                gl.GetProgramiv(sh, gl.LINK_STATUS, &success);
                if (success == gl.FALSE) Utils.infoLog(sh, "Shader didn't link: {s}", gl.GetProgramInfoLog);
                break :sh sh;
            };
            return .{ .id = sh };
        }
        pub fn set(loc: i32, value: anytype) void {
            const ti = @typeInfo(@TypeOf(value));
            switch (@TypeOf(value)) {
                f32 => gl.Uniform1f(loc, value),
                @Vector(2, f32) => gl.Uniform2f(loc, value[0], value[1]),
                @Vector(3, f32) => gl.Uniform3f(loc, value[0], value[1], value[2]),
                @Vector(4, f32) => gl.Uniform4f(loc, value[0], value[1], value[2], value[3]),
                zm.Mat4f => {
                    const val: [16]f32 = value.transpose().data;
                    gl.UniformMatrix4fv(loc, 1, gl.FALSE, &val);
                },
                Texture => {
                    value.bind();
                    gl.Uniform1i(loc, @intCast(value.slot));
                },
                else => if (ti == .array) {
                    const off = comptime uniformLen(ti.array.child);
                    inline for (0..ti.array.len) |i|
                        set(loc + @as(i32, @intCast(i * off)), value[i]);
                } else if (ti == .@"struct") {
                    comptime var off = 0;
                    inline for (ti.@"struct".fields) |field| {
                        set(loc + off, @field(value, field.name));
                        off += comptime uniformLen(field.type);
                    }
                } else @compileError("Unknown type: " ++ @typeName(@TypeOf(value))),
            }
        }
        pub fn use(self: @This(), us: Uniforms) void {
            gl.UseProgram(self.id);
            comptime var loc = 0;
            inline for (@typeInfo(Uniforms).@"struct".fields) |field| {
                const val = @field(us, field.name);
                set(loc, val);
                loc += comptime uniformLen(field.type);
            }
        }
        pub fn deinit(self: @This()) void {
            gl.DeleteProgram(self.id);
        }
    };
}
pub const Triangle = struct { u32, u32, u32 };
pub fn Mesh(Vertex: type) type {
    return struct {
        VAO: u32,
        VBO: u32,
        EBO: u32,
        triCount: i32,
        pub fn quad() @This() {
            const vertices = [_]Vertex{
                .{ .aPos = .{ 0.5, 0.5, 0.0 }, .aTexCoord = .{ 1, 1 } },
                .{ .aPos = .{ 0.5, -0.5, 0.0 }, .aTexCoord = .{ 1, 0 } },
                .{ .aPos = .{ -0.5, -0.5, 0.0 }, .aTexCoord = .{ 0, 0 } },
                .{ .aPos = .{ -0.5, 0.5, 0.0 }, .aTexCoord = .{ 0, 1 } },
            };
            const indices = [_]Triangle{ .{ 0, 1, 3 }, .{ 1, 2, 3 } };
            return init(&vertices, &indices);
        }
        pub fn init(vertices: []const Vertex, triangles: []const Triangle) @This() {
            const VBO: u32 = Utils.generate(gl.GenBuffers);
            const EBO: u32 = Utils.generate(gl.GenBuffers);
            const VAO: u32 = Utils.generate(gl.GenVertexArrays);
            {
                gl.BindVertexArray(VAO);
                gl.BindBuffer(gl.ARRAY_BUFFER, VBO);
                gl.BufferData(gl.ARRAY_BUFFER, @sizeOf(Vertex) * @as(i64, @intCast(vertices.len)), vertices.ptr, gl.STATIC_DRAW);
                gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, EBO);
                gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, @sizeOf(Triangle) * @as(i64, @intCast(triangles.len)), triangles.ptr, gl.STATIC_DRAW);
                inline for (@typeInfo(Vertex).@"struct".fields, 0..) |field, i| {
                    switch (field.type) {
                        f32 => gl.VertexAttribPointer(i, 1, gl.FLOAT, gl.FALSE, @sizeOf(Vertex), @offsetOf(Vertex, field.name)),
                        @Vector(2, f32) => gl.VertexAttribPointer(i, 2, gl.FLOAT, gl.FALSE, @sizeOf(Vertex), @offsetOf(Vertex, field.name)),
                        @Vector(3, f32) => gl.VertexAttribPointer(i, 3, gl.FLOAT, gl.FALSE, @sizeOf(Vertex), @offsetOf(Vertex, field.name)),
                        @Vector(4, f32) => gl.VertexAttribPointer(i, 4, gl.FLOAT, gl.FALSE, @sizeOf(Vertex), @offsetOf(Vertex, field.name)),
                        else => @compileError("Vertex can have only fields of `VecN` type"),
                    }
                    gl.EnableVertexAttribArray(i);
                }
            }
            return .{ .VAO = VAO, .VBO = VBO, .EBO = EBO, .triCount = @intCast(triangles.len) };
        }
        pub fn deinit(self: @This()) void {
            var VAO = [_]u32{self.VAO};
            var VBO = [_]u32{self.VBO};
            var EBO = [_]u32{self.EBO};
            gl.DeleteVertexArrays(1, &VAO);
            gl.DeleteBuffers(1, &VBO);
            gl.DeleteBuffers(1, &EBO);
        }
        pub fn draw(self: @This()) void {
            gl.BindVertexArray(self.VAO);
            gl.DrawElements(gl.TRIANGLES, 3 * self.triCount, gl.UNSIGNED_INT, 0);
        }
    };
}

pub const App = struct {
    window: *glfw.Window,
    var procs: *gl.ProcTable = undefined;
    pub fn init(width: u32, height: u32, title: [*:0]const u8) !@This() {
        try glfw.init();
        glfw.windowHint(glfw.ContextVersionMajor, 3);
        glfw.windowHint(glfw.ContextVersionMinor, 3);
        glfw.windowHint(glfw.OpenGLProfile, glfw.OpenGLCoreProfile);

        const dims: struct { c_int, c_int } = .{ @intCast(width), @intCast(height) };
        const window = try glfw.createWindow(dims[0], dims[1], title, null, null);
        glfw.makeContextCurrent(window);

        procs = try std.heap.c_allocator.create(gl.ProcTable);
        if (!procs.init(glfw.getProcAddress)) return error.InitFailed;
        gl.makeProcTableCurrent(procs);

        Mouse.init(window);
        return .{ .window = window };
    }
    pub fn deinit(self: @This()) void {
        std.heap.c_allocator.destroy(self.procs);
        gl.makeProcTableCurrent(null);
        glfw.makeContextCurrent(null);
        glfw.destroyWindow(self.window);
        glfw.terminate();
    }
    pub fn windowOpened(self: *@This()) ?*glfw.Window {
        glfw.swapBuffers(self.window);
        glfw.pollEvents();
        if (glfw.windowShouldClose(self.window)) return null;
        return self.window;
    }
    fn glSetProcs(table: ?*const gl.ProcTable) callconv(.c) void {
        gl.makeProcTableCurrent(table);
    }
    pub fn postReload(dynLib: *std.DynLib) void {
        dynLib.lookup(@TypeOf(&glSetProcs), "glSetProcs").?(procs);
        dynLib.lookup(
            @TypeOf(&Mouse.setCallbackData),
            "mouseSetCallbackData",
        ).?(Mouse.Callback.data);
    }
};
comptime {
    @export(&App.glSetProcs, .{ .name = "glSetProcs" });
}

pub const Watch = struct {
    path: []const u8,
    mtime: i128,
    pub fn init(path: []const u8) @This() {
        return .{ .path = path, .mtime = 0 };
    }
    pub fn changed(self: *@This()) !bool {
        const f = try std.fs.cwd().openFile(self.path, std.fs.File.OpenFlags{});
        defer f.close();
        const s = try f.stat();
        if (self.mtime == s.mtime) return false;
        self.mtime = s.mtime;
        return true;
    }
};

pub fn Reloader(fns: anytype, postReload: *const fn (*std.DynLib) void) type {
    const soPath: []const u8 = "zig-out/lib/libreloadable.so";
    var FnsI = @typeInfo(@TypeOf(fns)).@"struct";
    var fields: [FnsI.fields.len]std.builtin.Type.StructField = undefined;
    for (FnsI.fields, 0..) |field, i| {
        const func = @field(fns, field.name);
        fields[i] = field;
        fields[i].is_comptime = false;
        const Ti = @typeInfo(field.type);
        if (Ti != .pointer or @typeInfo(Ti.pointer.child) != .@"fn")
            @compileError("Expected function pointer, got: " ++ @typeName(field.type));
        @export(func, .{ .name = field.name });
    }
    FnsI.fields = &fields;
    const Fns = @Type(.{ .@"struct" = FnsI });
    const new_fns = x: {
        var sol: Fns = undefined;
        for (FnsI.fields) |field| @field(sol, field.name) = @field(fns, field.name);
        break :x sol;
    };
    return struct {
        dynLib: std.DynLib,
        watch: Watch,
        reg: Fns = new_fns,
        pub fn init() !@This() {
            const dynLib = try std.DynLib.open(soPath);
            return .{ .dynLib = dynLib, .watch = Watch.init(soPath) };
        }
        pub fn deinit(self: *@This()) void {
            self.dynLib.close();
        }
        pub fn reload(self: *@This()) !void {
            if (!(try self.watch.changed())) return;
            self.dynLib.close();
            self.dynLib = try std.DynLib.open(soPath);
            inline for (std.meta.fields(Fns)) |field| {
                const f = self.dynLib.lookup(field.type, field.name);
                const msg = if (f) |_| "Found" else "Didn't find";
                std.debug.print("{s} identifier: {s}\n", .{ msg, field.name });
                if (f) |x| @field(self.reg, field.name) = x;
            }
            postReload(&self.dynLib);
        }
    };
}

pub const Keyboard = struct {
    pub fn Binding(Action: type) type {
        return struct { key: glfw.Key, action: Action };
    }
    pub fn getActions(window: *glfw.Window, Action: type, comptime as: []const Binding(Action)) []Action {
        var sol: [as.len]Action = undefined;
        var i: u32 = 0;
        inline for (as) |a| if (glfw.getKey(window, a.key) == glfw.Press) {
            sol[i] = a.action;
            i += 1;
        };
        return sol[0..i];
    }
    pub fn movement3D(window: *glfw.Window) @Vector(3, f32) {
        var sol: @Vector(3, f32) = .{ 0, 0, 0 };
        for (Keyboard.getActions(window, @Vector(3, f32), &.{
            .{ .key = glfw.KeyW, .action = .{ 0, 0, 1 } },
            .{ .key = glfw.KeyS, .action = .{ 0, 0, -1 } },
            .{ .key = glfw.KeyD, .action = .{ 1, 0, 0 } },
            .{ .key = glfw.KeyA, .action = .{ -1, 0, 0 } },
            .{ .key = glfw.KeySpace, .action = .{ 0, 1, 0 } },
            .{ .key = glfw.KeyLeftShift, .action = .{ 0, -1, 0 } },
        })) |v| sol += v;
        return sol;
    }
};

pub const Mouse = struct {
    pub const Offsets = struct {
        position: @Vector(2, f32) = .{ 0, 0 },
        scroll: @Vector(2, f32) = .{ 0, 0 },
    };
    var last: ?Offsets = null;
    var callbackData: Offsets = undefined;
    const Callback = struct {
        var data: *Offsets = &callbackData;
        fn position(_: *glfw.Window, xpos: f64, ypos: f64) callconv(.C) void {
            data.position = .{ @floatCast(xpos), @floatCast(ypos) };
        }
        fn scroll(_: *glfw.Window, xoff: f64, yoff: f64) callconv(.C) void {
            data.scroll += .{ @floatCast(xoff), @floatCast(yoff) };
        }
    };
    pub fn init(window: *glfw.Window) void {
        _ = glfw.setCursorPosCallback(window, Callback.position);
        _ = glfw.setScrollCallback(window, Callback.scroll);
    }
    pub fn setFpsMode(window: *glfw.Window) void {
        glfw.setInputMode(window, glfw.Cursor, glfw.CursorDisabled);
    }
    pub fn setNormalMode(window: *glfw.Window) void {
        glfw.setInputMode(window, glfw.Cursor, glfw.CursorNormal);
    }
    pub fn getOffsets() Offsets {
        const sol = if (last) |l| Offsets{
            .position = Callback.data.position - l.position,
            .scroll = Callback.data.scroll - l.scroll,
        } else Offsets{};
        last = .{ .position = Callback.data.position, .scroll = Callback.data.scroll };
        return sol;
    }
    fn setCallbackData(data: *Offsets) callconv(.c) void {
        Callback.data = data;
    }
};
comptime {
    @export(&Mouse.setCallbackData, .{ .name = "mouseSetCallbackData" });
}

const EulerAngles = struct {
    angles: @Vector(3, f32), // yaw[0]  pitch[1] roll[2]
    fn toDir(self: @This()) @Vector(3, f32) {
        return .{
            std.math.cos(self.angles[0]) * std.math.cos(self.angles[1]),
            std.math.sin(self.angles[1]),
            std.math.sin(self.angles[0]) * std.math.cos(self.angles[1]),
        };
    }
    fn fromDir(dir: @Vector(3, f32)) @This() {
        return .{ .angles = .{ std.math.atan2(dir[2], dir[0]), std.math.asin(dir[1]), 0.0 } };
    }
};
// ToDo elongated x axis?
pub const Camera = struct {
    pub const InputOffsets = struct {
        position: Vec3,
        rotation: Vec2,
        zoom: f32,
    };
    pos: Vec3,
    dir: Vec3,
    fovy: f32,
    pub fn init(pos: Vec3, dir: Vec3) @This() {
        const fovy = std.math.degreesToRadians(60);
        return .{ .pos = pos, .dir = zm.vec.normalize(dir), .fovy = fovy };
    }
    pub fn view(self: @This()) zm.Mat4f {
        return zm.Mat4f.lookAt(self.pos, self.pos + self.dir, zm.vec.up(f32));
    }
    pub fn projection(self: @This(), width: usize, height: usize) zm.Mat4f {
        const aspect = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height));
        return zm.Mat4f.perspective(self.fovy, aspect, 0.5, 100);
    }
    pub fn update(self: *@This(), offsets: InputOffsets) void {
        const right = zm.vec.normalize(zm.vec.cross(self.dir, zm.vec.up(f32)));
        const up = zm.vec.normalize(zm.vec.cross(right, self.dir));
        self.pos += zm.vec.scale(right, offsets.position[0]);
        self.pos += zm.vec.scale(up, offsets.position[1]);
        self.pos += zm.vec.scale(self.dir, offsets.position[2]);

        var ang = EulerAngles.fromDir(self.dir);
        ang.angles += .{ offsets.rotation[0], -offsets.rotation[1], 0.0 };
        const limit = std.math.degreesToRadians(89);
        ang.angles[1] = std.math.clamp(ang.angles[1], -limit, limit);
        self.dir = ang.toDir();
        self.fovy = std.math.clamp(self.fovy - offsets.zoom * 0.02, 0.01, 0.8);
    }
};
