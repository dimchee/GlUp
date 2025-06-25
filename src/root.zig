const std = @import("std");
pub const gl = @import("gl");
pub const glfw = @import("glfw");
pub const zm = @import("zm");

pub const Vec2 = zm.Vec2f;
pub const Vec3 = zm.Vec3f;
pub const Vec4 = zm.Vec4f;

const Utils = struct {
    fn infoLog(id: u32, comptime msg: []const u8, log: anytype) void {
        var buff: [512:0]u8 = .{0} ** 512;
        log(id, 512, null, &buff);
        std.log.err(msg, .{buff[0..std.mem.len(@as([*:0]u8, &buff))]});
    }
    fn fileContent(fileName: []const u8) ![]u8 {
        var file = try std.fs.cwd().openFile(fileName, .{});
        defer file.close();
        return try file.readToEndAlloc(std.heap.c_allocator, 100000);
    }
    pub fn generate(gen: fn (c_int, [*]u32) void) u32 {
        var x: [1]u32 = undefined;
        gen(1, &x);
        return x[0];
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
        std.mem.reverse(Color, pixels[0 .. width * height]);
        // TODO Leaking memory
        if (err != 0) {
            std.debug.print("Error: {s}", .{png.lodepng_error_text(err)});
        }
        gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGB, @intCast(width), @intCast(height), 0, gl.RGBA, gl.UNSIGNED_BYTE, image);
        gl.GenerateMipmap(gl.TEXTURE_2D);

        return .{ .id = id, .slot = slot };
    }
    pub fn bind(self: *const @This()) void {
        gl.ActiveTexture(gl.TEXTURE0 + self.slot);
        gl.BindTexture(gl.TEXTURE_2D, self.id);
    }
    pub fn unbind() void {
        gl.BindTexture(gl.TEXTURE_2D, 0);
    }
    pub fn deinit(self: @This()) void {
        var id = [_]u32{self.id};
        gl.DeleteTextures(1, &id);
    }
};

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
            for (std.meta.fields(Uniforms), 0..) |field, i|
                sol = sol ++ std.fmt.comptimePrint(
                    "\nlayout (location = {}) uniform {s} {s};",
                    .{ i, toType(field.type), field.name },
                );
            break :x sol;
        };
        fn toType(t: type) []const u8 {
            return if (t == @Vector(4, f32))
                "vec4"
            else if (t == @Vector(3, f32))
                "vec3"
            else if (t == @Vector(2, f32))
                "vec2"
            else if (t == zm.Mat4f)
                "mat4"
            else if (t == f32)
                "float"
            else if (t == Texture)
                "sampler2D"
            else
                @compileError("Unknown type: " ++ @typeName(t));
        }
        pub fn initFromFiles(vsFile: []const u8, fsFile: []const u8) !@This() {
            return init(try Utils.fileContent(vsFile), try Utils.fileContent(fsFile));
        }
        pub fn init(vertexSource: []const u8, fragmentSource: []const u8) !@This() {
            const vertexSrc = try std.mem.join(std.heap.page_allocator, "\n", &.{
                "#version 320 es",
                "precision mediump float;",
                "out vec2 TexCoord;",
                attributes,
                uniforms,
                vertexSource,
            });
            const fragmentSrc = try std.mem.join(std.heap.page_allocator, "\n", &.{
                "#version 320 es",
                "precision mediump float;",
                "out vec4 FragColor;",
                "in vec2 TexCoord;",
                uniforms,
                fragmentSource,
            });
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
            if (@TypeOf(value) == @Vector(4, f32))
                gl.Uniform4f(loc, value[0], value[1], value[2], value[3])
            else if (@TypeOf(value) == @Vector(3, f32))
                gl.Uniform3f(loc, value[0], value[1], value[2])
            else if (@TypeOf(value) == @Vector(2, f32))
                gl.Uniform2f(loc, value[0], value[1])
            else if (@TypeOf(value) == zm.Mat4f) {
                const val: [16]f32 = value.transpose().data;
                gl.UniformMatrix4fv(loc, 1, gl.FALSE, &val);
            } else if (@TypeOf(value) == Texture)
                gl.Uniform1i(loc, @intCast(value.slot))
                // std.debug.print("Texture...", .{})
            else
                @compileError("Unknown type: " ++ @typeName(@TypeOf(value)));
        }
        pub fn use(self: @This(), us: Uniforms) void {
            gl.UseProgram(self.id);
            inline for (std.meta.fields(Uniforms), 0..) |field, i| {
                const val = @field(us, field.name);
                set(i, val);
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
                var ptr: usize = 0;
                inline for (std.meta.fields(Vertex), 0..) |field, i|
                    if (field.type == Vec2) {
                        gl.VertexAttribPointer(i, 2, gl.FLOAT, gl.FALSE, @sizeOf(Vertex), ptr);
                        gl.EnableVertexAttribArray(i);
                        ptr += @sizeOf(Vec2);
                    } else if (field.type == Vec3) {
                        gl.VertexAttribPointer(i, 3, gl.FLOAT, gl.FALSE, @sizeOf(Vertex), ptr);
                        gl.EnableVertexAttribArray(i);
                        ptr += @sizeOf(Vec3);
                    } else if (field.type == Vec4) {
                        gl.VertexAttribPointer(i, 4, gl.FLOAT, gl.FALSE, @sizeOf(Vertex), ptr);
                        gl.EnableVertexAttribArray(i);
                        ptr += @sizeOf(Vec4);
                    } else @compileError("Vertex can have only fields of `VecN` type");
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
        pub fn use(self: @This()) void {
            gl.BindVertexArray(self.VAO);
        }
        pub fn draw(self: @This()) void {
            gl.DrawElements(gl.TRIANGLES, 3 * self.triCount, gl.UNSIGNED_INT, 0);
        }
    };
}

pub const App = struct {
    window: *glfw.Window,
    var procs: gl.ProcTable = undefined;
    pub fn init(width: u32, height: u32, title: [*:0]const u8) !@This() {
        try glfw.init();
        glfw.windowHint(glfw.ContextVersionMajor, 3);
        glfw.windowHint(glfw.ContextVersionMinor, 3);
        glfw.windowHint(glfw.OpenGLProfile, glfw.OpenGLCoreProfile);

        const dims: struct { c_int, c_int } = .{ @intCast(width), @intCast(height) };
        const window = try glfw.createWindow(dims[0], dims[1], title, null, null);
        glfw.makeContextCurrent(window);

        if (!procs.init(glfw.getProcAddress)) return error.InitFailed;
        gl.makeProcTableCurrent(&procs);

        return .{ .window = window };
    }
    pub fn deinit(self: @This()) void {
        gl.makeProcTableCurrent(null);
        glfw.makeContextCurrent(null);
        glfw.destroyWindow(self.window);
        glfw.terminate();
    }
    fn is_struct(x: anytype) bool {
        return switch (@typeInfo(@TypeOf(x))) {
            .@"struct" => true,
            else => false,
        };
    }
    fn is_function(x: anytype) bool {
        return switch (@typeInfo(@TypeOf(x))) {
            .@"struct" => true,
            else => false,
        };
    }
    /// Accepts struct with optional fields:
    ///     .loop: ...
    ///     .init: ...
    ///     .state: anytype
    pub fn run(self: *const @This(), opts: anytype) !void {
        @export(&struct {
            pub fn f(table: ?*const gl.ProcTable) callconv(.c) void {
                gl.makeProcTableCurrent(table);
            }
        }.f, .{ .name = "glMakeProcTableCurrent" });
        const Opts = @TypeOf(opts);
        var state = if (@hasField(Opts, "state")) opts.state;
        if (@hasField(Opts, "init")) opts.init(self.window);
        const loop_reloadable = @hasField(Opts, "loop") and
            @typeInfo(@TypeOf(opts.loop)) != .@"fn";
        var loop = if (loop_reloadable) opts.loop else @as(u32, 0);

        while (!glfw.windowShouldClose(self.window)) {
            if (loop_reloadable) {
                try loop.reload();
                @TypeOf(loop).makeProcTableCurrent(&procs);
                loop.f();
            } else if (@hasField(Opts, "loop")) {
                const Args = std.meta.ArgsTuple(@TypeOf(opts.loop));
                const State = if (@hasField(Opts, "state")) @TypeOf(opts.state) else void;
                if (Args == @TypeOf(.{}))
                    opts.loop()
                else if (Args == struct { *glfw.Window })
                    opts.loop(self.window)
                else if (Args == struct { *State })
                    opts.loop(&state)
                else if (Args == struct { *glfw.Window, *State })
                    opts.loop(self.window, &state)
                else
                    @compileError("Error loop args: `" ++ @typeName(Args) ++ "`");
            }
            glfw.swapBuffers(self.window);
            glfw.pollEvents();
        }
    }
};

pub const Watch = struct {
    path: []const u8,
    mtime: i128,
    fn init(path: []const u8) @This() {
        return .{ .path = path, .mtime = 0 };
    }
    fn poll(self: *@This()) !bool {
        const f = try std.fs.cwd().openFile(self.path, std.fs.File.OpenFlags{});
        defer f.close();
        const s = try f.stat();
        if (self.mtime == s.mtime) return false;
        self.mtime = s.mtime;
        return true;
    }
};

pub const Reloader = struct {
    cnt: comptime_int = 0,
    pub fn New(rs: *@This(), func: anytype) type {
        const soPath: []const u8 = "zig-out/lib/libreloadable.so";
        const Func = @TypeOf(func);
        switch (@typeInfo(Func)) {
            .pointer => {},
            else => @compileError("Expected ptr, found '" ++ @typeName(Func) ++ "'"),
        }
        const identifier = std.fmt.comptimePrint("reloader_{}", .{rs.cnt});
        rs.cnt += 1;
        @export(func, .{ .name = identifier });
        return struct {
            const is_reloader: void = {};
            var makeProcTableCurrent = &gl.makeProcTableCurrent;
            f: Func,
            dynLib: std.DynLib,
            watch: Watch,
            pub fn init() !@This() {
                const dynLib = try std.DynLib.open(soPath);
                return .{ .f = func, .dynLib = dynLib, .watch = Watch.init(soPath) };
            }
            pub fn reload(self: *@This()) !void {
                if (!(try self.watch.poll())) return;
                self.dynLib.close();
                self.dynLib = try std.DynLib.open(soPath);
                if (self.dynLib.lookup(Func, identifier)) |_|
                    std.debug.print("Found identifier!\n", .{})
                else
                    std.debug.print("Didn't find identifier!\n", .{});
                makeProcTableCurrent = self.dynLib.lookup(
                    @TypeOf(makeProcTableCurrent),
                    "glMakeProcTableCurrent",
                ).?;
                self.f = self.dynLib.lookup(Func, identifier) orelse self.f;
            }
            pub fn deinit(self: *@This()) void {
                self.dynLib.close();
            }
        };
    }
};
