//! Starting point for a new mapper, see `../mapper.zig` for how to hook it up.
//! Rename the file to the board name (e.g. `mmc1.zig`), fill in the
//! functions, delete the optional ones you don't need.

const Template = @This();

const Rom = @import("../rom.zig");

// mapper registers go here, e.g. selected banks
prg_bank: u8 = 0,

pub fn init(rom: *const Rom) Template {
    _ = rom;
    return .{};
}

/// return the byte for a CPU read, or null if the cartridge doesn't respond
pub fn cpuRead(self: *Template, rom: *Rom, addr: u16) ?u8 {
    _ = self;
    _ = rom;
    _ = addr;
    return null;
}

/// handle a CPU write (bank select registers, PRG RAM), return true if handled
pub fn cpuWrite(self: *Template, rom: *Rom, addr: u16, value: u8) bool {
    _ = self;
    _ = rom;
    _ = addr;
    _ = value;
    return false;
}

/// return the byte for a PPU read ($0000-$1FFF is CHR), or null if not handled
pub fn ppuRead(self: *Template, rom: *Rom, addr: u16) ?u8 {
    _ = self;
    _ = rom;
    _ = addr;
    return null;
}

/// handle a PPU write (CHR RAM), return true if handled
pub fn ppuWrite(self: *Template, rom: *Rom, addr: u16, value: u8) bool {
    _ = self;
    _ = rom;
    _ = addr;
    _ = value;
    return false;
}

/// optional: for mappers that switch mirroring at runtime
pub fn mirroring(self: *Template, rom: *const Rom) Rom.Mirroring {
    _ = self;
    return rom.mirroring;
}

/// optional: scanline counter hook (MMC3 style IRQs)
pub fn scanline(self: *Template) void {
    _ = self;
}
