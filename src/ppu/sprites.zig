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
/// the first sprite evaluated (normally sprite 0) is in `line`
zero_on_line: bool = false,
/// sprite 0 is the sprite drawn at the current pixel
zero_rendering: bool = false,
eval: Evaluation = .{},

/// sprite evaluation in progress, finds the sprites for the next scanline
const Evaluation = struct {
    line: [8]Sprite = @splat(.{}),
    count: u8 = 0,
    /// bytes of the current sprite copied, 0 = checking its Y
    copy: u8 = 0,
    /// still on the first entry evaluated (it counts as sprite 0)
    first: bool = true,
    zero_found: bool = false,
    /// OAMADDR wrapped around, nothing more to find
    done: bool = false,
    /// byte read on the last odd dot
    latch: u8 = 0,
};

/// OAM as raw bytes, for $2004 and OAM DMA
pub fn oamBytes(self: *Sprites) *[256]u8 {
    return @ptrCast(&self.oam);
}

pub fn clearPatterns(self: *Sprites) void {
    self.pattern_lo = @splat(0);
    self.pattern_hi = @splat(0);
}

/// OAM attribute bytes only store bits 0-1 and 5-7
pub fn writeOam(self: *Sprites, addr: u8, value: u8) void {
    self.oamBytes()[addr] = if (addr & 3 == 2) value & 0xE3 else value;
}

/// start evaluating sprites for the next scanline (dot 65)
pub fn evalBegin(self: *Sprites) void {
    self.eval = .{};
}

/// one dot of sprite evaluation (dots 65-256). OAM is read on odd dots and
/// the result is acted on during even dots, `oam_addr` (OAMADDR) steps
/// through OAM as it goes, so $2004 reads see where evaluation is.
/// Returns true when sprite overflow is detected.
///
/// Whatever entry evaluation starts on counts as sprite 0 for sprite zero
/// hits. A misaligned OAMADDR stays misaligned (Y is read from whatever byte
/// it points at) until a sprite is out of range, then it realigns.
pub fn evalStep(self: *Sprites, oam_addr: *u8, dot: i16, scanline: i16, height: u8) bool {
    const e = &self.eval;
    if (dot & 1 == 1) {
        e.latch = self.oamBytes()[oam_addr.*];
        return false;
    }
    if (e.done) return false;

    var overflow = false;
    var next: u16 = oam_addr.*;
    if (e.count < 8) {
        if (e.copy == 0 and !onLine(e.latch, scanline, height)) {
            // not on this line, skip to the next (aligned) entry
            next = (next + 4) & 0x1FC;
        } else {
            if (e.copy == 0 and e.first) e.zero_found = true;
            const entry: *[4]u8 = @ptrCast(&e.line[e.count]);
            entry[e.copy] = e.latch;
            e.copy += 1;
            if (e.copy == 4) {
                e.copy = 0;
                e.count += 1;
            }
            next += 1;
        }
    } else if (e.copy == 0) {
        if (onLine(e.latch, scanline, height)) {
            overflow = true;
            e.done = true;
        } else {
            // hardware bug: the byte index within the entry is incremented
            // along with the entry, so tile ids, attributes and x get
            // checked as if they were y
            next = ((next + 4) & 0x1FC) | ((next + 1) & 3);
        }
    }

    if (e.copy == 0) e.first = false;
    if (next >= 256) e.done = true;
    oam_addr.* = @truncate(next);
    return overflow;
}

/// evaluation is over (dot 257), the sprites found become the next line's
pub fn evalFinish(self: *Sprites) void {
    self.line = self.eval.line;
    self.count = self.eval.count;
    self.zero_on_line = self.eval.zero_found;
    self.clearPatterns();
}

fn onLine(y: u8, scanline: i16, height: u8) bool {
    const diff: i16 = scanline - y;
    return diff >= 0 and diff < height;
}

/// load the pattern rows of the sprites found by `evaluate`
pub fn fetchPatterns(self: *Sprites, ppu: *Ppu) void {
    if (ppu.scanline < 0) return;
    const scanline: u16 = @intCast(ppu.scanline);

    for (self.line[0..self.count], 0..) |spr, i| {
        // only the low 4 bits matter, sprites left over from an interrupted
        // evaluation (rendering toggled mid-line) just wrap like on hardware
        const row: u16 = (scanline -% spr.y) & 0x0F;
        const flip_v = spr.attrib & 0x80 != 0;
        const flip_h = spr.attrib & 0x40 != 0;

        var addr: u16 = undefined;
        if (!ppu.ctrl.tall_sprites) {
            // 8x8, pattern table picked by PPUCTRL
            const table: u16 = @intFromBool(ppu.ctrl.sprite_table);
            addr = (table << 12) | (@as(u16, spr.id) << 4) | ((if (flip_v) 7 -% row else row) & 7);
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
