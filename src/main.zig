const std = @import("std");
const rl = @import("raylib");

const Nes = @import("nes.zig");
const Ppu = @import("ppu/ppu.zig");
const Cartridge = @import("cart/cartridge.zig");
const input = @import("frontend/input.zig");

const screen_width = 1000;
const screen_height = 480;
const default_rom = "AccuracyCoin.nes";

/// usage: ZNES [rom.nes]
pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const rom_path = if (args.len > 1) args[1] else default_rom;

    const nes = try gpa.create(Nes);
    defer gpa.destroy(nes);
    nes.init(try Cartridge.load(gpa, init.io, rom_path));
    defer nes.deinit(gpa);

    rl.setConfigFlags(.{ .window_resizable = true });
    rl.initWindow(screen_width, screen_height, "nes-emu");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    const screen = try loadScreenTexture();
    defer rl.unloadTexture(screen);

    const cam: rl.Camera2D = .{
        .offset = .init(0, 0),
        .target = .init(0, 0),
        .rotation = 0,
        .zoom = 2,
    };

    while (!rl.windowShouldClose()) {
        input.poll(&nes.bus.controllers);
        nes.runFrame();
        if (nes.cpu.jammed) {
            std.debug.print("Execution stopped by bad instruction: {x:0>2}\n", .{nes.cpu.opcode});
            return error.CpuJammed;
        }
        rl.updateTexture(screen, &nes.ppu.framebuffer);

        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(.dark_blue);
        rl.drawFPS(520, 15);

        cam.begin();
        defer cam.end();
        rl.drawTexture(screen, 0, 0, .white);
    }
}

/// texture the framebuffer gets copied into every frame
fn loadScreenTexture() !rl.Texture2D {
    const image = rl.genImageColor(Ppu.width, Ppu.height, .black);
    defer rl.unloadImage(image);
    return rl.loadTextureFromImage(image);
}
