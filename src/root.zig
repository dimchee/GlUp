const std = @import("std");
pub const gl = @import("gl");
pub const glfw = @import("glfw");
pub const m = @import("zalgebra");
pub const lodepng = @cImport(@cInclude("lodepng.h"));

const Camera = struct {
    position: m.Vec3,
    target: m.Vec3,
    up: m.Vec3,
    fovy: f32,
    fn view(self: @This()) m.Mat4 {
        m.lookAt(self.position, self.target, .{ 0, 1, 0 });
    }
    fn perspective(self: @This()) m.Mat4 {
        m.perspective(self.fovy, 16 / 9, 0.5, 100);
    }
};

const Texture = struct {
    id: u32,
    fn init(filePath: []const u8) !@This() {
        const id = x: {
            var x: [1]u32 = undefined;
            gl.GenTextures(1, &x);
            break :x x[0];
        };
        gl.ActiveTexture(gl.TEXTURE0); // save tex slot so you can bind it
        gl.BindTexture(gl.TEXTURE_2D, id);
        // set the texture wrapping/filtering options (on the currently bound texture object)
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
        // load and generate the texture
        // var image = try zigimg.Image.fromFilePath(std.heap.c_allocator, filePath);
        // defer image.deinit();
        var image: [*c] u8 = undefined;
        var width: u32 =  undefined;
        var height: u32 =  undefined;

        _ = lodepng.lodepng_decode32_file(&image, &width, &height, filePath.ptr);
        gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGB, @intCast(width), @intCast(height), 0, gl.RGB, gl.UNSIGNED_BYTE, image);
        gl.GenerateMipmap(gl.TEXTURE_2D);
        return .{ .id = id };
    }
};

fn Shader(VUniforms: type, FUniforms: type, Vertex: type) type {
    return struct {
        id: u32,
        flocs: [std.meta.fields(FUniforms).len]i32,
        vlocs: [std.meta.fields(VUniforms).len]i32,
        fn infoLog(id: u32, comptime msg: []const u8) void {
            var buff: [512:0]u8 = .{0} ** 512;
            gl.GetShaderInfoLog(id, 512, null, &buff);
            std.log.err(msg, .{buff[0..std.mem.len(@as([*:0]u8, &buff))]});
        }
        fn fileContent(fileName: []const u8) ![]u8 {
            var file = try std.fs.cwd().openFile(fileName, .{});
            defer file.close();
            return try file.readToEndAlloc(std.heap.c_allocator, 100000);
        }
        fn toType(t: type) []const u8 {
            return if (t == @Vector(4, f32))
                "vec4"
            else if (t == @Vector(3, f32))
                "vec3"
            else if (t == @Vector(2, f32))
                "vec2"
            else if (t == f32)
                "float"
            else if (t == ?Texture)
                "sampler2D"
            else
                @compileError("Unknown type");
        }
        fn attributes() []const u8 {
            comptime {
                var sol: []const u8 = "";
                for (std.meta.fields(Vertex), 0..) |field, i|
                    sol = sol ++ std.fmt.comptimePrint("\nlayout (location = {}) in {s} {s};", .{ i, toType(field.type), field.name });
                return sol;
            }
        }
        fn uniforms(Uniforms: type) []const u8 {
            comptime {
                var sol: []const u8 = "";
                for (std.meta.fields(Uniforms)) |field|
                    sol = sol ++ std.fmt.comptimePrint("\nuniform {s} {s};", .{ toType(field.type), field.name });
                return sol;
            }
        }
        fn initFromFiles(vsFile: []const u8, fsFile: []const u8) !@This() {
            return init(try fileContent(vsFile), try fileContent(fsFile));
        }
        fn init(vertexSource: []const u8, fragmentSource: []const u8) !@This() {
            const vertexSrc = try std.mem.join(std.heap.page_allocator, "\n", &.{
                "#version 320 es",
                "out vec2 TexCoord;",
                comptime attributes(),
                comptime uniforms(VUniforms),
                vertexSource,
            });
            const fragmentSrc = try std.mem.join(std.heap.page_allocator, "\n", &.{
                "#version 320 es",
                "precision mediump float;",
                "out vec4 FragColor;",
                "in vec2 TexCoord;",
                comptime uniforms(FUniforms),
                fragmentSource,
            });
            var success: i32 = undefined;
            const vs = vs: {
                const vs: u32 = gl.CreateShader(gl.VERTEX_SHADER);
                gl.ShaderSource(vs, 1, &.{vertexSrc.ptr}, null);
                gl.CompileShader(vs);
                gl.GetShaderiv(vs, gl.COMPILE_STATUS, &success);
                if (success == 0) infoLog(vs, "Shader didn't compile: {s}");
                break :vs vs;
            };

            const fs = fs: {
                const fs: u32 = gl.CreateShader(gl.FRAGMENT_SHADER);
                gl.ShaderSource(fs, 1, &.{fragmentSrc.ptr}, null);
                gl.CompileShader(fs);
                gl.GetShaderiv(fs, gl.COMPILE_STATUS, &success);
                if (success == 0) infoLog(fs, "Shader didn't compile: {s}");
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
                if (success == 0) infoLog(sh, "Shader didn't link {s}");
                break :sh sh;
            };
            var flocs: [std.meta.fields(FUniforms).len]i32 = undefined;
            var vlocs: [std.meta.fields(VUniforms).len]i32 = undefined;
            inline for (std.meta.fieldNames(FUniforms), 0..) |uname, i|
                flocs[i] = gl.GetUniformLocation(sh, uname);
            inline for (std.meta.fieldNames(VUniforms), 0..) |uname, i|
                vlocs[i] = gl.GetUniformLocation(sh, uname);
            return .{ .id = sh, .flocs = flocs, .vlocs = vlocs };
        }
        fn set(loc: i32, value: anytype) void {
            if (@TypeOf(value) == @Vector(4, f32))
                gl.Uniform4f(loc, value[0], value[1], value[2], value[3])
            else if (@TypeOf(value) == @Vector(3, f32))
                gl.Uniform3f(loc, value[0], value[1], value[2])
            else if (@TypeOf(value) == @Vector(2, f32))
                gl.Uniform2f(loc, value[0], value[1])
            else if (@TypeOf(value) == ?Texture)
                gl.Uniform1i(loc, 0)
                // std.debug.print("Texture...", .{})
            else
                @compileError("Unknown type!");
        }
        fn use(self: @This(), vus: VUniforms, fus: FUniforms) void {
            gl.UseProgram(self.id);
            inline for (std.meta.fields(FUniforms), 0..) |field, i| {
                const val = @field(fus, field.name);
                set(self.flocs[i], val);
            }
            inline for (std.meta.fields(VUniforms), 0..) |field, i| {
                const val = @field(vus, field.name);
                set(self.vlocs[i], val);
            }
        }
        fn deinit(self: @This()) void {
            gl.DeleteProgram(self.id);
        }
    };
}
const Triangle = struct { u32, u32, u32 };
fn Mesh(Vertex: type) type {
    return struct {
        VAO: u32,
        VBO: u32,
        EBO: u32,
        triCount: i32,
        fn init(vertices: []const Vertex, indices: []const Triangle) @This() {
            const VBO: u32 = x: {
                var x: [1]u32 = undefined;
                gl.GenBuffers(1, &x);
                break :x x[0];
            };
            const EBO: u32 = x: {
                var x: [1]u32 = undefined;
                gl.GenBuffers(1, &x);
                break :x x[0];
            };
            const VAO: u32 = x: {
                var x: [1]u32 = undefined;
                gl.GenVertexArrays(1, &x);
                break :x x[0];
            };
            {
                gl.BindVertexArray(VAO);
                gl.BindBuffer(gl.ARRAY_BUFFER, VBO);
                gl.BufferData(gl.ARRAY_BUFFER, @sizeOf(Vertex) * @as(i64, @intCast(vertices.len)), vertices.ptr, gl.STATIC_DRAW);
                gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, EBO);
                gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, @sizeOf(Triangle) * @as(i64, @intCast(indices.len)), indices.ptr, gl.STATIC_DRAW);
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
            return .{ .VAO = VAO, .VBO = VBO, .EBO = EBO, .triCount = @intCast(indices.len) };
        }
        fn deinit(self: @This()) void {
            var VAO = [_]u32{self.VAO};
            var VBO = [_]u32{self.VBO};
            var EBO = [_]u32{self.EBO};
            gl.DeleteVertexArrays(1, &VAO);
            gl.DeleteBuffers(1, &VBO);
            gl.DeleteBuffers(1, &EBO);
        }
        fn use(self: @This()) void {
            gl.BindVertexArray(self.VAO);
        }
        fn draw(self: @This()) void {
            gl.DrawElements(gl.TRIANGLES, 3 * self.triCount, gl.UNSIGNED_INT, 0);
        }
    };
}

pub const Vec2 = @Vector(2, f32);
pub const Vec3 = @Vector(3, f32);
pub const Vec4 = @Vector(4, f32);

pub const Quad = struct {
    const Vertex = struct { aPos: Vec3, aTexCoord: Vec2 };
    const VUniforms = struct { pos: Vec2 };
    const FUniforms = struct { color: Vec4, texture0: ?Texture };
    sh: Shader(VUniforms, FUniforms, Vertex),
    mesh: Mesh(Vertex),
    pos: Vec2,
    pub fn init() !@This() {
        const vertices = [_]Vertex{
            .{ .aPos = .{ 0.5, 0.5, 0.0 }, .aTexCoord = .{ 1, 1 } },
            .{ .aPos = .{ 0.5, -0.5, 0.0 }, .aTexCoord = .{ 1, 0 } },
            .{ .aPos = .{ -0.5, -0.5, 0.0 }, .aTexCoord = .{ 0, 0 } },
            .{ .aPos = .{ -0.5, 0.5, 0.0 }, .aTexCoord = .{ 0, 1 } },
        };
        _ = try Texture.init("tile.png");
        const indices = [_]Triangle{ .{ 0, 1, 3 }, .{ 1, 2, 3 } };
        return .{
            .sh = try Shader(VUniforms, FUniforms, Vertex).init(
                "void main() { gl_Position = vec4(aPos + vec3(pos, 0.0), 1.0); TexCoord = aTexCoord; }",
                "void main() { FragColor = color; }",
            ),
            .mesh = Mesh(Vertex).init(&vertices, &indices),
            .pos = .{ 0, 0 },
        };
    }
    pub fn deinit(self: @This()) void {
        self.mesh.deinit();
        self.sh.deinit();
    }
    pub fn draw(self: @This()) void {
        self.sh.use(
            .{ .pos = self.pos },
            .{ .color = .{ 1, 1, 0, 0 }, .texture0 = null },
        );
        self.mesh.use();
        self.mesh.draw();
    }
};

pub const Window = struct {
    window: *glfw.Window,
    procs: gl.ProcTable,
    pub fn init(width: u32, height: u32, title: [*:0]const u8, callback: glfw.KeyFun) !@This() {
        try glfw.init();

        const window: *glfw.Window = try glfw.createWindow(@intCast(width), @intCast(height), title, null, null);
        glfw.makeContextCurrent(window);
        _ = glfw.setKeyCallback(window, callback);

        var procs: gl.ProcTable = undefined;
        if (!procs.init(glfw.getProcAddress)) return error.InitFailed;

        return .{ .window = window, .procs = procs };
    }
    pub fn useProcTable(self: *const @This()) void {
        gl.makeProcTableCurrent(&self.procs);
    }
    pub fn deinit(self: @This()) void {
        gl.makeProcTableCurrent(null);
        glfw.makeContextCurrent(null);
        glfw.destroyWindow(self.window);
        glfw.terminate();
    }
};
