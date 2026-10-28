//! 6502 addressing modes. Each one reads its operand bytes, leaves the
//! effective address in `cpu.addr_abs` (or `cpu.addr_rel` for branches) and
//! returns 1 if the instruction may take an extra cycle for crossing a page.

const Cpu = @import("cpu.zig");

/// implied / accumulator
pub fn IMP(cpu: *Cpu) u8 {
    cpu.fetched = cpu.a;
    return 0;
}
/// immediate
pub fn IMM(cpu: *Cpu) u8 {
    cpu.addr_abs = cpu.pc;
    cpu.pc +%= 1;
    return 0;
}
/// zero page
pub fn ZP0(cpu: *Cpu) u8 {
    cpu.addr_abs = cpu.read(cpu.pc);
    cpu.pc +%= 1;
    return 0;
}
/// zero page, x
pub fn ZPX(cpu: *Cpu) u8 {
    cpu.addr_abs = cpu.read(cpu.pc) +% cpu.x;
    cpu.pc +%= 1;
    return 0;
}
/// zero page, y
pub fn ZPY(cpu: *Cpu) u8 {
    cpu.addr_abs = cpu.read(cpu.pc) +% cpu.y;
    cpu.pc +%= 1;
    return 0;
}
/// absolute
pub fn ABS(cpu: *Cpu) u8 {
    cpu.addr_abs = cpu.readU16(cpu.pc);
    cpu.pc +%= 2;
    return 0;
}
/// absolute, x
pub fn ABX(cpu: *Cpu) u8 {
    const base = cpu.readU16(cpu.pc);
    cpu.pc +%= 2;

    cpu.addr_abs = base +% cpu.x;
    return indexedDummyRead(cpu, base);
}
/// absolute, y
pub fn ABY(cpu: *Cpu) u8 {
    const base = cpu.readU16(cpu.pc);
    cpu.pc +%= 2;

    cpu.addr_abs = base +% cpu.y;
    return indexedDummyRead(cpu, base);
}
/// indirect
pub fn IND(cpu: *Cpu) u8 {
    const ptr = cpu.readU16(cpu.pc);
    cpu.pc +%= 2;

    // simulate 6502 hardware bug, the pointer's high byte doesn't carry into the next page
    if (ptr & 0xff == 0xff) {
        cpu.addr_abs = (@as(u16, cpu.read(ptr & 0xff00)) << 8) | cpu.read(ptr);
        return 0;
    }

    cpu.addr_abs = cpu.readU16(ptr);
    return 0;
}
/// (indirect, x)
pub fn IZX(cpu: *Cpu) u8 {
    const t: u8 = cpu.read(cpu.pc);
    cpu.pc +%= 1;

    const lo: u16 = cpu.read((t +% cpu.x) & 0x00ff);
    const hi: u16 = cpu.read((t +% cpu.x +% 1) & 0x00ff);

    cpu.addr_abs = (hi << 8) | lo;
    return 0;
}
/// (indirect), y
pub fn IZY(cpu: *Cpu) u8 {
    const t: u8 = cpu.read(cpu.pc);
    cpu.pc +%= 1;

    const lo: u16 = cpu.read(t);
    const hi: u16 = cpu.read(t +% 1);

    cpu.addr_abs = ((hi << 8) | lo) +% cpu.y;
    return indexedDummyRead(cpu, hi << 8);
}
/// relative
pub fn REL(cpu: *Cpu) u8 {
    cpu.addr_rel = cpu.read(cpu.pc);
    cpu.pc +%= 1;

    // sign extend
    if (cpu.addr_rel & 0x80 != 0) {
        cpu.addr_rel |= 0xff00;
    }
    return 0;
}

/// indexed addressing does a dummy read before the high byte is fixed,
/// returns 1 if the index crossed a page
fn indexedDummyRead(cpu: *Cpu, base: u16) u8 {
    const page_crossed = cpu.addr_abs & 0xff00 != base & 0xff00;

    // stores and read-modify-write instructions always do this read
    if (page_crossed or cpu.instruction().op.writesMemory()) {
        _ = cpu.read((base & 0xff00) | (cpu.addr_abs & 0x00ff));
    }

    return @intFromBool(page_crossed);
}
