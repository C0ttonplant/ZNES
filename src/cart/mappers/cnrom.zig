//! Mapper 003 (CNROM): fixed 16 / 32 KB PRG, switchable 8 KB CHR bank.
//! https://www.nesdev.org/wiki/CNROM

const Cnrom = @This();

const Rom = @import("../rom.zig");

chr_bank: u8 = 0,

pub fn init(rom: *const Rom) Cnrom {
    _ = rom;
    return .{};
}

pub fn cpuRead(_: *Cnrom, rom: *Rom, addr: u16) ?u8 {
    return switch (addr) {
        0x6000...0x7FFF => rom.readPrgRam(addr),
        0x8000...0xFFFF => rom.prg32k(0, addr),
        else => null,
    };
}

pub fn cpuWrite(self: *Cnrom, rom: *Rom, addr: u16, value: u8) bool {
    switch (addr) {
        0x6000...0x7FFF => return rom.writePrgRam(addr, value),
        0x8000...0xFFFF => {
            self.chr_bank = value;
            return true;
        },
        else => return false,
    }
}

pub fn ppuRead(self: *Cnrom, rom: *Rom, addr: u16) ?u8 {
    if (addr > 0x1FFF) return null;
    return rom.chr[rom.chrOffset(self.chr_bank, 0x2000, addr)];
}

pub fn ppuWrite(self: *Cnrom, rom: *Rom, addr: u16, value: u8) bool {
    if (addr > 0x1FFF) return false;
    if (rom.chr_is_ram) rom.chr[rom.chrOffset(self.chr_bank, 0x2000, addr)] = value;
    return true;
}
