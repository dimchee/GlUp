const std = @import("std");
const glup = @import("glup");

fn loop() callconv(.c) void {
    glup.gl.Clear(glup.gl.COLOR_BUFFER_BIT);
    glup.gl.ClearColor(0, 0, 1, 1);
}

const Rld = glup.Reloader(.{ .loop = loop });
comptime {
    _ = Rld;
}

pub fn main() !void {
    const rld = try Rld.init();
    const app = try glup.App.init(800, 640, "App");
    try app.run(glup.Utils.merge(rld.reg, .{ .reloader = rld }));
}
