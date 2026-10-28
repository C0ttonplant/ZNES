//! Mapper 002 (UxROM): switchable 16 KB PRG bank at $8000, last bank fixed
//! at $C000, 8 KB CHR (usually RAM).
//! https://www.nesdev.org/wiki/UxROM

const Uxrom = @This();

const Rom = @import("../rom.zig");

prg_bank: u8 = 0,

pub fn init(rom: *const Rom) Uxrom {
    _ = rom;
    return .{};
}

pub fn cpuRead(self: *Uxrom, rom: *Rom, addr: u16) ?u8 {
    return switch (addr) {
        0x6000...0x7FFF => rom.readPrgRam(addr),
        0x8000...0xBFFF => rom.prg16k(self.prg_bank, addr),
        0xC000...0xFFFF => rom.prg16k(rom.prgBanks() - 1, addr),
        else => null,
    };
}

pub fn cpuWrite(self: *Uxrom, rom: *Rom, addr: u16, value: u8) bool {
    switch (addr) {
        0x6000...0x7FFF => return rom.writePrgRam(addr, value),
        0x8000...0xFFFF => {
            self.prg_bank = value;
            return true;
        },
        else => return false,
    }
}

pub fn ppuRead(_: *Uxrom, rom: *Rom, addr: u16) ?u8 {
    if (addr > 0x1FFF) return null;
    return rom.chr[rom.chrOffset(0, 0x2000, addr)];
}

pub fn ppuWrite(_: *Uxrom, rom: *Rom, addr: u16, value: u8) bool {
    if (addr > 0x1FFF) return false;
    if (rom.chr_is_ram) rom.chr[rom.chrOffset(0, 0x2000, addr)] = value;
    return true;
}
