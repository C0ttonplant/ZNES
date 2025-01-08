const std = @import("std");
const fs = std.fs;
const rl = @import("raylib");

const cpu_6502 = @import("cpu.zig");
const bus = @import("bus.zig");
const ppu = @import("ppu.zig");
const apu = @import("apu.zig");
const cartrige = @import("cartrige.zig");

var screenTexture: rl.Texture2D = undefined;

pub const screenWidth = 1000;
pub const screenHeight = 480;
pub var cam: rl.Camera2D = undefined;
pub var font: rl.Font = undefined;

pub fn main() !void 
{
    const flags = rl.ConfigFlags{ .window_resizable = true };
    rl.setConfigFlags(flags);
    rl.initWindow(screenWidth, screenHeight, "nes-emu");
    defer rl.closeWindow(); // Close window and OpenGL context
    rl.setTargetFPS(120);

    ppu.screenImg = rl.genImageColor(256, 240, rl.Color.black);
    apu.setSampleFrequency(44100);

    var cart = try cartrige.init("smb.nes");
    bus.instertCartrage(&cart);
    defer bus.removeCartrige();

    apu.init();
    defer apu.destroy();

    cam.offset = rl.Vector2.init(0, 0);
    cam.target = rl.Vector2.init(0, 0);
    cam.rotation = 0;
    cam.zoom = 2;

    
    cpu_6502.reset();

    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        //----------------------------------------------------------------------------------
        // TODO: Update your variables here
        //----------------------------------------------------------------------------------
        bus.controller.update();
        // Draw
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(rl.Color.dark_blue);
        rl.drawFPS(520, 15);

        cam.begin();
        defer cam.end();
        // ppu.drawFrame();

        rl.unloadTexture(screenTexture); 
        screenTexture = rl.loadTextureFromImage(ppu.screenImg);

        rl.drawTexture(screenTexture, 0, 0, rl.Color.white);
        //----------------------------------------------------------------------------------
    }

    // try dumpVirtualMemory();
}

pub fn dumpVirtualMemory() !void {
    var cwd = fs.cwd();

    var f = cwd.createFile("mem.dmp", .{}) catch {
        return;
    };
    defer f.close();
    for (0..0x10000) |i| {
        _ = try f.write(&[1]u8{cpu_6502.read(@intCast(i))});
    }
}

pub fn drawCurrentInstruction(x: i32, y: i32) !void
{
    const str: []u8 = try std.fmt.allocPrint(std.heap.page_allocator, "{s}, op {x:0<2}, pc {x:0<4}, a {x:0<2}, x {x:0<2}, y {x:0<2}\ncycles {d}\n", .{cpu_6502.LOOKUP[(cpu_6502.opCode & 0xf0) >> 4][cpu_6502.opCode & 0x0f].Name, cpu_6502.opCode, cpu_6502.ProgramCounter, cpu_6502.accumulator, cpu_6502.xReg, cpu_6502.yReg, cpu_6502.clockCount});
    var pos: rl.Vector2 = undefined;

    pos.x = @floatFromInt(x);
    pos.y = @floatFromInt(y);


    //rl.drawText(@as([:0] const u8, @ptrCast(str)), x, y, 20, rl.Color.white);
    rl.drawTextEx(font, @as([:0] const u8, @ptrCast(str)), pos, 20, 1, rl.Color.white);
    
}
