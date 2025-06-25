const glup = @import("glup");

fn loop() void {
    glup.gl.ClearColor(1.0, 0.0, 0.0, 1.0);
    glup.gl.Clear(glup.gl.COLOR_BUFFER_BIT);
}

pub fn main() !void {
    const app = try glup.App.init(800, 600, "Hello Window Example");
    try app.run(.{
        .loop = loop,
    });
}

