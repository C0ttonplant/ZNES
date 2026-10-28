//! Runs a ROM without a window and prints a hash of every frame, for
//! checking that a change didn't alter emulation output.
//!
//! usage: znes-headless <rom.nes> <frames> [trace frames] [frame:buttons,...] [screenshot.ppm]
//!   trace frames   print a CPU trace line per instruction for the first N frames
//!   frame:buttons  from that frame on, controller 1 holds `buttons`
//!                  (hex, bit 7 = A ... bit 0 = right, see Controller.Buttons),
//!                  pass "-" for no input
//!   screenshot     write the last frame to a PPM image
//!
//! Output goes to stderr: "FRAME <n> <hash>" per frame, then "RAM <hash>"
//! and "AUDIO rms <x> peak <y>" over all generated samples.
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
    const input_script: []const u8 = if (args.len > 4 and !std.mem.eql(u8, args[4], "-")) args[4] else "";
    const screenshot_path: ?[]const u8 = if (args.len > 5) args[5] else null;

    const nes = try gpa.create(Nes);
    defer gpa.destroy(nes);
    nes.init(try Cartridge.load(gpa, init.io, args[1]));
    defer nes.deinit(gpa);

    var audio_sum: f64 = 0;
    var audio_peak: f32 = 0;
    var audio_count: usize = 0;
    var samples: [4096]f32 = undefined;

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

        const n = nes.apu.takeSamples(&samples);
        for (samples[0..n]) |sample| {
            audio_sum += sample * sample;
            audio_peak = @max(audio_peak, @abs(sample));
        }
        audio_count += n;

        std.debug.print("FRAME {d} {x:0>16}\n", .{ frame, std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(&nes.ppu.framebuffer)) });
    }
    std.debug.print("RAM {x:0>16}\n", .{std.hash.Wyhash.hash(0, &nes.bus.ram)});
    const rms = if (audio_count > 0) @sqrt(audio_sum / @as(f64, @floatFromInt(audio_count))) else 0;
    std.debug.print("AUDIO samples {d} rms {d:.4} peak {d:.4}\n", .{ audio_count, rms, audio_peak });

    printBlarggResult(nes);
    if (screenshot_path) |path| try writeScreenshot(init.io, gpa, nes, path);
}

/// blargg's test ROMs report through PRG RAM: $6000 status (0x80 = running,
/// 0 = passed, else failed), $6001-$6003 = DE B0 61, $6004 = text
fn printBlarggResult(nes: *const Nes) void {
    const ram = nes.cart.rom.prg_ram;
    if (ram.len < 5 or !std.mem.eql(u8, ram[1..4], &.{ 0xDE, 0xB0, 0x61 })) return;

    const text = ram[4..];
    const end = std.mem.indexOfScalar(u8, text, 0) orelse text.len;
    std.debug.print("BLARGG status {x:0>2}\n{s}\n", .{ ram[0], text[0..end] });
}

fn writeScreenshot(io: std.Io, gpa: std.mem.Allocator, nes: *const Nes, path: []const u8) !void {
    const Ppu = @import("ppu/ppu.zig");
    const header = std.fmt.comptimePrint("P6\n{d} {d}\n255\n", .{ Ppu.width, Ppu.height });

    const data = try gpa.alloc(u8, header.len + Ppu.width * Ppu.height * 3);
    defer gpa.free(data);
    @memcpy(data[0..header.len], header);
    for (nes.ppu.framebuffer, 0..) |color, i| {
        data[header.len + i * 3 ..][0..3].* = .{ color.r, color.g, color.b };
    }

    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = data });
}
