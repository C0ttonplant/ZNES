//! Runs a ROM without a window and prints a hash of every frame, for
//! checking that a change didn't alter emulation output.
//!
//! usage: znes-headless <rom.nes> <frames> [trace frames] [frame:buttons,...]
//!   trace frames   print a CPU trace line per instruction for the first N frames
//!   frame:buttons  from that frame on, controller 1 holds `buttons`
//!                  (hex, bit 7 = A ... bit 0 = right, see Controller.Buttons)
//!
//! Output goes to stderr: "FRAME <n> <hash>" per frame, then "RAM <hash>".
//! Diff the output from before and after a change.

const std = @import("std");
const Nes = @import("nes.zig");
const Cartridge = @import("cart/cartridge.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 3) {
        std.debug.print("usage: {s} <rom.nes> <frames> [trace frames] [frame:buttons,...]\n", .{args[0]});
        return error.InvalidArguments;
    }
    const frames = try std.fmt.parseInt(u32, args[2], 10);
    const trace_frames = if (args.len > 3) try std.fmt.parseInt(u32, args[3], 10) else 0;
    const input_script: []const u8 = if (args.len > 4) args[4] else "";

    const nes = try gpa.create(Nes);
    defer gpa.destroy(nes);
    nes.init(try Cartridge.load(gpa, init.io, args[1]));
    defer nes.deinit(gpa);

    for (0..frames) |frame| {
        var it = std.mem.tokenizeScalar(u8, input_script, ',');
        while (it.next()) |entry| {
            const colon = std.mem.indexOfScalar(u8, entry, ':') orelse return error.InvalidArguments;
            if (try std.fmt.parseInt(u32, entry[0..colon], 10) == frame) {
                nes.bus.controllers[0].buttons = @bitCast(try std.fmt.parseInt(u8, entry[colon + 1 ..], 16));
            }
        }

        nes.cpu.debug = frame < trace_frames;
        nes.runFrame();
        if (nes.cpu.jammed) return error.CpuJammed;

        std.debug.print("FRAME {d} {x:0>16}\n", .{ frame, std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(&nes.ppu.framebuffer)) });
    }
    std.debug.print("RAM {x:0>16}\n", .{std.hash.Wyhash.hash(0, &nes.bus.ram)});
}
