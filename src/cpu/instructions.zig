//! 6502 instructions, official and illegal. Each one runs after its
//! addressing mode and returns 1 if it takes the extra page-crossing cycle
//! (the extra cycle is only added when both the mode and the op return 1).

const Cpu = @import("cpu.zig");

/// value ORed into the accumulator by the unstable ANE and LXA opcodes (differs between chips)
const unstable_magic: u8 = 0xEE;

/// helper function to get overflow
fn overflow(a: u8, b: u8, c: u8) bool {
    return (a ^ b) & (a ^ c) & 0x80 != 0;
}

/// branch if the condition is met, branches add their extra cycles directly
fn branch(cpu: *Cpu, condition: bool) u8 {
    if (!condition) return 0;

    cpu.cycles += 1;

    cpu.addr_abs = cpu.pc +% cpu.addr_rel;

    if (cpu.addr_abs & 0xff00 != cpu.pc & 0xff00) {
        cpu.cycles += 1;
    }

    cpu.pc = cpu.addr_abs;

    return 0;
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
pub fn AND(cpu: *Cpu) u8 {
    cpu.fetch();
    cpu.a &= cpu.fetched;

    cpu.status.Z = cpu.a == 0;
    cpu.status.N = cpu.a & 0x80 != 0;
    return 1;
}
/// add carry
pub fn ADC(cpu: *Cpu) u8 {
    // TODO: add decimal mode
    cpu.fetch();

    const tmp: u16 = @as(u16, cpu.a) + cpu.fetched + @intFromBool(cpu.status.C);
    const result: u8 = @truncate(tmp);

    cpu.status.C = tmp > 0xff;
    cpu.status.Z = result == 0;
    cpu.status.N = result & 0x80 != 0;
    cpu.status.V = overflow(~cpu.a, cpu.fetched, ~result);

    cpu.a = result;

    return 1;
}
/// logical shift left (carry <- data <- void)
pub fn ASL(cpu: *Cpu) u8 {
    cpu.fetch();

    const tmp: u8 = cpu.fetched << 1;

    cpu.status.C = cpu.fetched & 0x80 != 0;
    cpu.status.Z = tmp == 0;
    cpu.status.N = tmp & 0x80 != 0;

    if (cpu.instruction().mode == .IMP) {
        cpu.a = tmp;
        return 0;
    }
    // read-modify-write instructions write the unmodified value first
    cpu.write(cpu.addr_abs, cpu.fetched);
    cpu.write(cpu.addr_abs, tmp);
    return 0;
}
/// branch if carry clear
pub fn BCC(cpu: *Cpu) u8 {
    return branch(cpu, !cpu.status.C);
}
// branch if carry set
pub fn BCS(cpu: *Cpu) u8 {
    return branch(cpu, cpu.status.C);
}
/// branch if equal
pub fn BEQ(cpu: *Cpu) u8 {
    return branch(cpu, cpu.status.Z);
}
/// test bits
pub fn BIT(cpu: *Cpu) u8 {
    cpu.fetch();
    const result: u8 = cpu.a & cpu.fetched;
    cpu.status.Z = result == 0;
    cpu.status.N = cpu.fetched & 0x80 != 0;
    cpu.status.V = cpu.fetched & 0x40 != 0;
    return 0;
}
/// branch if minus
pub fn BMI(cpu: *Cpu) u8 {
    return branch(cpu, cpu.status.N);
}
/// branch if not equal
pub fn BNE(cpu: *Cpu) u8 {
    return branch(cpu, !cpu.status.Z);
}
/// branch if plus
pub fn BPL(cpu: *Cpu) u8 {
    return branch(cpu, !cpu.status.N);
}
/// break
pub fn BRK(cpu: *Cpu) u8 {
    cpu.pc +%= 1;
    cpu.pushU16(cpu.pc);

    cpu.status.B = true;
    cpu.push(@bitCast(cpu.status));
    cpu.status.I = true;
    cpu.status.B = false;

    cpu.pc = cpu.readU16(0xFFFE);

    return 0;
}
/// branch if overflow clear
pub fn BVC(cpu: *Cpu) u8 {
    return branch(cpu, !cpu.status.V);
}
/// branch if overflow set
pub fn BVS(cpu: *Cpu) u8 {
    return branch(cpu, cpu.status.V);
}
/// clear carry
pub fn CLC(cpu: *Cpu) u8 {
    cpu.status.C = false;
    return 0;
}
/// clear 'decimal mode' flag
pub fn CLD(cpu: *Cpu) u8 {
    cpu.status.D = false;
    return 0;
}
/// clear 'no interrupt' flag
pub fn CLI(cpu: *Cpu) u8 {
    cpu.status.I = false;
    return 0;
}
/// clear overflow flag
pub fn CLV(cpu: *Cpu) u8 {
    cpu.status.V = false;
    return 0;
}
/// compare accumulator
pub fn CMP(cpu: *Cpu) u8 {
    cpu.fetch();
    const result: u8 = cpu.a -% cpu.fetched;

    cpu.status.C = cpu.a >= cpu.fetched;
    cpu.status.Z = result == 0;
    cpu.status.N = result & 0x80 != 0;

    return 1;
}
/// compare x
pub fn CPX(cpu: *Cpu) u8 {
    cpu.fetch();
    const result: u8 = cpu.x -% cpu.fetched;

    cpu.status.C = cpu.x >= cpu.fetched;
    cpu.status.Z = result == 0;
    cpu.status.N = result & 0x80 != 0;
    return 0;
}
/// compare y
pub fn CPY(cpu: *Cpu) u8 {
    cpu.fetch();
    const result: u8 = cpu.y -% cpu.fetched;

    cpu.status.C = cpu.y >= cpu.fetched;
    cpu.status.Z = result == 0;
    cpu.status.N = result & 0x80 != 0;
    return 0;
}
/// decrement memory
pub fn DEC(cpu: *Cpu) u8 {
    cpu.fetch();

    const result: u8 = cpu.fetched -% 1;
    // read-modify-write instructions write the unmodified value first
    cpu.write(cpu.addr_abs, cpu.fetched);
    cpu.write(cpu.addr_abs, result);

    cpu.status.Z = result == 0;
    cpu.status.N = result & 0x80 != 0;
    return 0;
}
/// decrement x
pub fn DEX(cpu: *Cpu) u8 {
    cpu.x -%= 1;

    cpu.status.Z = cpu.x == 0;
    cpu.status.N = cpu.x & 0x80 != 0;
    return 0;
}
/// decrement y
pub fn DEY(cpu: *Cpu) u8 {
    cpu.y -%= 1;

    cpu.status.Z = cpu.y == 0;
    cpu.status.N = cpu.y & 0x80 != 0;
    return 0;
}
/// bitwise xor
pub fn EOR(cpu: *Cpu) u8 {
    cpu.fetch();
    cpu.a ^= cpu.fetched;

    cpu.status.Z = cpu.a == 0;
    cpu.status.N = cpu.a & 0x80 != 0;
    return 1;
}
/// increment memory
pub fn INC(cpu: *Cpu) u8 {
    cpu.fetch();
    const result: u8 = cpu.fetched +% 1;

    // read-modify-write instructions write the unmodified value first
    cpu.write(cpu.addr_abs, cpu.fetched);
    cpu.write(cpu.addr_abs, result);

    cpu.status.Z = result == 0;
    cpu.status.N = result & 0x80 != 0;
    return 0;
}
/// increment x
pub fn INX(cpu: *Cpu) u8 {
    cpu.x +%= 1;

    cpu.status.Z = cpu.x == 0;
    cpu.status.N = cpu.x & 0x80 != 0;
    return 0;
}
/// increment y
pub fn INY(cpu: *Cpu) u8 {
    cpu.y +%= 1;

    cpu.status.Z = cpu.y == 0;
    cpu.status.N = cpu.y & 0x80 != 0;
    return 0;
}
/// jump
pub fn JMP(cpu: *Cpu) u8 {
    cpu.pc = cpu.addr_abs;
    return 0;
}
/// jump to subroutine
pub fn JSR(cpu: *Cpu) u8 {
    cpu.pc -%= 1;
    cpu.pushU16(cpu.pc);

    cpu.pc = cpu.addr_abs;
    return 0;
}
/// load accumulator
pub fn LDA(cpu: *Cpu) u8 {
    cpu.fetch();

    cpu.a = cpu.fetched;

    cpu.status.Z = cpu.a == 0;
    cpu.status.N = cpu.a & 0x80 != 0;
    return 1;
}
/// load x
pub fn LDX(cpu: *Cpu) u8 {
    cpu.fetch();

    cpu.x = cpu.fetched;

    cpu.status.Z = cpu.x == 0;
    cpu.status.N = cpu.x & 0x80 != 0;
    return 1;
}
/// load y
pub fn LDY(cpu: *Cpu) u8 {
    cpu.fetch();

    cpu.y = cpu.fetched;

    cpu.status.Z = cpu.y == 0;
    cpu.status.N = cpu.y & 0x80 != 0;
    return 1;
}
/// logical shift right (void -> data -> carry)
pub fn LSR(cpu: *Cpu) u8 {
    cpu.fetch();
    const tmp: u8 = cpu.fetched >> 1;

    cpu.status.C = cpu.fetched & 1 == 1;
    cpu.status.Z = tmp == 0;
    cpu.status.N = false;

    if (cpu.instruction().mode == .IMP) {
        cpu.a = tmp;
        return 0;
    }
    // read-modify-write instructions write the unmodified value first
    cpu.write(cpu.addr_abs, cpu.fetched);
    cpu.write(cpu.addr_abs, tmp);
    return 0;
}
/// no operation (does nothing, but still reads memory)
pub fn NOP(cpu: *Cpu) u8 {
    cpu.fetch();

    switch (cpu.opcode) {
        0x1C, 0x3C, 0x5C, 0x7C, 0xDC, 0xFC => return 1,
        else => return 0,
    }
}
/// bitwise or accumulator
pub fn ORA(cpu: *Cpu) u8 {
    cpu.fetch();

    cpu.a |= cpu.fetched;

    cpu.status.Z = cpu.a == 0;
    cpu.status.N = cpu.a & 0x80 != 0;
    return 1;
}
/// push accumulator to stack
pub fn PHA(cpu: *Cpu) u8 {
    cpu.push(cpu.a);
    return 0;
}
/// push processor status to stack
pub fn PHP(cpu: *Cpu) u8 {
    cpu.status.B = true;
    cpu.status.U = true;
    cpu.push(@bitCast(cpu.status));
    cpu.status.B = false;
    return 0;
}
/// pop accumulator from stack
pub fn PLA(cpu: *Cpu) u8 {
    cpu.a = cpu.pull();
    cpu.status.Z = cpu.a == 0;
    cpu.status.N = cpu.a & 0x80 != 0;
    return 0;
}
/// pop processor status from stack
pub fn PLP(cpu: *Cpu) u8 {
    cpu.status = @bitCast(cpu.pull());
    cpu.status.B = false;
    cpu.status.U = true;

    return 0;
}
/// rotate bits left (carry <- data <- carry)
pub fn ROL(cpu: *Cpu) u8 {
    cpu.fetch();

    const tmp: u8 = cpu.fetched << 1 | @intFromBool(cpu.status.C);

    cpu.status.C = cpu.fetched & 0x80 != 0;
    cpu.status.Z = tmp == 0;
    cpu.status.N = tmp & 0x80 != 0;

    if (cpu.instruction().mode == .IMP) {
        cpu.a = tmp;
        return 0;
    }
    // read-modify-write instructions write the unmodified value first
    cpu.write(cpu.addr_abs, cpu.fetched);
    cpu.write(cpu.addr_abs, tmp);
    return 0;
}
/// rotate bits right (carry -> data -> carry)
pub fn ROR(cpu: *Cpu) u8 {
    cpu.fetch();

    const tmp: u8 = @as(u8, @intFromBool(cpu.status.C)) << 7 | cpu.fetched >> 1;

    cpu.status.C = cpu.fetched & 1 == 1;
    cpu.status.Z = tmp == 0;
    cpu.status.N = tmp & 0x80 != 0;

    if (cpu.instruction().mode == .IMP) {
        cpu.a = tmp;
        return 0;
    }
    // read-modify-write instructions write the unmodified value first
    cpu.write(cpu.addr_abs, cpu.fetched);
    cpu.write(cpu.addr_abs, tmp);
    return 0;
}
/// return from interrupt
pub fn RTI(cpu: *Cpu) u8 {
    cpu.status = @bitCast(cpu.pull());
    cpu.status.B = false;
    cpu.status.U = true;

    cpu.pc = cpu.pullU16();
    return 0;
}
/// return from subroutine
pub fn RTS(cpu: *Cpu) u8 {
    cpu.pc = cpu.pullU16();
    cpu.pc +%= 1;
    return 0;
}
/// carry subtract
pub fn SBC(cpu: *Cpu) u8 {
    // TODO: add decimal mode
    cpu.fetch();

    const tmp: u16 = @as(u16, cpu.a) + ~cpu.fetched + @intFromBool(cpu.status.C);
    const result: u8 = @truncate(tmp);

    cpu.status.C = tmp > 0xff;
    cpu.status.Z = result == 0;
    cpu.status.N = result & 0x80 != 0;
    cpu.status.V = overflow(result, ~cpu.fetched, cpu.a);

    cpu.a = result;

    return 1;
}
/// set carry flag
pub fn SEC(cpu: *Cpu) u8 {
    cpu.status.C = true;
    return 0;
}
/// set 'decimal mode' flag
pub fn SED(cpu: *Cpu) u8 {
    cpu.status.D = true;
    return 0;
}
/// set 'no interrupt' flag
pub fn SEI(cpu: *Cpu) u8 {
    cpu.status.I = true;
    return 0;
}
/// store accumulator
pub fn STA(cpu: *Cpu) u8 {
    cpu.write(cpu.addr_abs, cpu.a);
    return 0;
}
/// store x
pub fn STX(cpu: *Cpu) u8 {
    cpu.write(cpu.addr_abs, cpu.x);
    return 0;
}
/// store y
pub fn STY(cpu: *Cpu) u8 {
    cpu.write(cpu.addr_abs, cpu.y);
    return 0;
}
/// transfer accumulator to x
pub fn TAX(cpu: *Cpu) u8 {
    cpu.x = cpu.a;

    cpu.status.Z = cpu.x == 0;
    cpu.status.N = cpu.x & 0x80 != 0;
    return 0;
}
/// transfer accumulator to y
pub fn TAY(cpu: *Cpu) u8 {
    cpu.y = cpu.a;

    cpu.status.Z = cpu.y == 0;
    cpu.status.N = cpu.y & 0x80 != 0;
    return 0;
}
/// transfer stack pointer to x
pub fn TSX(cpu: *Cpu) u8 {
    cpu.x = cpu.sp;

    cpu.status.Z = cpu.x == 0;
    cpu.status.N = cpu.x & 0x80 != 0;
    return 0;
}
/// transfer x to accumulator
pub fn TXA(cpu: *Cpu) u8 {
    cpu.a = cpu.x;

    cpu.status.Z = cpu.a == 0;
    cpu.status.N = cpu.a & 0x80 != 0;
    return 0;
}
/// transfer x to stack pointer
pub fn TXS(cpu: *Cpu) u8 {
    cpu.sp = cpu.x;
    return 0;
}
/// transfer y to accumulator
pub fn TYA(cpu: *Cpu) u8 {
    cpu.a = cpu.y;

    cpu.status.Z = cpu.a == 0;
    cpu.status.N = cpu.a & 0x80 != 0;
    return 0;
}

// illegal opcodes, all are defined but unstable instructions may not be accurate

/// (illegal opcode), halts the cpu, the frontend reports it and exits
pub fn JAM(cpu: *Cpu) u8 {
    cpu.jammed = true;
    return 0;
}
/// (illegal opcode), logical and + LSR
pub fn ALR(cpu: *Cpu) u8 {
    cpu.fetch();

    const tmp: u8 = cpu.a & cpu.fetched;
    cpu.a = tmp >> 1;

    cpu.status.C = tmp & 1 == 1;
    cpu.status.Z = cpu.a == 0;
    cpu.status.N = false;
    return 0;
}
/// (illegal opcode), logical and + set C as bit 7
pub fn ANC(cpu: *Cpu) u8 {
    const additionalCycle: u8 = AND(cpu);
    cpu.status.C = cpu.a & 0x80 != 0;
    return additionalCycle;
}
/// (unstable opcode), (accumulator | magic) & x & value -> accumulator
pub fn ANE(cpu: *Cpu) u8 {
    cpu.fetch();

    cpu.a = (cpu.a | unstable_magic) & cpu.x & cpu.fetched;

    cpu.status.Z = cpu.a == 0;
    cpu.status.N = cpu.a & 0x80 != 0;
    return 0;
}
/// (illegal opcode), logical and + ROR, C is bit 6 and V is bit 6 ^ bit 5
pub fn ARR(cpu: *Cpu) u8 {
    cpu.fetch();

    cpu.a = @as(u8, @intFromBool(cpu.status.C)) << 7 | (cpu.a & cpu.fetched) >> 1;

    cpu.status.C = cpu.a & 0x40 != 0;
    cpu.status.Z = cpu.a == 0;
    cpu.status.N = cpu.a & 0x80 != 0;
    cpu.status.V = (cpu.a ^ cpu.a << 1) & 0x40 != 0;
    return 0;
}
/// (illegal opcode), decrement memory, then compare
pub fn DCP(cpu: *Cpu) u8 {
    return DEC(cpu) & CMP(cpu);
}
/// (illegal opcode), increment memory, then sub carry
pub fn ISC(cpu: *Cpu) u8 {
    cpu.fetch();

    const inc: u8 = cpu.fetched +% 1;
    // read-modify-write instructions write the unmodified value first
    cpu.write(cpu.addr_abs, cpu.fetched);
    cpu.write(cpu.addr_abs, inc);

    const val: u16 = @as(u16, inc) ^ 0x00ff;

    const tmp: u16 = @as(u16, cpu.a) + val + @as(u16, @intFromBool(cpu.status.C));
    const result: u8 = @truncate(tmp);

    cpu.status.C = tmp & 0xff00 != 0;
    cpu.status.Z = result == 0;
    cpu.status.N = result & 0x80 != 0;
    cpu.status.V = ((tmp ^ cpu.a) & (tmp ^ (val)) & 0x80) != 0;

    cpu.a = result;

    return 0;
}
/// (illegal opcode), logical and -> load accumulator, x and stack pointer
pub fn LAS(cpu: *Cpu) u8 {
    cpu.fetch();

    cpu.a = cpu.sp & cpu.fetched;
    cpu.x = cpu.a;
    cpu.sp = cpu.a;

    cpu.status.Z = cpu.a == 0;
    cpu.status.N = cpu.a & 0x80 != 0;

    return 1;
}
/// (illegal opcode), load memory onto accumulator and x
pub fn LAX(cpu: *Cpu) u8 {
    cpu.fetch();

    cpu.a = cpu.fetched;
    cpu.x = cpu.fetched;

    cpu.status.Z = cpu.fetched == 0;
    cpu.status.N = cpu.fetched & 0x80 == 0x80;
    return 1;
}
/// (unstable opcode), (accumulator | magic) & value -> accumulator and x
pub fn LXA(cpu: *Cpu) u8 {
    cpu.fetch();

    cpu.a = (cpu.a | unstable_magic) & cpu.fetched;
    cpu.x = cpu.a;

    cpu.status.Z = cpu.a == 0;
    cpu.status.N = cpu.a & 0x80 != 0;
    return 0;
}
/// (illegal opcode), ROL -> memory, then logical and -> accumulator
pub fn RLA(cpu: *Cpu) u8 {
    return ROL(cpu) & AND(cpu);
}
/// (illegal opcode), ROR, then ADC
pub fn RRA(cpu: *Cpu) u8 {
    return ROR(cpu) & ADC(cpu);
}
/// (illegal opcode), accumulator & x -> memory
pub fn SAX(cpu: *Cpu) u8 {
    cpu.write(cpu.addr_abs, cpu.a & cpu.x);
    return 0;
}
/// (illegal opcode), CMP and DEX, (accumulator & x) - value -> x
pub fn SBX(cpu: *Cpu) u8 {
    cpu.fetch();

    const tmp: u8 = cpu.a & cpu.x;
    cpu.x = tmp -% cpu.fetched;

    cpu.status.C = tmp >= cpu.fetched;
    cpu.status.Z = cpu.x == 0;
    cpu.status.N = cpu.x & 0x80 != 0;
    return 0;
}
/// (unstable opcode), accumulator & x & (high byte + 1) -> memory
pub fn SHA(cpu: *Cpu) u8 {
    storeHigh(cpu, cpu.a & cpu.x, cpu.y);
    return 0;
}
/// (unstable opcode), x & (high byte + 1) -> memory
pub fn SHX(cpu: *Cpu) u8 {
    storeHigh(cpu, cpu.x, cpu.y);
    return 0;
}
/// (unstable opcode), y & (high byte + 1) -> memory
pub fn SHY(cpu: *Cpu) u8 {
    storeHigh(cpu, cpu.y, cpu.x);
    return 0;
}
/// (illegal opcode), arithmetic shift left, then accumulator | memory -> accumulator
pub fn SLO(cpu: *Cpu) u8 {
    cpu.fetch();

    cpu.status.C = cpu.fetched & 0x80 == 0x80;
    const result: u8 = cpu.fetched << 1;

    // read-modify-write instructions write the unmodified value first
    cpu.write(cpu.addr_abs, cpu.fetched);
    cpu.write(cpu.addr_abs, result);

    cpu.a |= result;

    cpu.status.Z = cpu.a == 0;
    cpu.status.N = cpu.a & 0x80 == 0x80;

    return 0;
}
/// (illegal opcode), logical shift right, then accumulator ^ memory -> accumulator
pub fn SRE(cpu: *Cpu) u8 {
    cpu.fetch();

    cpu.status.C = cpu.fetched & 1 == 1;
    const result: u8 = cpu.fetched >> 1;

    // read-modify-write instructions write the unmodified value first
    cpu.write(cpu.addr_abs, cpu.fetched);
    cpu.write(cpu.addr_abs, result);

    cpu.a ^= result;

    cpu.status.Z = cpu.a == 0;
    cpu.status.N = cpu.a & 0x80 == 0x80;

    return 0;
}
/// (unstable opcode), accumulator & x -> stack pointer, then stack pointer & (high byte + 1) -> memory
pub fn TAS(cpu: *Cpu) u8 {
    cpu.sp = cpu.a & cpu.x;
    storeHigh(cpu, cpu.sp, cpu.y);
    return 0;
}
/// (illegal opcode), same as SBC
pub fn USB(cpu: *Cpu) u8 {
    return SBC(cpu);
}
