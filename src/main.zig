const std = @import("std");
const gl = @import("gl");
const glfw = @import("glfw");
const m = @import("zalgebra");

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

fn Shader(Uniforms: type) type {
    return struct {
        id: u32,
        locs: [std.meta.fields(Uniforms).len]i32,
        fn infoLog(id: u32, comptime msg: []const u8) void {
            var buff: [512:0]u8 = .{0} ** 512;
            gl.GetShaderInfoLog(id, 512, null, &buff);
            std.log.err(msg, .{buff[0..std.mem.len(@as([*:0]u8, &buff))]});
        }
        fn init(vsFile: []const u8, fsFile: []const u8) !@This() {
            var success: i32 = undefined;
            const vs = vs: {
                const vertexSrc = src: {
                    var file = try std.fs.cwd().openFile(vsFile, .{});
                    defer file.close();
                    break :src try file.readToEndAlloc(std.heap.c_allocator, 100000);
                };
                const vs: u32 = gl.CreateShader(gl.VERTEX_SHADER);
                gl.ShaderSource(vs, 1, &.{vertexSrc.ptr}, null);
                gl.CompileShader(vs);
                gl.GetShaderiv(vs, gl.COMPILE_STATUS, &success);
                if (success == 0) infoLog(vs, "Shader didn't compile: {s}");
                break :vs vs;
            };

            const fs = fs: {
                const fragmentSrc = src: {
                    var file = try std.fs.cwd().openFile(fsFile, .{});
                    defer file.close();
                    break :src try file.readToEndAlloc(std.heap.c_allocator, 100000);
                };
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
            var locs: [std.meta.fields(Uniforms).len]i32 = undefined;
            inline for (std.meta.fieldNames(Uniforms), 0..) |uname, i|
                locs[i] = gl.GetUniformLocation(sh, uname);
            return .{ .id = sh, .locs = locs };
        }
        fn set(loc: i32, value: anytype) void {
            if (@TypeOf(value) == m.Vec4) {
                gl.Uniform4f(loc, value.x(), value.y(), value.z(), value.w());
            } else @compileError("Unknown type!");
        }
        fn use(self: @This(), uniforms: Uniforms) void {
            gl.UseProgram(self.id);
            inline for (std.meta.fields(Uniforms), 0..) |field, i| {
                const val = @field(uniforms, field.name);
                set(self.locs[i], val);
            }
        }
        fn deinit(self: @This()) void {
            gl.DeleteProgram(self.id);
        }
    };
}
fn Mesh(Vertex: type) type {
    return struct {
        VAO: u32,
        VBO: u32,
        EBO: u32,
        fn init(vertices: []const Vertex, indices: []const u32) @This() {
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
                gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, @sizeOf(u32) * @as(i64, @intCast(indices.len)), indices.ptr, gl.STATIC_DRAW);
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
            return .{ .VAO = VAO, .VBO = VBO, .EBO = EBO };
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
        fn draw(_: @This()) void {
            gl.DrawElements(gl.TRIANGLES, 6, gl.UNSIGNED_INT, 0);
        }
    };
}

const Vec2 = @Vector(2, f32);
const Vec3 = @Vector(3, f32);
const Vec4 = @Vector(4, f32);

const Triangle = struct {
    const Vertex = struct { aPos: Vec3 };
    const Uniforms = struct { color: m.Vec4 };
    sh: Shader(Uniforms),
    mesh: Mesh(Vertex),
    fn init() !@This() {
        const vertices = [_]Vertex{
            .{ .aPos = .{ 0.5, 0.5, 0.0 } },
            .{ .aPos = .{ 0.5, -0.5, 0.0 } },
            .{ .aPos = .{ -0.5, -0.5, 0.0 } },
            .{ .aPos = .{ -0.5, 0.5, 0.0 } },
        };
        const indices = [_]u32{ 0, 1, 3, 1, 2, 3 };
        return .{
            .sh = try Shader(Uniforms).init("src/vertex.glsl", "src/fragment.glsl"),
            .mesh = Mesh(Vertex).init(&vertices, &indices),
        };
    }
    fn deinit(self: @This()) void {
        self.mesh.deinit();
        self.sh.deinit();
    }
    fn draw(self: @This()) void {
        self.sh.use(.{ .color = m.Vec4.new(1, 1, 0, 0) });
        self.mesh.use();
        self.mesh.draw();
    }
};

var procs: gl.ProcTable = undefined;
pub fn main() !void {
    // var ally = std.heap.GeneralPurposeAllocator(.{}){};
    // const allocator = ally.allocator();

    try glfw.init();
    defer glfw.terminate();

    const window: *glfw.Window = try glfw.createWindow(800, 640, "Hello World", null, null);
    defer glfw.destroyWindow(window);
    glfw.makeContextCurrent(window);
    defer glfw.makeContextCurrent(null);

    if (!procs.init(glfw.getProcAddress)) return error.InitFailed;

    gl.makeProcTableCurrent(&procs);
    defer gl.makeProcTableCurrent(null);

    var t = try Triangle.init();
    defer t.deinit();

    // gl.PolygonMode(gl.FRONT_AND_BACK, gl.LINE);
    gl.Enable(gl.COLOR_BUFFER_BIT);
    while (!glfw.windowShouldClose(window)) {
        if (glfw.getKey(window, glfw.KeyEscape) == glfw.Press) {
            glfw.setWindowShouldClose(window, true);
        }
        gl.ClearColor(1, 0, 0, 1);
        gl.Clear(gl.COLOR_BUFFER_BIT);

        t.draw();
        glfw.swapBuffers(window);
        glfw.pollEvents();
    }
}
