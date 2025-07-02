const std = @import("std");
const glup = @import("glup");

fn loop() callconv(.c) void {
    glup.gl.Clear(glup.gl.COLOR_BUFFER_BIT);
    glup.gl.ClearColor(0, 1, 0, 1);
}


const Rld = glup.Reloader(.{ .loop = &loop }, glup.App.postReload);
comptime {
    _ = Rld;
}

pub fn main() !void {
    var rld = try Rld.init();
    var app = try glup.App.init(800, 640, "App");
    while (app.windowOpened()) |_| {
        try rld.reload();
        rld.reg.loop();
    }
}
