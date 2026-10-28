//! Ricoh 2A03 CPU core (a 6502 without decimal mode).
//!
//! Every instruction executes in full on its first cycle, the remaining
//! cycles are then spent idling so the overall timing lines up.

const Cpu = @This();

const std = @import("std");
const Bus = @import("../bus.zig");
const opcodes = @import("opcodes.zig");
const addressing = @import("addressing.zig");
const instructions = @import("instructions.zig");

bus: *Bus,

// registers
a: u8 = 0,
x: u8 = 0,
y: u8 = 0,
sp: u8 = 0,
pc: u16 = 0,
status: Status = .{},

// helper state
/// current working address
addr_abs: u16 = 0,
/// branch offset
addr_rel: u16 = 0,
/// current executing opcode
opcode: u8 = 0,
/// last fetched data
fetched: u8 = 0,
/// cycles remaining for the current instruction
cycles: u8 = 0,
/// total cycles executed
clock_count: u64 = 0,
/// set by a JAM opcode, the cpu stops executing
jammed: bool = false,

// debugging
/// print a trace line for every instruction
debug: bool = false,
/// make `clock` return false when a BRK executes
exit_on_break: bool = false,

pub const Status = packed struct(u8) {
    /// carry
    C: bool = false,
    /// zero
    Z: bool = false,
    /// disable interrupts
    I: bool = false,
    /// decimal mode (no effect on the 2A03)
    D: bool = false,
    /// break
    B: bool = false,
    /// unused
    U: bool = false,
    /// signed overflow
    V: bool = false,
    /// negative
    N: bool = false,
};

pub fn init(bus: *Bus) Cpu {
    return .{ .bus = bus };
}

/// iterate the cpu for one cycle
pub fn clock(self: *Cpu) bool {
    if (self.jammed) return true;

    if (self.cycles == 0) {
        self.opcode = self.read(self.pc);
        const instr = self.instruction();

        if (self.debug) self.printTrace();

        self.pc +%= 1;
        self.cycles = instr.cycles;

        const extra_cycle_mode: u8 = switch (instr.mode) {
            inline else => |mode| @field(addressing, @tagName(mode))(self),
        };
        const extra_cycle_op: u8 = switch (instr.op) {
            inline else => |op| @field(instructions, @tagName(op))(self),
        };

        if (self.exit_on_break and instr.op == .BRK) {
            return false;
        }
        self.cycles += extra_cycle_mode & extra_cycle_op;
    }

    self.clock_count += 1;
    self.cycles -= 1;
    return true;
}

/// reset cpu (does not clear memory)
pub fn reset(self: *Cpu) void {
    self.pc = self.readU16(0xFFFC);

    self.a = 0;
    self.x = 0;
    self.y = 0;
    self.sp = 0xFF;
    self.status = .{ .U = true };

    self.addr_abs = 0;
    self.addr_rel = 0;
    self.fetched = 0;

    self.cycles = 8;
}

/// interrupt request
pub fn irq(self: *Cpu) void {
    if (self.status.I) return;
    self.interrupt(0xFFFE);
}

/// non maskable interrupt
pub fn nmi(self: *Cpu) void {
    self.interrupt(0xFFFA);
}

fn interrupt(self: *Cpu, vector: u16) void {
    self.pushU16(self.pc);

    self.status.B = false;
    self.status.U = true;
    self.push(@bitCast(self.status));
    self.status.I = true;

    self.pc = self.readU16(vector);
    self.cycles = 7;
}

/// the instruction table entry for the current opcode
pub fn instruction(self: *const Cpu) opcodes.Instruction {
    return opcodes.table[self.opcode];
}

/// read the operand of the current instruction into `fetched`
pub fn fetch(self: *Cpu) void {
    if (self.instruction().mode != .IMP) self.fetched = self.read(self.addr_abs);
}

pub fn read(self: *Cpu, addr: u16) u8 {
    return self.bus.read(addr);
}

pub fn readU16(self: *Cpu, addr: u16) u16 {
    const hi: u16 = self.read(addr +% 1);
    return hi << 8 | self.read(addr);
}

pub fn write(self: *Cpu, addr: u16, value: u8) void {
    self.bus.write(addr, value);
}

pub fn push(self: *Cpu, value: u8) void {
    self.write(0x0100 + @as(u16, self.sp), value);
    self.sp -%= 1;
}

pub fn pushU16(self: *Cpu, value: u16) void {
    self.push(@truncate(value >> 8));
    self.push(@truncate(value));
}

pub fn pull(self: *Cpu) u8 {
    self.sp +%= 1;
    return self.read(0x0100 + @as(u16, self.sp));
}

pub fn pullU16(self: *Cpu) u16 {
    const lo: u16 = self.pull();
    const hi: u16 = self.pull();
    return hi << 8 | lo;
}

fn printTrace(self: *const Cpu) void {
    const instr = self.instruction();
    std.debug.print("{s}, {s}, op {x:0>2}, pc {x:0>4}, a {x:0>2}, x {x:0>2}, y {x:0>2}, SP {x:0>2}, NVUBDIZC {b:0>8}, cycles {d}\n", .{
        @tagName(instr.op),
        @tagName(instr.mode),
        self.opcode,
        self.pc,
        self.a,
        self.x,
        self.y,
        self.sp,
        @as(u8, @bitCast(self.status)),
        self.clock_count,
    });
}
