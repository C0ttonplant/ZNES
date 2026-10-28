//! Mapper 001 (MMC1, SxROM boards).
//! https://www.nesdev.org/wiki/MMC1
//!
//! Registers are written one bit at a time through a 5 bit shift register at
//! $8000-$FFFF, the 5th write copies it to the register picked by A13-A14.

const Mmc1 = @This();

const Rom = @import("../rom.zig");

shift: u8 = shift_reset,
/// mirroring (bits 0-1), PRG mode (bits 2-3), CHR mode (bit 4)
control: u8 = 0x0C,
chr_bank0: u8 = 0,
chr_bank1: u8 = 0,
prg_bank: u8 = 0,

/// the marker bit, the register is full once it has shifted down to bit 0
const shift_reset = 0x10;

pub fn init(rom: *const Rom) Mmc1 {
    _ = rom;
    return .{};
}

pub fn cpuRead(self: *Mmc1, rom: *Rom, addr: u16) ?u8 {
    return switch (addr) {
        0x6000...0x7FFF => if (self.prgRamEnabled()) rom.readPrgRam(addr) else null,
        0x8000...0xFFFF => rom.prg16k(self.prgBank(rom, addr), addr),
        else => null,
    };
}

pub fn cpuWrite(self: *Mmc1, rom: *Rom, addr: u16, value: u8) bool {
    switch (addr) {
        0x6000...0x7FFF => return self.prgRamEnabled() and rom.writePrgRam(addr, value),
        0x8000...0xFFFF => {
            // TODO: writes on consecutive cpu cycles (RMW instructions) should be ignored
            if (value & 0x80 != 0) {
                self.shift = shift_reset;
                self.control |= 0x0C;
                return true;
            }

            const full = self.shift & 1 != 0;
            self.shift = (self.shift >> 1) | ((value & 1) << 4);
            if (full) {
                switch ((addr >> 13) & 3) {
                    0 => self.control = self.shift,
                    1 => self.chr_bank0 = self.shift,
                    2 => self.chr_bank1 = self.shift,
                    3 => self.prg_bank = self.shift,
                    else => unreachable,
                }
                self.shift = shift_reset;
            }
            return true;
        },
        else => return false,
    }
}

pub fn ppuRead(self: *Mmc1, rom: *Rom, addr: u16) ?u8 {
    if (addr > 0x1FFF) return null;
    return rom.chr[self.chrOffset(rom, addr)];
}

pub fn ppuWrite(self: *Mmc1, rom: *Rom, addr: u16, value: u8) bool {
    if (addr > 0x1FFF) return false;
    if (rom.chr_is_ram) rom.chr[self.chrOffset(rom, addr)] = value;
    return true;
}

pub fn mirroring(self: *Mmc1, rom: *const Rom) Rom.Mirroring {
    _ = rom;
    return switch (self.control & 3) {
        0 => .single_lo,
        1 => .single_hi,
        2 => .vertical,
        3 => .horizontal,
        else => unreachable,
    };
}

fn prgRamEnabled(self: *const Mmc1) bool {
    return self.prg_bank & 0x10 == 0;
}

/// 16 KB bank mapped at `addr`
fn prgBank(self: *const Mmc1, rom: *const Rom, addr: u16) usize {
    // 512 KB boards (SUROM) use CHR bank 0 bit 4 to pick the 256 KB half
    const outer: usize = if (rom.prgBanks() > 16) @as(usize, self.chr_bank0 & 0x10) else 0;
    const bank: usize = self.prg_bank & 0x0F;
    const upper_half = addr >= 0xC000;

    const inner: usize = switch ((self.control >> 2) & 3) {
        // 32 KB mode, low bit ignored
        0, 1 => (bank & 0x0E) + @intFromBool(upper_half),
        // first bank fixed at $8000
        2 => if (upper_half) bank else 0,
        // last bank fixed at $C000
        3 => if (upper_half) (@min(rom.prgBanks(), 16) - 1) else bank,
        else => unreachable,
    };
    return outer | inner;
}

fn chrOffset(self: *const Mmc1, rom: *const Rom, addr: u16) usize {
    if (self.control & 0x10 == 0) {
        // one 8 KB bank, low bit ignored
        return rom.chrOffset(self.chr_bank0 >> 1, 0x2000, addr);
    }
    // two 4 KB banks
    const bank = if (addr < 0x1000) self.chr_bank0 else self.chr_bank1;
    return rom.chrOffset(bank, 0x1000, addr);
}
