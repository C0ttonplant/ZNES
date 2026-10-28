//! The contents of a ROM file, plus the board information from its header.
//! Mappers read and write cartridge memory through this.

const Rom = @This();

const std = @import("std");

prg_rom: []u8,
/// CHR ROM, or CHR RAM when `chr_banks` is 0
chr: []u8,
/// number of 16 KB PRG ROM banks
prg_banks: u8,
/// number of 8 KB CHR ROM banks, 0 means the board has CHR RAM
chr_banks: u8,
mapper_id: u8,
/// hard-wired nametable mirroring from the header
mirroring: Mirroring,

pub const Mirroring = enum {
    horizontal,
    vertical,
    single_lo,
    single_hi,
};

pub fn chrIsRam(self: *const Rom) bool {
    return self.chr_banks == 0;
}

pub fn deinit(self: *Rom, gpa: std.mem.Allocator) void {
    gpa.free(self.prg_rom);
    gpa.free(self.chr);
}
