const std = @import("std");
const glup = @import("glup");

fn loop() callconv(.c) void {
    glup.gl.Clear(glup.gl.COLOR_BUFFER_BIT);
    glup.gl.ClearColor(0, 1, 0, 1);
    // std.debug.print("time: {}\n", .{glup.glfw.getTime()});
}

pub fn main() !void {
    comptime var Reloader = glup.Reloader{};
    var new_loop = try Reloader.New(&loop).init();
    defer new_loop.deinit();
    const app = try glup.App.init(800, 640, "App");
    try app.run(.{
        .loop = new_loop,
    });
}

export fn dummy() void {
    main() catch {};
}
