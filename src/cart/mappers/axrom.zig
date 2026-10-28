//! Mapper 007 (AxROM): switchable 32 KB PRG bank, 8 KB CHR RAM, single
//! screen mirroring selected by the bank register.
//! https://www.nesdev.org/wiki/AxROM

const Axrom = @This();

const Rom = @import("../rom.zig");

/// PRG bank (bits 0-2), nametable select (bit 4)
bank: u8 = 0,

pub fn init(rom: *const Rom) Axrom {
    _ = rom;
    return .{};
}

pub fn cpuRead(self: *Axrom, rom: *Rom, addr: u16) ?u8 {
    if (addr < 0x8000) return null;
    return rom.prg32k(self.bank & 0x07, addr);
}

pub fn cpuWrite(self: *Axrom, _: *Rom, addr: u16, value: u8) bool {
    if (addr < 0x8000) return false;
    self.bank = value;
    return true;
}

pub fn ppuRead(_: *Axrom, rom: *Rom, addr: u16) ?u8 {
    if (addr > 0x1FFF) return null;
    return rom.chr[rom.chrOffset(0, 0x2000, addr)];
}

pub fn ppuWrite(_: *Axrom, rom: *Rom, addr: u16, value: u8) bool {
    if (addr > 0x1FFF) return false;
    if (rom.chr_is_ram) rom.chr[rom.chrOffset(0, 0x2000, addr)] = value;
    return true;
}

pub fn mirroring(self: *Axrom, rom: *const Rom) Rom.Mirroring {
    _ = rom;
    return if (self.bank & 0x10 != 0) .single_hi else .single_lo;
}
