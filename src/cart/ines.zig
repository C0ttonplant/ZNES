//! iNES / NES 2.0 file parsing.
//! https://www.nesdev.org/wiki/INES, https://www.nesdev.org/wiki/NES_2.0

const std = @import("std");
const Rom = @import("rom.zig");

pub const Error = error{ InvalidRom, EndOfStream, UnsupportedRomSize } || std.mem.Allocator.Error;

const Header = extern struct {
    /// "NES\x1A"
    magic: [4]u8,
    /// PRG ROM size, low byte, 16 KB units
    prg_size: u8,
    /// CHR ROM size, low byte, 8 KB units
    chr_size: u8,
    /// mirroring, battery, trainer, four-screen, mapper bits 0-3
    flags6: u8,
    /// console type, NES 2.0 identifier, mapper bits 4-7
    flags7: u8,
    /// NES 2.0: mapper bits 8-11, submapper
    mapper_msb: u8,
    /// NES 2.0: PRG / CHR ROM size high nibbles
    rom_size_msb: u8,
    /// NES 2.0: PRG RAM / NVRAM size shifts
    prg_ram_size: u8,
    /// NES 2.0: CHR RAM / NVRAM size shifts
    chr_ram_size: u8,
    /// NES 2.0: CPU/PPU timing (region)
    timing: u8,
    padding: [3]u8,
};

const trainer_size = 512;
const default_prg_ram_size = 0x2000;
const default_chr_ram_size = 0x2000;

pub fn parse(gpa: std.mem.Allocator, data: []const u8) Error!Rom {
    if (data.len < @sizeOf(Header)) return error.EndOfStream;
    const header: *align(1) const Header = @ptrCast(data[0..@sizeOf(Header)]);
    if (!std.mem.eql(u8, &header.magic, "NES\x1A")) return error.InvalidRom;

    const is_nes2 = header.flags7 & 0x0C == 0x08;
    // old dumping tools wrote junk like "DiskDude!" into bytes 7-15, the
    // upper mapper nibble can't be trusted then
    const has_junk = !is_nes2 and !std.mem.allEqual(u8, data[12..16], 0);

    var mapper_id: u16 = header.flags6 >> 4;
    if (!has_junk) mapper_id |= header.flags7 & 0xF0;
    var submapper: u4 = 0;

    var prg_size: usize = @as(usize, header.prg_size) * 0x4000;
    var chr_size: usize = @as(usize, header.chr_size) * 0x2000;
    var prg_ram_size: usize = default_prg_ram_size;
    var chr_ram_size: usize = default_chr_ram_size;
    var region: Rom.Region = .ntsc;

    if (is_nes2) {
        mapper_id |= @as(u16, header.mapper_msb & 0x0F) << 8;
        submapper = @truncate(header.mapper_msb >> 4);

        // a 0xF nibble means the exponent-multiplier size notation, which
        // only matters for odd sized homebrew, not supported
        const prg_msb = header.rom_size_msb & 0x0F;
        const chr_msb = header.rom_size_msb >> 4;
        if (prg_msb == 0x0F or chr_msb == 0x0F) return error.UnsupportedRomSize;
        prg_size = (@as(usize, prg_msb) << 8 | header.prg_size) * 0x4000;
        chr_size = (@as(usize, chr_msb) << 8 | header.chr_size) * 0x2000;

        // volatile and battery backed RAM are mapped to the same place
        prg_ram_size = ramSize(header.prg_ram_size & 0x0F) + ramSize(header.prg_ram_size >> 4);
        chr_ram_size = ramSize(header.chr_ram_size & 0x0F) + ramSize(header.chr_ram_size >> 4);
        region = @fromBackingInt(@intCast(header.timing & 0x03));
    } else if (!has_junk and header.rom_size_msb & 0x01 != 0) {
        // iNES byte 9 bit 0, rarely set, but correct when it is
        region = .pal;
    }

    const has_trainer = header.flags6 & 0x04 != 0;
    const prg_start: usize = @sizeOf(Header) + @as(usize, if (has_trainer) trainer_size else 0);
    if (data.len < prg_start + prg_size + chr_size) return error.EndOfStream;

    const prg_rom = try gpa.dupe(u8, data[prg_start..][0..prg_size]);
    errdefer gpa.free(prg_rom);

    // no CHR ROM means the board has CHR RAM
    const chr_is_ram = chr_size == 0;
    const chr = if (chr_is_ram)
        try zeroed(gpa, @max(chr_ram_size, default_chr_ram_size))
    else
        try gpa.dupe(u8, data[prg_start + prg_size ..][0..chr_size]);
    errdefer gpa.free(chr);

    const prg_ram = try zeroed(gpa, prg_ram_size);

    return .{
        .prg_rom = prg_rom,
        .chr = chr,
        .prg_ram = prg_ram,
        .chr_is_ram = chr_is_ram,
        .mapper_id = mapper_id,
        .submapper = submapper,
        .mirroring = if (header.flags6 & 0x08 != 0)
            .four_screen
        else if (header.flags6 & 0x01 != 0)
            .vertical
        else
            .horizontal,
        .battery = header.flags6 & 0x02 != 0,
        .region = region,
    };
}

/// NES 2.0 RAM sizes are stored as a shift count, 0 means none
fn ramSize(shift: u8) usize {
    if (shift == 0) return 0;
    return @as(usize, 64) << @intCast(shift);
}

fn zeroed(gpa: std.mem.Allocator, len: usize) ![]u8 {
    const buf = try gpa.alloc(u8, len);
    @memset(buf, 0);
    return buf;
}
