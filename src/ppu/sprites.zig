//! Sprites: OAM, per-scanline evaluation, pattern fetching and pixel output.

const Sprites = @This();

const Ppu = @import("ppu.zig");

/// one OAM entry, same byte order as the hardware
pub const Sprite = extern struct {
    y: u8 = 0,
    id: u8 = 0,
    attrib: u8 = 0,
    x: u8 = 0,
};

pub const Pixel = struct {
    pixel: u8 = 0,
    palette: u8 = 0,
    /// in front of the background
    priority: bool = false,
};

/// primary OAM
oam: [64]Sprite = @splat(.{}),
/// sprites on the current scanline (secondary OAM), `x` counts down to 0
/// before the sprite starts shifting out
line: [8]Sprite = @splat(.{}),
count: u8 = 0,
pattern_lo: [8]u8 = @splat(0),
pattern_hi: [8]u8 = @splat(0),
/// sprite 0 is in `line`
zero_on_line: bool = false,
/// sprite 0 is the sprite drawn at the current pixel
zero_rendering: bool = false,

/// OAM as raw bytes, for $2004 and OAM DMA
pub fn oamBytes(self: *Sprites) *[256]u8 {
    return @ptrCast(&self.oam);
}

pub fn clearPatterns(self: *Sprites) void {
    self.pattern_lo = @splat(0);
    self.pattern_hi = @splat(0);
}

/// collect up to 8 sprites that cover `scanline`, returns true on sprite overflow
pub fn evaluate(self: *Sprites, scanline: i16, height: u8) bool {
    self.count = 0;
    self.clearPatterns();
    self.zero_on_line = false;

    for (self.oam, 0..) |spr, i| {
        const diff: i16 = scanline - spr.y;
        if (diff < 0 or diff >= height) continue;

        if (self.count == 8) return true;

        if (i == 0) self.zero_on_line = true;
        self.line[self.count] = spr;
        self.count += 1;
    }
    return false;
}

/// load the pattern rows of the sprites found by `evaluate`
pub fn fetchPatterns(self: *Sprites, ppu: *Ppu) void {
    if (ppu.scanline < 0) return;
    const scanline: u16 = @intCast(ppu.scanline);

    for (self.line[0..self.count], 0..) |spr, i| {
        const row: u16 = scanline - spr.y;
        const flip_v = spr.attrib & 0x80 != 0;
        const flip_h = spr.attrib & 0x40 != 0;

        var addr: u16 = undefined;
        if (!ppu.ctrl.tall_sprites) {
            // 8x8, pattern table picked by PPUCTRL
            const table: u16 = @intFromBool(ppu.ctrl.sprite_table);
            addr = (table << 12) | (@as(u16, spr.id) << 4) | (if (flip_v) 7 -% row else row);
        } else {
            // 8x16, pattern table picked by bit 0 of the tile id
            const table: u16 = spr.id & 1;
            var tile: u16 = spr.id & 0xFE;
            // the bottom tile is drawn on the bottom half, or the top half when flipped
            if ((row < 8) == flip_v) tile += 1;
            const fine_y = (if (flip_v) 7 -% row else row) & 7;
            addr = (table << 12) | (tile << 4) | fine_y;
        }

        var lo = ppu.read(addr);
        var hi = ppu.read(addr + 8);
        if (flip_h) {
            lo = @bitReverse(lo);
            hi = @bitReverse(hi);
        }
        self.pattern_lo[i] = lo;
        self.pattern_hi[i] = hi;
    }
}

pub fn shift(self: *Sprites) void {
    for (self.line[0..self.count], 0..) |*spr, i| {
        if (spr.x > 0) {
            spr.x -= 1;
        } else {
            self.pattern_lo[i] <<= 1;
            self.pattern_hi[i] <<= 1;
        }
    }
}

/// the first opaque sprite pixel at the current dot
pub fn pixel(self: *Sprites) Pixel {
    self.zero_rendering = false;

    var out: Pixel = .{};
    for (self.line[0..self.count], 0..) |spr, i| {
        if (spr.x != 0) continue;

        out.pixel = ((self.pattern_hi[i] >> 7) << 1) | (self.pattern_lo[i] >> 7);
        out.palette = (spr.attrib & 0x03) + 0x04;
        out.priority = spr.attrib & 0x20 == 0;

        if (out.pixel != 0) {
            if (i == 0) self.zero_rendering = true;
            break;
        }
    }
    return out;
}
