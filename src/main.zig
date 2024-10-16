const std = @import("std");
const gl = @import("gl");
const glfw = @import("glfw");

const vertexSrc =
    \\#version 300 es
    \\layout (location = 0) in vec3 aPos;
    \\void main()
    \\{
    \\   gl_Position = vec4(aPos.x, aPos.y, aPos.z, 1.0);
    \\}
;
const fragmentSrc =
    \\#version 300 es
    \\
    \\precision mediump float;
    \\
    \\out vec4 FragColor;
    \\
    \\void main()
    \\{
    \\    FragColor = vec4(1.0f, 0.5f, 0.2f, 1.0f);
    \\} 
;

const Triangle = struct {
    VAO: u32,
    VBO: u32,
    EBO: u32,
    sh: u32,
    fn init() @This() {
        const vertices = [_]f32{
            0.5, 0.5, 0.0, // top right
            0.5, -0.5, 0.0, // bottom right
            -0.5, -0.5, 0.0, // bottom left
            -0.5, 0.5, 0.0, // top left
        };
        const indices = [_]u32{ 0, 1, 3, 1, 2, 3 };
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
            gl.BufferData(gl.ARRAY_BUFFER, @sizeOf(@TypeOf(vertices)), &vertices, gl.STATIC_DRAW);
            gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, EBO);
            gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, @sizeOf(@TypeOf(indices)), &indices, gl.STATIC_DRAW);
            gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 3 * @sizeOf(f32), 0);
            gl.EnableVertexAttribArray(0);
        }
        const vs = vs: {
            const vs: u32 = gl.CreateShader(gl.VERTEX_SHADER);
            gl.ShaderSource(vs, 1, &.{vertexSrc}, null);
            gl.CompileShader(vs);
            var success: i32 = undefined;
            gl.GetShaderiv(vs, gl.COMPILE_STATUS, &success);
            if (success == 0) {
                var infoLog: [512:0]u8 = .{0} ** 512;
                gl.GetShaderInfoLog(vs, 512, null, &infoLog);
                std.log.err("Shader didn't compile: {s}", .{infoLog[0..std.mem.len(@as([*:0]u8, &infoLog))]});
            }
            break :vs vs;
        };

        const fs = fs: {
            const fs: u32 = gl.CreateShader(gl.FRAGMENT_SHADER);
            gl.ShaderSource(fs, 1, &.{fragmentSrc}, null);
            gl.CompileShader(fs);
            var success: i32 = undefined;
            gl.GetShaderiv(fs, gl.COMPILE_STATUS, &success);
            if (success == 0) {
                var infoLog: [512:0]u8 = .{0} ** 512;
                gl.GetShaderInfoLog(fs, 512, null, &infoLog);
                std.log.err("Shader didn't compile: {s}", .{infoLog[0..std.mem.len(@as([*:0]u8, &infoLog))]});
            }
            break :fs fs;
        };
        const sh = sh: {
            const sh: u32 = gl.CreateProgram();
            gl.AttachShader(sh, vs);
            gl.AttachShader(sh, fs);
            gl.DeleteShader(vs);
            gl.DeleteShader(fs);
            gl.LinkProgram(sh);
            var success: i32 = undefined;
            gl.GetProgramiv(sh, gl.LINK_STATUS, &success);
            if (success == 0) {
                var infoLog: [512:0]u8 = .{0} ** 512;
                gl.GetShaderInfoLog(sh, 512, null, &infoLog);
                std.log.err("Shader didn't link: {s}", .{infoLog[0..std.mem.len(@as([*:0]u8, &infoLog))]});
            }
            break :sh sh;
        };
        return .{ .VAO = VAO, .VBO = VBO, .EBO = EBO, .sh = sh };
    }
    fn deinit(self: @This()) void {
        var VAO = [_]u32{self.VAO};
        var VBO = [_]u32{self.VBO};
        var EBO = [_]u32{self.EBO};
        gl.DeleteVertexArrays(1, &VAO);
        gl.DeleteBuffers(1, &VBO);
        gl.DeleteBuffers(1, &EBO);
        gl.DeleteProgram(self.sh);
    }
    fn draw(self: @This()) void {
        gl.BindVertexArray(self.VAO);
        gl.UseProgram(self.sh);
        gl.DrawElements(gl.TRIANGLES, 6, gl.UNSIGNED_INT, 0);
    }
};

var procs: gl.ProcTable = undefined;
pub fn main() !void {
    try glfw.init();
    defer glfw.terminate();

    const window: *glfw.Window = try glfw.createWindow(800, 640, "Hello World", null, null);
    defer glfw.destroyWindow(window);
    glfw.makeContextCurrent(window);
    defer glfw.makeContextCurrent(null);

    if (!procs.init(glfw.getProcAddress)) return error.InitFailed;

    gl.makeProcTableCurrent(&procs);
    defer gl.makeProcTableCurrent(null);

    var t = Triangle.init();
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
