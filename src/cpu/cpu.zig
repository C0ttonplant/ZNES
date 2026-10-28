//! Ricoh 2A03 CPU core (a 6502 without decimal mode).
//!
//! Every bus access is one CPU cycle: `read` and `write` go through the
//! console, which runs the PPU and APU for that cycle before the access
//! happens. Instructions are written as their real sequence of accesses
//! (dummy reads included), so the cycle timing falls out of that.
//!
//! Interrupts are polled once per cycle and the poll from the second to last
//! cycle of an instruction decides whether an interrupt is taken after it,
//! same as the real chip.

const Cpu = @This();

const std = @import("std");
const Nes = @import("../nes.zig");
const opcodes = @import("opcodes.zig");
const addressing = @import("addressing.zig");
const instructions = @import("instructions.zig");

nes: *Nes,

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
/// total cycles executed
clock_count: u64 = 0,
/// set by a JAM opcode, the cpu stops executing
jammed: bool = false,

// interrupts
/// an NMI edge was seen, cleared when the NMI is taken
nmi_pending: bool = false,
/// level of the IRQ line (any source asserting it), set by `Nes` every cycle
irq_line: bool = false,
/// interrupt wanted as of the end of the last cycle
interrupt_wanted: bool = false,
/// `interrupt_wanted` one cycle earlier, what the CPU acts on after an instruction
interrupt_poll: bool = false,

// debugging
/// print a trace line for every instruction
debug: bool = false,

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

pub fn init(nes: *Nes) Cpu {
    return .{ .nes = nes };
}

/// run one instruction, then an interrupt if one was polled
pub fn step(self: *Cpu) void {
    if (self.jammed) {
        // the bus keeps reading, time keeps passing
        self.dummyRead(0xFFFF);
        return;
    }

    self.execute();

    if (self.interrupt_poll) {
        // the opcode fetch happens but is thrown away
        self.dummyRead(self.pc);
        self.dummyRead(self.pc);
        self.interruptSequence(false);
    }
}

fn execute(self: *Cpu) void {
    self.opcode = self.read(self.pc);
    const instr = self.instruction();
    if (self.debug) self.printTrace();
    self.pc +%= 1;

    // JSR reads its operand in its own order
    if (instr.op != .JSR) switch (instr.mode) {
        inline else => |mode| @field(addressing, @tagName(mode))(self),
    };
    switch (instr.op) {
        inline else => |op| @field(instructions, @tagName(op))(self),
    }
}

/// reset (also used for power on): an interrupt sequence whose pushes are
/// turned into reads, so SP drops by 3 and nothing is written.
/// Registers and memory are kept.
pub fn reset(self: *Cpu) void {
    self.jammed = false;
    self.nmi_pending = false;
    self.interrupt_wanted = false;
    self.interrupt_poll = false;

    self.dummyRead(self.pc);
    self.dummyRead(self.pc);
    for (0..3) |_| {
        self.dummyRead(0x0100 + @as(u16, self.sp));
        self.sp -%= 1;
    }
    self.status.I = true;
    self.status.U = true;
    self.pc = self.readVector(0xFFFC);
}

/// push PC and P, then jump through the NMI / IRQ / BRK vector.
/// An NMI that arrives before P is pushed takes over the vector, even
/// during BRK or an IRQ ("hijacking").
pub fn interruptSequence(self: *Cpu, brk: bool) void {
    self.pushU16(self.pc);

    const vector: u16 = if (self.nmi_pending) 0xFFFA else 0xFFFE;
    if (self.nmi_pending) self.nmi_pending = false;

    var pushed = self.status;
    pushed.B = brk;
    pushed.U = true;
    self.push(@bitCast(pushed));
    self.status.I = true;

    self.pc = self.readVector(vector);
    // the handler's first instruction always runs
    self.interrupt_poll = false;
}

/// called by `Nes` at the end of every cycle, `nmi_edge` is a new NMI
pub fn pollInterrupts(self: *Cpu, nmi_edge: bool) void {
    if (nmi_edge) self.nmi_pending = true;

    self.interrupt_poll = self.interrupt_wanted;
    self.interrupt_wanted = self.nmi_pending or (self.irq_line and !self.status.I);
}

/// the instruction table entry for the current opcode
pub fn instruction(self: *const Cpu) opcodes.Instruction {
    return opcodes.table[self.opcode];
}

/// read the operand of the current instruction into `fetched`
pub fn fetch(self: *Cpu) void {
    if (self.instruction().mode != .IMP) self.fetched = self.read(self.addr_abs);
}

/// next byte of the instruction
pub fn fetchOperand(self: *Cpu) u8 {
    const value = self.read(self.pc);
    self.pc +%= 1;
    return value;
}

/// next two bytes of the instruction, low byte first
pub fn fetchOperandU16(self: *Cpu) u16 {
    const lo: u16 = self.fetchOperand();
    const hi: u16 = self.fetchOperand();
    return hi << 8 | lo;
}

pub fn read(self: *Cpu, addr: u16) u8 {
    return self.nes.cpuRead(addr);
}

/// a read the CPU does only for timing, the value is ignored (side effects
/// like clearing $2002 flags still happen)
pub fn dummyRead(self: *Cpu, addr: u16) void {
    _ = self.read(addr);
}

pub fn write(self: *Cpu, addr: u16, value: u8) void {
    self.nes.cpuWrite(addr, value);
}

fn readVector(self: *Cpu, addr: u16) u16 {
    const lo: u16 = self.read(addr);
    const hi: u16 = self.read(addr +% 1);
    return hi << 8 | lo;
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
