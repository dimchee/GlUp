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

const Vertex = extern struct {
    normal: @Vector(3, f32),
    position: @Vector(3, f32),
    tangent: @Vector(4, f32),
    texCoord: @Vector(2, f32),
};

const Reloader = glup.FileReloader(.{
    .sh = .{ "examples/model_gltf.glsl", struct {
        pub fn init(filePath: []const u8) !glup.Shader(Uniforms, Vertex) {
            return .initFromFile(filePath);
        }
        pub fn deinit(s: *glup.Shader(Uniforms, Vertex)) void {
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

pub fn toLen(x: glup.glTF.Accessor.Type) i32 {
    return switch (x) {
        .SCALAR => 1,
        .VEC2 => 2,
        .VEC3 => 3,
        .VEC4, .MAT2 => 4,
        .MAT3 => 9,
        .MAT4 => 16,
    };
}

const Model = struct {
    const DrawMode = union(enum) {
        elements: u32,
        vertices: void,
    };
    VAO: u32,
    BUF: u32,
    gltf: glup.glTF.Parsed,
    // ToDo use arena, don't save gltf
    // ToDo all asserts to gltf module as 'check'
    pub fn init(path: []const u8, alloc: std.mem.Allocator) !@This() {
        const gl = glup.gl;
        const BUF: u32 = glup.Utils.generate(gl.GenBuffers);
        const VAO: u32 = glup.Utils.generate(gl.GenVertexArrays);
        const gltf = x: {
            const data = try std.fs.cwd().readFileAlloc(alloc, path, 10000000); // ToDo leak
            break :x try glup.glTF.parse(alloc, data);
        };
        const val = gltf.value;
        for (val.buffers) |buf| {
            const uri = try std.fmt.allocPrint(alloc, "examples/cube/{s}", .{buf.uri.?});
            const data = try std.fs.cwd().readFileAlloc(alloc, uri, buf.byteLength);
            defer alloc.free(data);
            gl.BindVertexArray(VAO);
            gl.BindBuffer(gl.ARRAY_BUFFER, BUF);
            gl.BufferData(gl.ARRAY_BUFFER, @as(i64, @intCast(data.len)), data.ptr, gl.STATIC_DRAW);
        }

        const node = val.nodes[val.scenes[val.scene orelse 0].nodes[0]];
        if (node.mesh == null) return error.NoMesh;
        const mesh = val.meshes[node.mesh.?];
        // std.debug.print("{?s}", .{mesh.name});
        for (mesh.primitives) |p| {
            var x: std.json.Value = p.attributes;
            var it = x.object.iterator();
            var i: u32 = 0;
            while (it.next()) |kv| : (i += 1) {
                // const name = kv.key_ptr;
                // std.debug.print("    {} {s}\n", .{ i, name.* });
                const acc = val.accessors[@intCast(kv.value_ptr.integer)];
                const bw = val.bufferViews[acc.bufferView.?];
                const stride = if (bw.byteStride) |bs|
                    @as(i32, @intCast(bs))
                else
                    toLen(acc.type) * @sizeOf(f32);
                gl.VertexAttribPointer(
                    i,
                    toLen(acc.type),
                    @intFromEnum(acc.componentType),
                    gl.FALSE,
                    stride,
                    @intCast(acc.byteOffset + bw.byteOffset),
                );
                gl.EnableVertexAttribArray(i);
                // const offset = acc.byteOffset + bw.byteOffset;
                // const end = offset + bw.byteLength;
                // const sol: []f32 = @alignCast(@ptrCast(ds[offset .. end]));
                // std.debug.print("{s}: {any}\n", .{ kv.key_ptr.*, sol });
            }
            if (p.indices) |inds| {
                const acc = val.accessors[inds];
                const bw = val.bufferViews[acc.bufferView.?];
                std.debug.assert(gl.ELEMENT_ARRAY_BUFFER == @intFromEnum(bw.target.?));
                std.debug.assert(bw.byteOffset + acc.byteOffset == 0);
                gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, BUF);
            }
        }
        return .{ .VAO = VAO, .BUF = BUF, .gltf = gltf };
    }
    pub fn deinit(self: *const @This()) void {
        self.gltf.deinit();
    }
    pub fn draw(self: *const @This()) !void {
        const val = self.gltf.value;
        const node = val.nodes[val.scenes[val.scene orelse 0].nodes[0]];
        if (node.mesh == null) return error.NoMesh;
        const mesh: glup.glTF.Mesh = val.meshes[node.mesh.?];
        for (mesh.primitives) |p| {
            if (p.indices) |inds| {
                const acc = val.accessors[inds];
                const bw = val.bufferViews[acc.bufferView.?];
                const offset = bw.byteOffset + acc.byteOffset;
                glup.gl.DrawElements(@intFromEnum(p.mode), @intCast(acc.count), @intFromEnum(acc.componentType), offset);
            } else {
                const accInd = p.attributes.object.iterator().values[0].integer;
                const acc = val.accessors[@intCast(accInd)];
                glup.gl.DrawArrays(@intFromEnum(p.mode), 0, @intCast(acc.count));
            }
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    var app = try glup.App.init(800, 600, "Model Loading");
    const model = try Model.init("examples/cube/Cube.gltf", alloc);
    var rld = try Reloader.init();
    //
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
        try model.draw();
        // cube.draw();
    }
}
