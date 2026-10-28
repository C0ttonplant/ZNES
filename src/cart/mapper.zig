//! Mapper dispatch.
//!
//! Each supported board is one field of the `Mapper` union, implemented in
//! its own file in `mappers/` (copy `mappers/template.zig` to start a new
//! one). To add a mapper:
//!   1. write `mappers/your_mapper.zig`
//!   2. add a field for it to `Mapper`
//!   3. map its iNES number to that field in `Mapper.init`
//!
//! Required functions:
//!   init(rom: *const Rom) T
//!   cpuRead(self: *T, rom: *Rom, addr: u16) ?u8          null = not handled
//!   cpuWrite(self: *T, rom: *Rom, addr: u16, value: u8) bool   true = handled
//!   ppuRead(self: *T, rom: *Rom, addr: u16) ?u8
//!   ppuWrite(self: *T, rom: *Rom, addr: u16, value: u8) bool
//!
//! Optional functions (left out = default behaviour):
//!   mirroring(self: *T, rom: *const Rom) Rom.Mirroring   default: header mirroring
//!   scanline(self: *T) void                              default: nothing
//!   irq(self: *const T) bool                             default: false

const std = @import("std");
const Rom = @import("rom.zig");

pub const Mapper = union(enum) {
    nrom: @import("mappers/nrom.zig"),
    mmc1: @import("mappers/mmc1.zig"),
    uxrom: @import("mappers/uxrom.zig"),
    cnrom: @import("mappers/cnrom.zig"),
    axrom: @import("mappers/axrom.zig"),

    pub const Error = error{UnsupportedMapper};

    pub fn init(rom: *const Rom) Error!Mapper {
        return switch (rom.mapper_id) {
            0 => .{ .nrom = .init(rom) },
            1 => .{ .mmc1 = .init(rom) },
            2 => .{ .uxrom = .init(rom) },
            3 => .{ .cnrom = .init(rom) },
            7 => .{ .axrom = .init(rom) },
            else => {
                std.log.err("unsupported mapper {d}", .{rom.mapper_id});
                return error.UnsupportedMapper;
            },
        };
    }

    pub fn cpuRead(self: *Mapper, rom: *Rom, addr: u16) ?u8 {
        switch (self.*) {
            inline else => |*m| return m.cpuRead(rom, addr),
        }
    }

    pub fn cpuWrite(self: *Mapper, rom: *Rom, addr: u16, value: u8) bool {
        switch (self.*) {
            inline else => |*m| return m.cpuWrite(rom, addr, value),
        }
    }

    pub fn ppuRead(self: *Mapper, rom: *Rom, addr: u16) ?u8 {
        switch (self.*) {
            inline else => |*m| return m.ppuRead(rom, addr),
        }
    }

    pub fn ppuWrite(self: *Mapper, rom: *Rom, addr: u16, value: u8) bool {
        switch (self.*) {
            inline else => |*m| return m.ppuWrite(rom, addr, value),
        }
    }

    pub fn mirroring(self: *Mapper, rom: *const Rom) Rom.Mirroring {
        switch (self.*) {
            inline else => |*m| {
                if (@hasDecl(@TypeOf(m.*), "mirroring")) return m.mirroring(rom);
                return rom.mirroring;
            },
        }
    }

    /// level of the cartridge's IRQ output
    pub fn irq(self: *const Mapper) bool {
        switch (self.*) {
            inline else => |*m| {
                if (@hasDecl(@TypeOf(m.*), "irq")) return m.irq();
                return false;
            },
        }
    }

    /// called once per visible scanline while rendering is enabled
    pub fn scanline(self: *Mapper) void {
        switch (self.*) {
            inline else => |*m| if (@hasDecl(@TypeOf(m.*), "scanline")) m.scanline(),
        }
    }
};
