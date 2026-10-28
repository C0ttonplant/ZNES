//! iNES / NES 2.0 file parsing.

const std = @import("std");
const Rom = @import("rom.zig");

pub const Error = error{ InvalidRom, EndOfStream } || std.mem.Allocator.Error;

const Header = extern struct {
    /// "NES\x1A"
    magic: [4]u8,
    prg_banks: u8,
    chr_banks: u8,
    flags6: u8,
    flags7: u8,
    flags8: u8,
    flags9: u8,
    flags10: u8,
    padding: [5]u8,
};

pub fn parse(gpa: std.mem.Allocator, data: []const u8) Error!Rom {
    if (data.len < @sizeOf(Header)) return error.EndOfStream;
    const header: *align(1) const Header = @ptrCast(data[0..@sizeOf(Header)]);
    if (!std.mem.eql(u8, &header.magic, "NES\x1A")) return error.InvalidRom;

    const has_trainer = header.flags6 & 0x04 != 0;
    const is_nes2 = header.flags7 & 0x0C == 0x08;

    // BUG: the trainer is 512 bytes after the header (0x210), see BUGS.md
    const offset: usize = if (has_trainer) 0x200 else @sizeOf(Header);

    var prg_banks: u8 = header.prg_banks;
    var chr_banks: u8 = header.chr_banks;
    var chr_size: usize = @as(usize, @max(1, chr_banks)) * 0x2000;
    if (is_nes2) {
        // BUG: wrong header byte and bit masks, see BUGS.md
        prg_banks = (header.flags8 & 0x07) << 4 | header.prg_banks;
        chr_banks = (header.flags8 & 0x38) << 4 | header.chr_banks;
        chr_size = @as(usize, chr_banks) * 0x2000;
    }
    const prg_size = @as(usize, prg_banks) * 0x4000;

    if (data.len < offset + prg_size + chr_size) return error.EndOfStream;

    const prg_rom = try gpa.dupe(u8, data[offset..][0..prg_size]);
    errdefer gpa.free(prg_rom);
    const chr = try gpa.dupe(u8, data[offset + prg_size ..][0..chr_size]);

    return .{
        .prg_rom = prg_rom,
        .chr = chr,
        .prg_banks = prg_banks,
        .chr_banks = chr_banks,
        .mapper_id = ((header.flags7 >> 4) << 4) | (header.flags6 >> 4),
        .mirroring = if (header.flags6 & 1 != 0) .vertical else .horizontal,
    };
}
