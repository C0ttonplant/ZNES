//! Background tile fetching and the shift registers that feed pixels out.

const Background = @This();

const Ppu = @import("ppu.zig");

// latched data for the next tile
next_tile_id: u8 = 0,
next_tile_attrib: u8 = 0,
next_tile_lsb: u8 = 0,
next_tile_msb: u8 = 0,

// shift registers, the high byte is the tile being drawn, the low byte is the next one
shift_pattern_lo: u16 = 0,
shift_pattern_hi: u16 = 0,
shift_attrib_lo: u16 = 0,
shift_attrib_hi: u16 = 0,

pub const Pixel = struct {
    pixel: u8 = 0,
    palette: u8 = 0,
};

/// one step of the 8 dot fetch cycle (nametable, attribute, pattern lo, pattern hi)
pub fn fetch(self: *Background, ppu: *Ppu, step: u3) void {
    const v = ppu.v;
    switch (step) {
        0 => {
            self.loadShifters();
            self.next_tile_id = ppu.read(0x2000 | (@as(u16, @bitCast(v)) & 0x0FFF));
        },
        2 => {
            // one attribute byte per 4x4 tile block
            self.next_tile_attrib = ppu.read(0x23C0 |
                (@as(u16, @intFromBool(v.nametable_y)) << 11) |
                (@as(u16, @intFromBool(v.nametable_x)) << 10) |
                (@as(u16, v.coarse_y >> 2) << 3) |
                (v.coarse_x >> 2));

            if (v.coarse_y & 2 != 0) self.next_tile_attrib >>= 4;
            if (v.coarse_x & 2 != 0) self.next_tile_attrib >>= 2;
            self.next_tile_attrib &= 3;
        },
        4 => self.next_tile_lsb = ppu.read(self.patternAddr(ppu) + 0),
        6 => self.next_tile_msb = ppu.read(self.patternAddr(ppu) + 8),
        7 => ppu.incrementScrollX(),
        else => {},
    }
}

fn patternAddr(self: *const Background, ppu: *const Ppu) u16 {
    return (@as(u16, @intFromBool(ppu.ctrl.bg_table)) << 12) +
        (@as(u16, self.next_tile_id) << 4) +
        ppu.v.fine_y;
}

/// move the next tile into the low byte of the shift registers
pub fn loadShifters(self: *Background) void {
    self.shift_pattern_lo = (self.shift_pattern_lo & 0xFF00) | self.next_tile_lsb;
    self.shift_pattern_hi = (self.shift_pattern_hi & 0xFF00) | self.next_tile_msb;

    self.shift_attrib_lo = (self.shift_attrib_lo & 0xFF00) | @as(u16, if (self.next_tile_attrib & 0b01 != 0) 0xFF else 0);
    self.shift_attrib_hi = (self.shift_attrib_hi & 0xFF00) | @as(u16, if (self.next_tile_attrib & 0b10 != 0) 0xFF else 0);
}

pub fn shift(self: *Background) void {
    self.shift_pattern_lo <<= 1;
    self.shift_pattern_hi <<= 1;
    self.shift_attrib_lo <<= 1;
    self.shift_attrib_hi <<= 1;
}

pub fn pixel(self: *const Background, fine_x: u3) Pixel {
    const mux: u16 = @as(u16, 0x8000) >> fine_x;

    const p0: u8 = @intFromBool(self.shift_pattern_lo & mux != 0);
    const p1: u8 = @intFromBool(self.shift_pattern_hi & mux != 0);
    const a0: u8 = @intFromBool(self.shift_attrib_lo & mux != 0);
    const a1: u8 = @intFromBool(self.shift_attrib_hi & mux != 0);

    return .{ .pixel = (p1 << 1) | p0, .palette = (a1 << 1) | a0 };
}
