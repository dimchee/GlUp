const glup = @import("glup");
const std = @import("std");

fn loop() void {
    glup.gl.ClearColor(1.0, 0.0, 0.0, 1.0);
    glup.gl.Clear(glup.gl.COLOR_BUFFER_BIT);
}

pub fn main() !void {
    try glup.run(.{
        .title = "Hello Window Example",
        .loop = loop,
    });
}

