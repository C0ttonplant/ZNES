//! Debugging helpers.

const std = @import("std");
const rl = @import("raylib");
const Nes = @import("../nes.zig");

/// write the CPU's view of the whole address space to a file
/// (this reads through the bus, so register reads have side effects)
pub fn dumpMemory(io: std.Io, nes: *Nes, path: []const u8) !void {
    var mem: [0x10000]u8 = undefined;
    for (&mem, 0..) |*byte, addr| byte.* = nes.bus.read(@intCast(addr));

    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = &mem });
}

/// draw the current instruction and registers
pub fn drawCpuState(nes: *const Nes, x: i32, y: i32) void {
    const cpu = &nes.cpu;
    const instr = cpu.instruction();

    var buf: [128]u8 = undefined;
    const text = std.fmt.bufPrintSentinel(&buf, "{s} {s}, op {x:0>2}, pc {x:0>4}, a {x:0>2}, x {x:0>2}, y {x:0>2}\ncycles {d}", .{
        @tagName(instr.op),
        @tagName(instr.mode),
        cpu.opcode,
        cpu.pc,
        cpu.a,
        cpu.x,
        cpu.y,
        cpu.clock_count,
    }, 0) catch return;

    rl.drawText(text, x, y, 20, .white);
}
