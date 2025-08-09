const std = @import("std");

const glup = @import("glup");
const gl = glup.gl;
const vec = glup.zm.vec;

const rotationSensitivity = 0.002;
const cameraSpeed = 0.05;

const Uniforms = struct {
    diffuse: glup.Texture,
    view: glup.zm.Mat4f,
    projection: glup.zm.Mat4f,
};

const Vertex = extern struct {
    normal: @Vector(3, f32),
    position: @Vector(3, f32),
    tangent: @Vector(4, f32),
    texCoord: @Vector(2, f32),
};
const Shader = glup.Shader(Uniforms, Vertex);

const Reloader = glup.FileReloader(.{
    .sh = .{ "examples/model_gltf.glsl", struct {
        pub fn init(filePath: []const u8) !Shader {
            return .initFromFile(filePath);
        }
        pub fn deinit(s: *Shader) void {
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

const Mesh = struct {
    VAOs: []u32,
    allocator: std.mem.Allocator,
    gltf: glup.glTF.Mesh,
    pub fn init(alloc: std.mem.Allocator, mesh: glup.glTF.Mesh, gltf: *const glup.glTF.GlTF, buffers: []u32) !@This() {
        const VAOs = try alloc.alloc(u32, mesh.primitives.len);
        gl.GenVertexArrays(@intCast(VAOs.len), VAOs.ptr);

        for (mesh.primitives, VAOs) |p, VAO| {
            gl.BindVertexArray(VAO);
            defer glup.gl.BindVertexArray(0);

            var it = p.attributes.object.iterator();
            var i: u32 = 0;
            while (it.next()) |kv| : (i += 1) {
                // const name = kv.key_ptr;
                const acc = gltf.accessors[@intCast(kv.value_ptr.integer)];
                const bw = gltf.bufferViews[acc.bufferView.?];
                glup.gl.BindBuffer(gl.ARRAY_BUFFER, buffers[bw.buffer]);
                const stride = gltf.stride(acc);
                const offset: usize = @intCast(acc.byteOffset + bw.byteOffset);
                const t: u32 = @intFromEnum(acc.componentType);
                gl.VertexAttribPointer(i, acc.type.len(), t, gl.FALSE, stride, offset);
                gl.EnableVertexAttribArray(i);
            }
            if (p.indices) |inds| {
                const acc = gltf.accessors[inds];
                const bw = gltf.bufferViews[acc.bufferView.?];
                // std.debug.assert(glup.gl.ELEMENT_ARRAY_BUFFER == @intFromEnum(bw.target.?)); Avocado
                glup.gl.BindBuffer(glup.gl.ELEMENT_ARRAY_BUFFER, buffers[bw.buffer]);
            }
        }
        gl.BindBuffer(gl.ARRAY_BUFFER, 0);
        glup.gl.BindBuffer(glup.gl.ELEMENT_ARRAY_BUFFER, 0);
        return .{ .VAOs = VAOs, .allocator = alloc, .gltf = mesh };
    }
    pub fn draw(self: *const @This(), gltf: *const glup.glTF.GlTF, texs: []u32) void {
        for (self.gltf.primitives, self.VAOs) |p, VAO| {
            glup.gl.BindVertexArray(VAO);
            defer glup.gl.BindVertexArray(0);

            const mat = gltf.materials[p.material.?];
            const tex = texs[mat.pbrMetallicRoughness.baseColorTexture.?.index];
            gl.BindTexture(gl.TEXTURE_2D, tex);

            const mode = @intFromEnum(p.mode);
            if (p.indices) |inds| {
                const acc = gltf.accessors[inds];
                const bw = gltf.bufferViews[acc.bufferView.?];
                const offset = bw.byteOffset + acc.byteOffset;
                const ct = @intFromEnum(acc.componentType);
                glup.gl.DrawElements(mode, @intCast(acc.count), ct, offset);
            } else {
                const accInd = p.attributes.object.iterator().values[0].integer;
                const acc = gltf.accessors[@intCast(accInd)];
                glup.gl.DrawArrays(mode, 0, @intCast(acc.count));
            }
        }
    }
    pub fn deinit(self: *const @This()) void {
        gl.DeleteVertexArrays(self.VAOs.len, self.VAOs.ptr);
        self.allocator.free(self.VAOs);
    }
};

const Model = struct {
    const DrawMode = union(enum) {
        elements: u32,
        vertices: void,
    };
    buffers: []u32,
    textures: []u32,
    gltf: glup.glTF.Parsed,
    allocator: std.mem.Allocator,
    meshes: []Mesh,
    // ToDo use arena, don't save gltf
    // ToDo all asserts to gltf module as 'check'
    pub fn init(path: []const u8, alloc: std.mem.Allocator) !@This() {
        const gltf = x: {
            const data = try std.fs.cwd().readFileAlloc(alloc, path, 10000000); // ToDo leak
            break :x try glup.glTF.parse(alloc, data);
        };
        const val = gltf.value;
        const scene = val.scenes[val.scene orelse 0]; // ToDo more than one scene

        const bufs: []u32 = try alloc.alloc(u32, val.buffers.len);
        gl.GenBuffers(@intCast(bufs.len), bufs.ptr);
        for (val.buffers, bufs) |buf, BUF| {
            const uri = try glup.Utils.getFilePath(alloc, path, buf.uri.?);
            const data = try std.fs.cwd().readFileAlloc(alloc, uri, buf.byteLength);
            defer alloc.free(data);
            gl.BindBuffer(gl.ARRAY_BUFFER, BUF);
            defer gl.BindBuffer(gl.ARRAY_BUFFER, 0);
            gl.BufferData(gl.ARRAY_BUFFER, @as(i64, @intCast(data.len)), data.ptr, gl.STATIC_DRAW);
        }

        const images = try alloc.alloc(glup.Image, val.images.len);
        defer {
            for (images) |img| img.deinit();
            alloc.free(images);
        }
        for (val.images, 0..) |img, i| {
            const uri = try glup.Utils.getFilePath(alloc, path, img.uri.?);
            images[i] = try glup.Image.init(uri);
        }

        const texs: []u32 = try alloc.alloc(u32, val.textures.len);
        gl.GenTextures(@intCast(texs.len), texs.ptr);
        for (val.textures, texs) |tex, TEX| {
            gl.BindTexture(gl.TEXTURE_2D, TEX);
            const img = images[tex.source.?];
            const sampler = if (tex.sampler) |s| val.samplers[s] else glup.glTF.Sampler{};
            const wrapS: i32 = @intCast(@intFromEnum(sampler.wrapS));
            const wrapT: i32 = @intCast(@intFromEnum(sampler.wrapT));
            const minFilter: i32 = @intCast(@intFromEnum(sampler.minFilter orelse
                .LINEAR_MIPMAP_LINEAR));
            const magFilter: i32 = @intCast(@intFromEnum(sampler.magFilter orelse
                .LINEAR));
            gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, wrapS);
            gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, wrapT);
            gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, minFilter);
            gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, magFilter);
            gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGB, @intCast(img.width), @intCast(img.height), 0, gl.RGBA, gl.UNSIGNED_BYTE, img.pixels.ptr);
            gl.GenerateMipmap(gl.TEXTURE_2D);
        }

        // for (val.materials) |mat| {
        //     // glup.glTF.Material
        //     if (mat.pbrMetallicRoughness.baseColorTexture) |t| {
        //         t.index
        //     }
        //     // mat.pbrMetallicRoughness.metallicRoughnessTexture.
        // }

        var meshes = std.ArrayList(Mesh).init(alloc);
        for (scene.nodes) |i| if (val.nodes[i].mesh) |mesh|
            try meshes.append(try Mesh.init(alloc, val.meshes[mesh], &gltf.value, bufs));
        return .{
            .buffers = bufs,
            .textures = texs,
            .gltf = gltf,
            .allocator = alloc,
            .meshes = meshes.items,
        };
    }
    pub fn deinit(self: *const @This()) void {
        self.gltf.deinit();
        gl.DeleteBuffers(self.buffers.len, self.buffers.ptr);
        gl.DeleteTextures(self.textures.len, self.textures.ptr);
        self.allocator.free(self.buffers);
        self.allocator.free(self.textures);
        self.allocator.free(self.meshes);
    }
    pub fn draw(self: *const @This()) !void {
        for (self.meshes) |m| m.draw(&self.gltf.value, self.textures);
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
    glup.Mouse.setFpsMode(app.window);
    while (app.windowOpened()) |window| {
        glup.gl.Clear(glup.gl.COLOR_BUFFER_BIT | glup.gl.DEPTH_BUFFER_BIT);
        glup.gl.ClearColor(1, 0, 0, 0);
        try rld.update();
        // _ = window;
        const mouseOffsets = glup.Mouse.getOffsets();
        camera.update(.{
            .position = vec.scale(glup.Keyboard.movement3D(window), cameraSpeed),
            .rotation = vec.scale(mouseOffsets.position, rotationSensitivity),
            .zoom = mouseOffsets.scroll[1],
        });
        rld.data.sh.use(.{
            .diffuse = rld.data.tex,
            .view = camera.view(),
            .projection = camera.projection(800, 600),
        });
        try model.draw();
    }
}
