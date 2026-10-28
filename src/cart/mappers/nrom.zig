//! Mapper 000 (NROM): 16 or 32 KB of PRG ROM, 8 KB of CHR ROM or RAM, no
//! bank switching. A 16 KB PRG ROM is mirrored into both halves of $8000-$FFFF.

const Nrom = @This();

const Rom = @import("../rom.zig");

prg_mask: u16,

pub fn init(rom: *const Rom) Nrom {
    return .{ .prg_mask = if (rom.prg_banks > 1) 0x7FFF else 0x3FFF };
}

pub fn cpuRead(self: *Nrom, rom: *Rom, addr: u16) ?u8 {
    if (addr < 0x8000) return null;
    return rom.prg_rom[addr & self.prg_mask];
}

pub fn cpuWrite(_: *Nrom, _: *Rom, addr: u16, _: u8) bool {
    // ROM, writes are ignored
    return addr >= 0x8000;
}

pub fn ppuRead(_: *Nrom, rom: *Rom, addr: u16) ?u8 {
    if (addr > 0x1FFF) return null;
    return rom.chr[addr];
}

pub fn ppuWrite(_: *Nrom, rom: *Rom, addr: u16, value: u8) bool {
    if (addr > 0x1FFF) return false;
    if (rom.chrIsRam()) rom.chr[addr] = value;
    return true;
}
