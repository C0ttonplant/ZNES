//! Mapper 000 (NROM): 16 or 32 KB of PRG ROM, 8 KB of CHR ROM or RAM, no
//! bank switching. A 16 KB PRG ROM is mirrored into both halves of $8000-$FFFF.

const Nrom = @This();

const Rom = @import("../rom.zig");

pub fn init(rom: *const Rom) Nrom {
    _ = rom;
    return .{};
}

pub fn cpuRead(_: *Nrom, rom: *Rom, addr: u16) ?u8 {
    return switch (addr) {
        0x6000...0x7FFF => rom.readPrgRam(addr),
        0x8000...0xFFFF => rom.prg32k(0, addr),
        else => null,
    };
}

pub fn cpuWrite(_: *Nrom, rom: *Rom, addr: u16, value: u8) bool {
    return switch (addr) {
        0x6000...0x7FFF => rom.writePrgRam(addr, value),
        // ROM, writes are ignored
        0x8000...0xFFFF => true,
        else => false,
    };
}

pub fn ppuRead(_: *Nrom, rom: *Rom, addr: u16) ?u8 {
    if (addr > 0x1FFF) return null;
    return rom.chr[rom.chrOffset(0, 0x2000, addr)];
}

pub fn ppuWrite(_: *Nrom, rom: *Rom, addr: u16, value: u8) bool {
    if (addr > 0x1FFF) return false;
    if (rom.chr_is_ram) rom.chr[rom.chrOffset(0, 0x2000, addr)] = value;
    return true;
}
