//! The contents of a ROM file, plus the board information from its header.
//! Mappers read and write cartridge memory through this.

const Rom = @This();

const std = @import("std");

prg_rom: []u8,
/// CHR ROM, or CHR RAM when `chr_is_ram`
chr: []u8,
/// $6000-$7FFF work / save RAM, may be empty
prg_ram: []u8,
chr_is_ram: bool,
mapper_id: u16,
submapper: u4,
/// hard-wired nametable mirroring from the header
mirroring: Mirroring,
/// PRG RAM is battery backed (save games)
battery: bool,
region: Region,

pub const Mirroring = enum {
    horizontal,
    vertical,
    single_lo,
    single_hi,
    /// the cartridge provides the extra 2 KB of nametable RAM
    four_screen,
};

pub const Region = enum {
    ntsc,
    pal,
    multi,
    dendy,
};

/// number of 16 KB PRG ROM banks
pub fn prgBanks(self: *const Rom) usize {
    return self.prg_rom.len / 0x4000;
}

/// number of 8 KB CHR banks (ROM or RAM)
pub fn chrBanks(self: *const Rom) usize {
    return self.chr.len / 0x2000;
}

/// $6000-$7FFF PRG RAM read, null if the board has none
pub fn readPrgRam(self: *const Rom, addr: u16) ?u8 {
    if (self.prg_ram.len == 0) return null;
    return self.prg_ram[(addr - 0x6000) % self.prg_ram.len];
}

/// $6000-$7FFF PRG RAM write, false if the board has none
pub fn writePrgRam(self: *Rom, addr: u16, value: u8) bool {
    if (self.prg_ram.len == 0) return false;
    self.prg_ram[(addr - 0x6000) % self.prg_ram.len] = value;
    return true;
}

/// byte from 16 KB PRG bank `bank` (wraps to the ROM size)
pub fn prg16k(self: *const Rom, bank: usize, addr: u16) u8 {
    return self.prg_rom[(bank % self.prgBanks()) * 0x4000 + (addr & 0x3FFF)];
}

/// byte from 32 KB PRG bank `bank` (wraps to the ROM size)
pub fn prg32k(self: *const Rom, bank: usize, addr: u16) u8 {
    return self.prg_rom[(bank * 0x8000 + (addr & 0x7FFF)) % self.prg_rom.len];
}

/// CHR offset for a `size` byte bank (wraps to the CHR size)
pub fn chrOffset(self: *const Rom, bank: usize, size: usize, addr: u16) usize {
    return (bank * size + (addr & (size - 1))) % self.chr.len;
}

pub fn deinit(self: *Rom, gpa: std.mem.Allocator) void {
    gpa.free(self.prg_rom);
    gpa.free(self.chr);
    gpa.free(self.prg_ram);
}
