//! A loaded game: the ROM data plus the mapper that decides how the console
//! sees it.

const Cartridge = @This();

const std = @import("std");
const Rom = @import("rom.zig");
const ines = @import("ines.zig");
const Mapper = @import("mapper.zig").Mapper;

rom: Rom,
mapper: Mapper,

pub fn load(gpa: std.mem.Allocator, io: std.Io, path: []const u8) !Cartridge {
    const data = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(16 * 1024 * 1024));
    defer gpa.free(data);
    return fromBytes(gpa, data);
}

pub fn fromBytes(gpa: std.mem.Allocator, data: []const u8) !Cartridge {
    var rom = try ines.parse(gpa, data);
    errdefer rom.deinit(gpa);
    return .{ .rom = rom, .mapper = try Mapper.init(&rom) };
}

pub fn deinit(self: *Cartridge, gpa: std.mem.Allocator) void {
    self.rom.deinit(gpa);
}

pub fn cpuRead(self: *Cartridge, addr: u16) ?u8 {
    return self.mapper.cpuRead(&self.rom, addr);
}

pub fn cpuWrite(self: *Cartridge, addr: u16, value: u8) bool {
    return self.mapper.cpuWrite(&self.rom, addr, value);
}

pub fn ppuRead(self: *Cartridge, addr: u16) ?u8 {
    return self.mapper.ppuRead(&self.rom, addr);
}

pub fn ppuWrite(self: *Cartridge, addr: u16, value: u8) bool {
    return self.mapper.ppuWrite(&self.rom, addr, value);
}

pub fn mirroring(self: *Cartridge) Rom.Mirroring {
    return self.mapper.mirroring(&self.rom);
}

pub fn scanline(self: *Cartridge) void {
    self.mapper.scanline();
}
