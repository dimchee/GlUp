const glup = @import("glup");

pub fn main() !void {
    var app = try glup.App.init(800, 600, "Hello Window Example");
    while (app.windowOpened()) |_| {
        glup.gl.ClearColor(1.0, 0.0, 0.0, 1.0);
        glup.gl.Clear(glup.gl.COLOR_BUFFER_BIT);
    }
}
