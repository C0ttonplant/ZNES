//! Save states: a snapshot of everything that changes while a game runs.
//!
//! The components are plain structs, so a state is just their bytes: CPU,
//! PPU, APU, bus and mapper, plus the cartridge's RAM. The pointers the
//! components keep to each other aren't restored, `load` keeps the live
//! ones.
//!
//! A state only loads into the same game (checked with a hash of the ROM)
//! and the same emulator build layout (checked with a fingerprint of the
//! struct sizes). States from an older build that changed any of these
//! structs are rejected rather than loaded as garbage.

const std = @import("std");
const Nes = @import("nes.zig");
const Cpu = @import("cpu/cpu.zig");
const Ppu = @import("ppu/ppu.zig");
const Apu = @import("apu/apu.zig");
const Bus = @import("bus.zig");
const Mapper = @import("cart/mapper.zig").Mapper;
const Rom = @import("cart/rom.zig");

pub const Error = error{ NotASaveState, WrongVersion, WrongGame } || std.mem.Allocator.Error;

const magic = "ZNESSAVE".*;
/// bump when the meaning of saved data changes without the sizes changing
const format_version: u32 = 1;

const Header = extern struct {
    magic: [8]u8 = magic,
    version: u32 = format_version,
    layout: u32 = layout_fingerprint,
    rom_hash: u64,
};

/// changes whenever one of the saved structs changes size
const layout_fingerprint: u32 = blk: {
    var hasher = std.hash.Crc32.init();
    for ([_]usize{ @sizeOf(Cpu), @sizeOf(Ppu), @sizeOf(Apu), @sizeOf(Bus), @sizeOf(Mapper) }) |size| {
        hasher.update(std.mem.asBytes(&@as(u64, size)));
    }
    break :blk hasher.final();
};

/// identifies the game, so a state isn't loaded into a different one
pub fn romHash(rom: *const Rom) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(rom.prg_rom);
    if (!rom.chr_is_ram) hasher.update(rom.chr);
    return hasher.final();
}

/// the full state of `nes`, caller owns the bytes
pub fn save(nes: *const Nes, gpa: std.mem.Allocator) Error![]u8 {
    const rom = &nes.cart.rom;
    const size = stateSize(rom);
    const data = try gpa.alloc(u8, size);

    var offset: usize = 0;
    const header: Header = .{ .rom_hash = romHash(rom) };
    put(data, &offset, std.mem.asBytes(&header));
    put(data, &offset, std.mem.asBytes(&nes.cpu));
    put(data, &offset, std.mem.asBytes(&nes.ppu));
    put(data, &offset, std.mem.asBytes(&nes.apu));
    put(data, &offset, std.mem.asBytes(&nes.bus));
    put(data, &offset, std.mem.asBytes(&nes.cart.mapper));
    put(data, &offset, std.mem.asBytes(&nes.nmi_line));
    put(data, &offset, rom.prg_ram);
    if (rom.chr_is_ram) put(data, &offset, rom.chr);
    std.debug.assert(offset == size);

    return data;
}

/// restore a state made by `save`. Nothing changes if it's rejected.
pub fn load(nes: *Nes, data: []const u8) Error!void {
    const rom = &nes.cart.rom;
    if (data.len < @sizeOf(Header)) return error.NotASaveState;

    var header: Header = undefined;
    @memcpy(std.mem.asBytes(&header), data[0..@sizeOf(Header)]);
    if (!std.mem.eql(u8, &header.magic, &magic)) return error.NotASaveState;
    if (header.version != format_version or header.layout != layout_fingerprint) return error.WrongVersion;
    if (header.rom_hash != romHash(rom)) return error.WrongGame;
    if (data.len != stateSize(rom)) return error.NotASaveState;

    // everything is checked, from here on it can't fail
    var offset: usize = @sizeOf(Header);

    const cpu_nes = nes.cpu.nes;
    const cpu_debug = nes.cpu.debug;
    get(data, &offset, std.mem.asBytes(&nes.cpu));
    nes.cpu.nes = cpu_nes;
    nes.cpu.debug = cpu_debug;

    const ppu_cart = nes.ppu.cart;
    get(data, &offset, std.mem.asBytes(&nes.ppu));
    nes.ppu.cart = ppu_cart;

    // the audio queued when the state was made is stale, keep the live queue
    const samples_read = nes.apu.samples_read;
    const samples_written = nes.apu.samples_written;
    const time_per_sample = nes.apu.time_per_sample;
    get(data, &offset, std.mem.asBytes(&nes.apu));
    nes.apu.samples_read = samples_read;
    nes.apu.samples_written = samples_written;
    nes.apu.time_per_sample = time_per_sample;

    const bus_ppu = nes.bus.ppu;
    const bus_apu = nes.bus.apu;
    const bus_cart = nes.bus.cart;
    get(data, &offset, std.mem.asBytes(&nes.bus));
    nes.bus.ppu = bus_ppu;
    nes.bus.apu = bus_apu;
    nes.bus.cart = bus_cart;

    get(data, &offset, std.mem.asBytes(&nes.cart.mapper));
    get(data, &offset, std.mem.asBytes(&nes.nmi_line));
    get(data, &offset, rom.prg_ram);
    if (rom.chr_is_ram) get(data, &offset, rom.chr);
}

fn stateSize(rom: *const Rom) usize {
    var size: usize = @sizeOf(Header) + @sizeOf(Cpu) + @sizeOf(Ppu) + @sizeOf(Apu) +
        @sizeOf(Bus) + @sizeOf(Mapper) + @sizeOf(bool) + rom.prg_ram.len;
    if (rom.chr_is_ram) size += rom.chr.len;
    return size;
}

fn put(data: []u8, offset: *usize, bytes: []const u8) void {
    @memcpy(data[offset.*..][0..bytes.len], bytes);
    offset.* += bytes.len;
}

fn get(data: []const u8, offset: *usize, bytes: []u8) void {
    @memcpy(bytes, data[offset.*..][0..bytes.len]);
    offset.* += bytes.len;
}
