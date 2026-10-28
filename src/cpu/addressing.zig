//! 6502 addressing modes. Each one reads its operand bytes and leaves the
//! effective address in `cpu.addr_abs` (or `cpu.addr_rel` for branches).
//! Every bus access is a CPU cycle, including the dummy reads the real chip
//! does while it works the address out.

const Cpu = @import("cpu.zig");

/// implied / accumulator, the CPU reads the next byte and throws it away
pub fn IMP(cpu: *Cpu) void {
    cpu.dummyRead(cpu.pc);
    cpu.fetched = cpu.a;
}
/// immediate
pub fn IMM(cpu: *Cpu) void {
    cpu.addr_abs = cpu.pc;
    cpu.pc +%= 1;
}
/// zero page
pub fn ZP0(cpu: *Cpu) void {
    cpu.addr_abs = cpu.fetchOperand();
}
/// zero page, x
pub fn ZPX(cpu: *Cpu) void {
    const base = cpu.fetchOperand();
    // reads the unindexed address while adding
    cpu.dummyRead(base);
    cpu.addr_abs = base +% cpu.x;
}
/// zero page, y
pub fn ZPY(cpu: *Cpu) void {
    const base = cpu.fetchOperand();
    cpu.dummyRead(base);
    cpu.addr_abs = base +% cpu.y;
}
/// absolute
pub fn ABS(cpu: *Cpu) void {
    cpu.addr_abs = cpu.fetchOperandU16();
}
/// absolute, x
pub fn ABX(cpu: *Cpu) void {
    const base = cpu.fetchOperandU16();
    cpu.addr_abs = base +% cpu.x;
    indexedDummyRead(cpu, base);
}
/// absolute, y
pub fn ABY(cpu: *Cpu) void {
    const base = cpu.fetchOperandU16();
    cpu.addr_abs = base +% cpu.y;
    indexedDummyRead(cpu, base);
}
/// indirect (JMP only)
pub fn IND(cpu: *Cpu) void {
    const ptr = cpu.fetchOperandU16();

    // 6502 bug: the pointer's high byte doesn't carry into the next page
    const lo: u16 = cpu.read(ptr);
    const hi: u16 = cpu.read((ptr & 0xff00) | ((ptr +% 1) & 0x00ff));
    cpu.addr_abs = hi << 8 | lo;
}
/// (indirect, x)
pub fn IZX(cpu: *Cpu) void {
    const ptr = cpu.fetchOperand();
    cpu.dummyRead(ptr);

    const lo: u16 = cpu.read(ptr +% cpu.x);
    const hi: u16 = cpu.read(ptr +% cpu.x +% 1);
    cpu.addr_abs = hi << 8 | lo;
}
/// (indirect), y
pub fn IZY(cpu: *Cpu) void {
    const ptr = cpu.fetchOperand();

    const lo: u16 = cpu.read(ptr);
    const hi: u16 = cpu.read(ptr +% 1);
    const base = hi << 8 | lo;

    cpu.addr_abs = base +% cpu.y;
    indexedDummyRead(cpu, base);
}
/// relative (branches)
pub fn REL(cpu: *Cpu) void {
    cpu.addr_rel = cpu.fetchOperand();

    // sign extend
    if (cpu.addr_rel & 0x80 != 0) {
        cpu.addr_rel |= 0xff00;
    }
}

/// indexed addressing reads the address before the high byte is fixed.
/// Reads only need that extra cycle when the index crossed a page, stores
/// and read-modify-write instructions always take it.
fn indexedDummyRead(cpu: *Cpu, base: u16) void {
    const page_crossed = cpu.addr_abs & 0xff00 != base & 0xff00;

    if (page_crossed or cpu.instruction().op.writesMemory()) {
        cpu.dummyRead((base & 0xff00) | (cpu.addr_abs & 0x00ff));
    }
}
