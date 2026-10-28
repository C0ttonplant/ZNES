//! 6502 instructions, official and illegal. Each one runs after its
//! addressing mode has computed `cpu.addr_abs`. Every bus access is one CPU
//! cycle, so the accesses here (dummy reads included) are what make the
//! cycle counts come out right.

const Cpu = @import("cpu.zig");

/// values ORed into the accumulator by the unstable ANE and LXA opcodes,
/// they differ between chips, these are the ones test ROMs expect
const ane_magic: u8 = 0xEE;
const lxa_magic: u8 = 0xFF;

fn setZN(cpu: *Cpu, value: u8) void {
    cpu.status.Z = value == 0;
    cpu.status.N = value & 0x80 != 0;
}

/// a + value + carry -> a, SBC is this with the value inverted
/// (the 2A03 has no decimal mode)
fn addWithCarry(cpu: *Cpu, value: u8) void {
    const sum: u16 = @as(u16, cpu.a) + value + @intFromBool(cpu.status.C);
    const result: u8 = @truncate(sum);

    cpu.status.C = sum > 0xff;
    // signed overflow: both inputs have the same sign and the result doesn't
    cpu.status.V = (cpu.a ^ result) & (value ^ result) & 0x80 != 0;
    setZN(cpu, result);
    cpu.a = result;
}

fn compare(cpu: *Cpu, register: u8, value: u8) void {
    cpu.status.C = register >= value;
    setZN(cpu, register -% value);
}

/// rotate left through carry
fn rotateLeft(cpu: *Cpu, value: u8) u8 {
    const result = value << 1 | @intFromBool(cpu.status.C);
    cpu.status.C = value & 0x80 != 0;
    return result;
}

/// rotate right through carry
fn rotateRight(cpu: *Cpu, value: u8) u8 {
    const result = @as(u8, @intFromBool(cpu.status.C)) << 7 | value >> 1;
    cpu.status.C = value & 1 != 0;
    return result;
}

/// read-modify-write instructions write the unmodified value back first
fn writeBack(cpu: *Cpu, result: u8) void {
    cpu.write(cpu.addr_abs, cpu.fetched);
    cpu.write(cpu.addr_abs, result);
}

/// branch if the condition is met: one extra cycle when taken, another
/// when the target is on a different page
fn branch(cpu: *Cpu, condition: bool) void {
    if (!condition) return;

    const target = cpu.pc +% cpu.addr_rel;

    // branches poll for interrupts before cycle 2, and when they cross a
    // page again before cycle 4 (either poll counts). A taken branch that
    // doesn't cross a page doesn't poll at its end, so an interrupt that
    // arrives during it waits one more instruction.
    const first_poll = cpu.interrupt_poll;
    cpu.dummyRead(cpu.pc);

    if (target & 0xff00 != cpu.pc & 0xff00) {
        // the low byte is added first, then the high byte is fixed
        cpu.dummyRead((cpu.pc & 0xff00) | (target & 0x00ff));
        cpu.interrupt_poll = cpu.interrupt_poll or first_poll;
    } else {
        cpu.interrupt_poll = first_poll;
    }

    cpu.pc = target;
}

/// helper for the unstable SH* opcodes, stores value & (high byte + 1)
fn storeHigh(cpu: *Cpu, value: u8, index: u8) void {
    const base: u16 = cpu.addr_abs -% index;
    const result: u8 = value & @as(u8, @truncate((base >> 8) +% 1));

    // if the index crosses a page the high byte of the address is replaced with the result
    if (cpu.addr_abs & 0xff00 != base & 0xff00) {
        cpu.addr_abs = (@as(u16, result) << 8) | (cpu.addr_abs & 0x00ff);
    }

    cpu.write(cpu.addr_abs, result);
}

// official opcodes

/// logical and accumulator
pub fn AND(cpu: *Cpu) void {
    cpu.fetch();
    cpu.a &= cpu.fetched;

    cpu.status.Z = cpu.a == 0;
    cpu.status.N = cpu.a & 0x80 != 0;
}
/// add carry
pub fn ADC(cpu: *Cpu) void {
    cpu.fetch();
    addWithCarry(cpu, cpu.fetched);
}
/// logical shift left (carry <- data <- void)
pub fn ASL(cpu: *Cpu) void {
    cpu.fetch();
    const result: u8 = cpu.fetched << 1;
    cpu.status.C = cpu.fetched & 0x80 != 0;
    setZN(cpu, result);

    if (cpu.instruction().mode == .IMP) {
        cpu.a = result;
    } else {
        writeBack(cpu, result);
    }
}
/// branch if carry clear
pub fn BCC(cpu: *Cpu) void {
    branch(cpu, !cpu.status.C);
}
// branch if carry set
pub fn BCS(cpu: *Cpu) void {
    branch(cpu, cpu.status.C);
}
/// branch if equal
pub fn BEQ(cpu: *Cpu) void {
    branch(cpu, cpu.status.Z);
}
/// test bits
pub fn BIT(cpu: *Cpu) void {
    cpu.fetch();
    const result: u8 = cpu.a & cpu.fetched;
    cpu.status.Z = result == 0;
    cpu.status.N = cpu.fetched & 0x80 != 0;
    cpu.status.V = cpu.fetched & 0x40 != 0;
}
/// branch if minus
pub fn BMI(cpu: *Cpu) void {
    branch(cpu, cpu.status.N);
}
/// branch if not equal
pub fn BNE(cpu: *Cpu) void {
    branch(cpu, !cpu.status.Z);
}
/// branch if plus
pub fn BPL(cpu: *Cpu) void {
    branch(cpu, !cpu.status.N);
}
/// break
pub fn BRK(cpu: *Cpu) void {
    // the byte after BRK is skipped (read by the implied mode's dummy read)
    cpu.pc +%= 1;
    cpu.interruptSequence(true);
}
/// branch if overflow clear
pub fn BVC(cpu: *Cpu) void {
    branch(cpu, !cpu.status.V);
}
/// branch if overflow set
pub fn BVS(cpu: *Cpu) void {
    branch(cpu, cpu.status.V);
}
/// clear carry
pub fn CLC(cpu: *Cpu) void {
    cpu.status.C = false;
}
/// clear 'decimal mode' flag
pub fn CLD(cpu: *Cpu) void {
    cpu.status.D = false;
}
/// clear 'no interrupt' flag
pub fn CLI(cpu: *Cpu) void {
    cpu.status.I = false;
}
/// clear overflow flag
pub fn CLV(cpu: *Cpu) void {
    cpu.status.V = false;
}
/// compare accumulator
pub fn CMP(cpu: *Cpu) void {
    cpu.fetch();
    compare(cpu, cpu.a, cpu.fetched);
}
/// compare x
pub fn CPX(cpu: *Cpu) void {
    cpu.fetch();
    compare(cpu, cpu.x, cpu.fetched);
}
/// compare y
pub fn CPY(cpu: *Cpu) void {
    cpu.fetch();
    compare(cpu, cpu.y, cpu.fetched);
}
/// decrement memory
pub fn DEC(cpu: *Cpu) void {
    cpu.fetch();
    const result: u8 = cpu.fetched -% 1;
    writeBack(cpu, result);
    setZN(cpu, result);
}
/// decrement x
pub fn DEX(cpu: *Cpu) void {
    cpu.x -%= 1;

    cpu.status.Z = cpu.x == 0;
    cpu.status.N = cpu.x & 0x80 != 0;
}
/// decrement y
pub fn DEY(cpu: *Cpu) void {
    cpu.y -%= 1;

    cpu.status.Z = cpu.y == 0;
    cpu.status.N = cpu.y & 0x80 != 0;
}
/// bitwise xor
pub fn EOR(cpu: *Cpu) void {
    cpu.fetch();
    cpu.a ^= cpu.fetched;

    cpu.status.Z = cpu.a == 0;
    cpu.status.N = cpu.a & 0x80 != 0;
}
/// increment memory
pub fn INC(cpu: *Cpu) void {
    cpu.fetch();
    const result: u8 = cpu.fetched +% 1;

    // read-modify-write instructions write the unmodified value first
    cpu.write(cpu.addr_abs, cpu.fetched);
    cpu.write(cpu.addr_abs, result);

    cpu.status.Z = result == 0;
    cpu.status.N = result & 0x80 != 0;
}
/// increment x
pub fn INX(cpu: *Cpu) void {
    cpu.x +%= 1;

    cpu.status.Z = cpu.x == 0;
    cpu.status.N = cpu.x & 0x80 != 0;
}
/// increment y
pub fn INY(cpu: *Cpu) void {
    cpu.y +%= 1;

    cpu.status.Z = cpu.y == 0;
    cpu.status.N = cpu.y & 0x80 != 0;
}
/// jump
pub fn JMP(cpu: *Cpu) void {
    cpu.pc = cpu.addr_abs;
}
/// jump to subroutine
pub fn JSR(cpu: *Cpu) void {
    // JSR has its own order: the high byte of the target is read last,
    // after the return address is pushed
    const lo: u16 = cpu.read(cpu.pc);
    cpu.pc +%= 1;
    cpu.dummyRead(0x0100 + @as(u16, cpu.sp));
    cpu.pushU16(cpu.pc);
    const hi: u16 = cpu.read(cpu.pc);

    cpu.pc = hi << 8 | lo;
}
/// load accumulator
pub fn LDA(cpu: *Cpu) void {
    cpu.fetch();

    cpu.a = cpu.fetched;

    cpu.status.Z = cpu.a == 0;
    cpu.status.N = cpu.a & 0x80 != 0;
}
/// load x
pub fn LDX(cpu: *Cpu) void {
    cpu.fetch();

    cpu.x = cpu.fetched;

    cpu.status.Z = cpu.x == 0;
    cpu.status.N = cpu.x & 0x80 != 0;
}
/// load y
pub fn LDY(cpu: *Cpu) void {
    cpu.fetch();

    cpu.y = cpu.fetched;

    cpu.status.Z = cpu.y == 0;
    cpu.status.N = cpu.y & 0x80 != 0;
}
/// logical shift right (void -> data -> carry)
pub fn LSR(cpu: *Cpu) void {
    cpu.fetch();
    const result: u8 = cpu.fetched >> 1;
    cpu.status.C = cpu.fetched & 1 != 0;
    setZN(cpu, result);

    if (cpu.instruction().mode == .IMP) {
        cpu.a = result;
    } else {
        writeBack(cpu, result);
    }
}
/// no operation (does nothing, but still reads memory)
pub fn NOP(cpu: *Cpu) void {
    cpu.fetch();
}
/// bitwise or accumulator
pub fn ORA(cpu: *Cpu) void {
    cpu.fetch();

    cpu.a |= cpu.fetched;

    cpu.status.Z = cpu.a == 0;
    cpu.status.N = cpu.a & 0x80 != 0;
}
/// push accumulator to stack
pub fn PHA(cpu: *Cpu) void {
    cpu.push(cpu.a);
}
/// push processor status to stack
pub fn PHP(cpu: *Cpu) void {
    cpu.status.B = true;
    cpu.status.U = true;
    cpu.push(@bitCast(cpu.status));
    cpu.status.B = false;
}
/// pop accumulator from stack
pub fn PLA(cpu: *Cpu) void {
    cpu.dummyRead(0x0100 + @as(u16, cpu.sp));
    cpu.a = cpu.pull();
    cpu.status.Z = cpu.a == 0;
    cpu.status.N = cpu.a & 0x80 != 0;
}
/// pop processor status from stack
pub fn PLP(cpu: *Cpu) void {
    cpu.dummyRead(0x0100 + @as(u16, cpu.sp));
    cpu.status = @bitCast(cpu.pull());
    cpu.status.B = false;
    cpu.status.U = true;
}
/// rotate bits left (carry <- data <- carry)
pub fn ROL(cpu: *Cpu) void {
    cpu.fetch();
    const result = rotateLeft(cpu, cpu.fetched);
    setZN(cpu, result);

    if (cpu.instruction().mode == .IMP) {
        cpu.a = result;
    } else {
        writeBack(cpu, result);
    }
}
/// rotate bits right (carry -> data -> carry)
pub fn ROR(cpu: *Cpu) void {
    cpu.fetch();
    const result = rotateRight(cpu, cpu.fetched);
    setZN(cpu, result);

    if (cpu.instruction().mode == .IMP) {
        cpu.a = result;
    } else {
        writeBack(cpu, result);
    }
}
/// return from interrupt
pub fn RTI(cpu: *Cpu) void {
    cpu.dummyRead(0x0100 + @as(u16, cpu.sp));
    cpu.status = @bitCast(cpu.pull());
    cpu.status.B = false;
    cpu.status.U = true;

    cpu.pc = cpu.pullU16();
}
/// return from subroutine
pub fn RTS(cpu: *Cpu) void {
    cpu.dummyRead(0x0100 + @as(u16, cpu.sp));
    cpu.pc = cpu.pullU16();
    cpu.dummyRead(cpu.pc);
    cpu.pc +%= 1;
}
/// carry subtract
pub fn SBC(cpu: *Cpu) void {
    cpu.fetch();
    addWithCarry(cpu, ~cpu.fetched);
}
/// set carry flag
pub fn SEC(cpu: *Cpu) void {
    cpu.status.C = true;
}
/// set 'decimal mode' flag
pub fn SED(cpu: *Cpu) void {
    cpu.status.D = true;
}
/// set 'no interrupt' flag
pub fn SEI(cpu: *Cpu) void {
    cpu.status.I = true;
}
/// store accumulator
pub fn STA(cpu: *Cpu) void {
    cpu.write(cpu.addr_abs, cpu.a);
}
/// store x
pub fn STX(cpu: *Cpu) void {
    cpu.write(cpu.addr_abs, cpu.x);
}
/// store y
pub fn STY(cpu: *Cpu) void {
    cpu.write(cpu.addr_abs, cpu.y);
}
/// transfer accumulator to x
pub fn TAX(cpu: *Cpu) void {
    cpu.x = cpu.a;

    cpu.status.Z = cpu.x == 0;
    cpu.status.N = cpu.x & 0x80 != 0;
}
/// transfer accumulator to y
pub fn TAY(cpu: *Cpu) void {
    cpu.y = cpu.a;

    cpu.status.Z = cpu.y == 0;
    cpu.status.N = cpu.y & 0x80 != 0;
}
/// transfer stack pointer to x
pub fn TSX(cpu: *Cpu) void {
    cpu.x = cpu.sp;

    cpu.status.Z = cpu.x == 0;
    cpu.status.N = cpu.x & 0x80 != 0;
}
/// transfer x to accumulator
pub fn TXA(cpu: *Cpu) void {
    cpu.a = cpu.x;

    cpu.status.Z = cpu.a == 0;
    cpu.status.N = cpu.a & 0x80 != 0;
}
/// transfer x to stack pointer
pub fn TXS(cpu: *Cpu) void {
    cpu.sp = cpu.x;
}
/// transfer y to accumulator
pub fn TYA(cpu: *Cpu) void {
    cpu.a = cpu.y;

    cpu.status.Z = cpu.a == 0;
    cpu.status.N = cpu.a & 0x80 != 0;
}

// illegal opcodes, all are defined but unstable instructions may not be accurate

/// (illegal opcode), halts the cpu, the frontend reports it and exits
pub fn JAM(cpu: *Cpu) void {
    cpu.jammed = true;
}
/// (illegal opcode), logical and + LSR
pub fn ALR(cpu: *Cpu) void {
    cpu.fetch();

    const tmp: u8 = cpu.a & cpu.fetched;
    cpu.a = tmp >> 1;

    cpu.status.C = tmp & 1 == 1;
    cpu.status.Z = cpu.a == 0;
    cpu.status.N = false;
}
/// (illegal opcode), logical and + set C as bit 7
pub fn ANC(cpu: *Cpu) void {
    AND(cpu);
    cpu.status.C = cpu.a & 0x80 != 0;
}
/// (unstable opcode), (accumulator | magic) & x & value -> accumulator
pub fn ANE(cpu: *Cpu) void {
    cpu.fetch();

    cpu.a = (cpu.a | ane_magic) & cpu.x & cpu.fetched;

    cpu.status.Z = cpu.a == 0;
    cpu.status.N = cpu.a & 0x80 != 0;
}
/// (illegal opcode), logical and + ROR, C is bit 6 and V is bit 6 ^ bit 5
pub fn ARR(cpu: *Cpu) void {
    cpu.fetch();

    cpu.a = @as(u8, @intFromBool(cpu.status.C)) << 7 | (cpu.a & cpu.fetched) >> 1;

    cpu.status.C = cpu.a & 0x40 != 0;
    cpu.status.Z = cpu.a == 0;
    cpu.status.N = cpu.a & 0x80 != 0;
    cpu.status.V = (cpu.a ^ cpu.a << 1) & 0x40 != 0;
}
/// (illegal opcode), decrement memory, then compare
pub fn DCP(cpu: *Cpu) void {
    cpu.fetch();
    const result: u8 = cpu.fetched -% 1;
    writeBack(cpu, result);
    compare(cpu, cpu.a, result);
}
/// (illegal opcode), increment memory, then sub carry
pub fn ISC(cpu: *Cpu) void {
    cpu.fetch();
    const result: u8 = cpu.fetched +% 1;
    writeBack(cpu, result);
    addWithCarry(cpu, ~result);
}
/// (illegal opcode), logical and -> load accumulator, x and stack pointer
pub fn LAS(cpu: *Cpu) void {
    cpu.fetch();

    cpu.a = cpu.sp & cpu.fetched;
    cpu.x = cpu.a;
    cpu.sp = cpu.a;

    cpu.status.Z = cpu.a == 0;
    cpu.status.N = cpu.a & 0x80 != 0;
}
/// (illegal opcode), load memory onto accumulator and x
pub fn LAX(cpu: *Cpu) void {
    cpu.fetch();

    cpu.a = cpu.fetched;
    cpu.x = cpu.fetched;

    cpu.status.Z = cpu.fetched == 0;
    cpu.status.N = cpu.fetched & 0x80 == 0x80;
}
/// (unstable opcode), (accumulator | magic) & value -> accumulator and x
pub fn LXA(cpu: *Cpu) void {
    cpu.fetch();

    cpu.a = (cpu.a | lxa_magic) & cpu.fetched;
    cpu.x = cpu.a;

    cpu.status.Z = cpu.a == 0;
    cpu.status.N = cpu.a & 0x80 != 0;
}
/// (illegal opcode), ROL -> memory, then logical and -> accumulator
pub fn RLA(cpu: *Cpu) void {
    cpu.fetch();
    const result = rotateLeft(cpu, cpu.fetched);
    writeBack(cpu, result);

    cpu.a &= result;
    setZN(cpu, cpu.a);
}
/// (illegal opcode), ROR -> memory, then ADC
pub fn RRA(cpu: *Cpu) void {
    cpu.fetch();
    const result = rotateRight(cpu, cpu.fetched);
    writeBack(cpu, result);

    addWithCarry(cpu, result);
}
/// (illegal opcode), accumulator & x -> memory
pub fn SAX(cpu: *Cpu) void {
    cpu.write(cpu.addr_abs, cpu.a & cpu.x);
}
/// (illegal opcode), CMP and DEX, (accumulator & x) - value -> x
pub fn SBX(cpu: *Cpu) void {
    cpu.fetch();

    const tmp: u8 = cpu.a & cpu.x;
    cpu.x = tmp -% cpu.fetched;

    cpu.status.C = tmp >= cpu.fetched;
    cpu.status.Z = cpu.x == 0;
    cpu.status.N = cpu.x & 0x80 != 0;
}
/// (unstable opcode), accumulator & x & (high byte + 1) -> memory
pub fn SHA(cpu: *Cpu) void {
    storeHigh(cpu, cpu.a & cpu.x, cpu.y);
}
/// (unstable opcode), x & (high byte + 1) -> memory
pub fn SHX(cpu: *Cpu) void {
    storeHigh(cpu, cpu.x, cpu.y);
}
/// (unstable opcode), y & (high byte + 1) -> memory
pub fn SHY(cpu: *Cpu) void {
    storeHigh(cpu, cpu.y, cpu.x);
}
/// (illegal opcode), arithmetic shift left, then accumulator | memory -> accumulator
pub fn SLO(cpu: *Cpu) void {
    cpu.fetch();

    cpu.status.C = cpu.fetched & 0x80 == 0x80;
    const result: u8 = cpu.fetched << 1;

    // read-modify-write instructions write the unmodified value first
    cpu.write(cpu.addr_abs, cpu.fetched);
    cpu.write(cpu.addr_abs, result);

    cpu.a |= result;

    cpu.status.Z = cpu.a == 0;
    cpu.status.N = cpu.a & 0x80 == 0x80;
}
/// (illegal opcode), logical shift right, then accumulator ^ memory -> accumulator
pub fn SRE(cpu: *Cpu) void {
    cpu.fetch();

    cpu.status.C = cpu.fetched & 1 == 1;
    const result: u8 = cpu.fetched >> 1;

    // read-modify-write instructions write the unmodified value first
    cpu.write(cpu.addr_abs, cpu.fetched);
    cpu.write(cpu.addr_abs, result);

    cpu.a ^= result;

    cpu.status.Z = cpu.a == 0;
    cpu.status.N = cpu.a & 0x80 == 0x80;
}
/// (unstable opcode), accumulator & x -> stack pointer, then stack pointer & (high byte + 1) -> memory
pub fn TAS(cpu: *Cpu) void {
    cpu.sp = cpu.a & cpu.x;
    storeHigh(cpu, cpu.sp, cpu.y);
}
/// (illegal opcode), same as SBC
pub fn USB(cpu: *Cpu) void {
    SBC(cpu);
}
