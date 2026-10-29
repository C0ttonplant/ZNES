const std = @import("std");
const rl = @import("raylib");

const App = @import("frontend/app.zig");
const Ppu = @import("ppu/ppu.zig");
const MenuBar = @import("frontend/menu_bar.zig");

/// usage: ZNES [rom.nes]
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    rl.setConfigFlags(.{ .window_resizable = true, .vsync_hint = true });
    rl.initWindow(Ppu.width * 3, Ppu.height * 3 + MenuBar.height, "ZNES");
    defer rl.closeWindow();
    rl.setWindowMinSize(Ppu.width, Ppu.height + MenuBar.height);
    // Escape closes menus and dialogs, not the emulator
    rl.setExitKey(.null);
    rl.setTargetFPS(60);

    var app = try App.init(init.gpa, init.io, init.environ_map);
    defer app.deinit();
    if (args.len > 1) app.loadRom(args[1]);

    while (!rl.windowShouldClose() and !app.quit) app.frame();
}
