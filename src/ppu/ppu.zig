//! Ricoh 2C02 PPU.
//!
//! A frame is 262 scanlines (-1 is the pre-render line, 0-239 are visible,
//! 241 starts vblank) of 341 dots. `clock` runs the current dot and
//! `advanceDot` moves to the next one; every visible dot writes one pixel to
//! `framebuffer`.

const Ppu = @This();

const Cartridge = @import("../cart/cartridge.zig");
const registers = @import("registers.zig");
const palette = @import("palette.zig");
const Background = @import("background.zig");
const Sprites = @import("sprites.zig");

pub const Color = palette.Color;
pub const width = 256;
pub const height = 240;

cart: *Cartridge,

// memory, the pattern tables live on the cartridge
/// 2 KB of nametable RAM inside the console, mapped by the cartridge's mirroring
name_tables: [2][0x400]u8 = @splat(@splat(0)),
palette_ram: [32]u8 = @splat(0),

// registers
ctrl: registers.Ctrl = .{},
mask: registers.Mask = .{},
status: registers.Status = .{},
/// current vram address
v: registers.Loopy = .{},
/// temporary vram address, the top left of the screen
t: registers.Loopy = .{},
fine_x: u3 = 0,
/// first / second write toggle shared by $2005 and $2006
write_toggle: bool = false,
/// $2007 read buffer
read_buffer: u8 = 0,
oam_addr: u8 = 0,

bg: Background = .{},
sprites: Sprites = .{},

// timing
scanline: i16 = 0,
dot: i16 = 0,
odd_frame: bool = false,

// outputs
/// set when vblank starts with NMI enabled, cleared by `Nes`
nmi_requested: bool = false,
/// set when the last dot of a frame is done, cleared by `Nes`
frame_complete: bool = false,
framebuffer: [width * height]Color = @splat(palette.black),

pub fn init(cart: *Cartridge) Ppu {
    return .{ .cart = cart };
}

// CPU interface ($2000-$2007, mirrored up to $3FFF)

pub fn cpuWrite(self: *Ppu, addr: u16, value: u8) void {
    switch (addr & 7) {
        // PPUCTRL
        0 => {
            self.ctrl = @bitCast(value);
            self.t.nametable_x = self.ctrl.nametable_x;
            self.t.nametable_y = self.ctrl.nametable_y;
        },
        // PPUMASK
        1 => self.mask = @bitCast(value),
        // PPUSTATUS
        2 => {},
        // OAMADDR
        3 => self.oam_addr = value,
        // OAMDATA
        4 => self.sprites.oamBytes()[self.oam_addr] = value,
        // PPUSCROLL
        5 => if (!self.write_toggle) {
            self.fine_x = @truncate(value);
            self.t.coarse_x = @truncate(value >> 3);
            self.write_toggle = true;
        } else {
            self.t.fine_y = @truncate(value);
            self.t.coarse_y = @truncate(value >> 3);
            self.write_toggle = false;
        },
        // PPUADDR
        6 => if (!self.write_toggle) {
            self.t = @bitCast((@as(u16, @bitCast(self.t)) & 0x00FF) | (@as(u16, value) << 8));
            self.write_toggle = true;
        } else {
            self.t = @bitCast((@as(u16, @bitCast(self.t)) & 0xFF00) | value);
            self.v = self.t;
            self.write_toggle = false;
        },
        // PPUDATA
        7 => {
            self.write(@bitCast(self.v), value);
            self.incrementAddr();
        },
        else => unreachable,
    }
}

pub fn cpuRead(self: *Ppu, addr: u16) u8 {
    return switch (addr & 7) {
        // PPUSTATUS
        2 => blk: {
            self.write_toggle = false;
            break :blk (@as(u8, @bitCast(self.status)) & 0xE0) | (self.read_buffer & 0x1F);
        },
        // OAMDATA
        4 => self.sprites.oamBytes()[self.oam_addr],
        // PPUDATA, reads are delayed by one except for the palette
        7 => blk: {
            var data = self.read_buffer;
            self.read_buffer = self.read(@bitCast(self.v));
            if (@as(u16, @bitCast(self.v)) > 0x3F00) data = self.read_buffer;

            self.incrementAddr();
            break :blk data;
        },
        // write only
        else => 0,
    };
}

fn incrementAddr(self: *Ppu) void {
    const step: u16 = if (self.ctrl.increment_32) 32 else 1;
    self.v = @bitCast(@as(u16, @bitCast(self.v)) +% step);
}

// PPU address space ($0000-$3FFF)

pub fn read(self: *Ppu, addr: u16) u8 {
    if (self.cart.ppuRead(addr)) |value| return value;

    const address = addr & 0x3FFF;
    return switch (address) {
        0x0000...0x1FFF => 0,
        0x2000...0x3EFF => if (self.nameTable(address)) |table| table[address & 0x03FF] else 0,
        0x3F00...0x3FFF => self.readPalette(address),
        else => unreachable,
    };
}

pub fn write(self: *Ppu, addr: u16, value: u8) void {
    if (self.cart.ppuWrite(addr, value)) return;

    const address = addr & 0x3FFF;
    switch (address) {
        0x0000...0x1FFF => {},
        0x2000...0x3EFF => if (self.nameTable(address)) |table| {
            table[address & 0x03FF] = value;
        },
        0x3F00...0x3FFF => self.palette_ram[paletteIndex(address)] = value,
        else => unreachable,
    }
}

/// the physical nametable a $2000-$3EFF address maps to
fn nameTable(self: *Ppu, addr: u16) ?*[0x400]u8 {
    return switch (self.cart.mirroring()) {
        .vertical => &self.name_tables[(addr >> 10) & 1],
        .horizontal => &self.name_tables[(addr >> 11) & 1],
        // TODO: see BUGS.md
        .single_lo, .single_hi => null,
    };
}

fn readPalette(self: *const Ppu, addr: u16) u8 {
    const mask: u8 = if (self.mask.grayscale) 0x30 else 0x3F;
    return self.palette_ram[paletteIndex(addr)] & mask;
}

/// $3F10/$3F14/$3F18/$3F1C mirror the background entries
fn paletteIndex(addr: u16) u5 {
    var index: u5 = @truncate(addr);
    if (index & 0x13 == 0x10) index &= 0x0F;
    return index;
}

// rendering

pub fn renderingEnabled(self: *const Ppu) bool {
    return self.mask.show_bg or self.mask.show_sprites;
}

/// run the current dot
pub fn clock(self: *Ppu) void {
    if (self.scanline == 241 and self.dot == 1) {
        self.status.vblank = true;
        if (self.ctrl.enable_nmi) self.nmi_requested = true;
    }

    // only the pre-render and visible scanlines do any work
    if (self.scanline < -1 or self.scanline >= 240) return;

    switch (self.dot) {
        // odd frames skip a dot when rendering
        0 => if (self.scanline == 0 and self.odd_frame and self.renderingEnabled()) {
            self.dot = 1;
        },
        1 => if (self.scanline == -1) {
            self.status.vblank = false;
            self.status.sprite_zero_hit = false;
            self.status.sprite_overflow = false;
            self.sprites.clearPatterns();
        },
        2...255, 321...337 => self.backgroundCycle(),
        256 => {
            self.backgroundCycle();
            self.incrementScrollY();
        },
        257 => {
            self.backgroundCycle();
            self.bg.loadShifters();
            self.transferX();

            if (self.scanline >= 0) {
                const sprite_height: u8 = if (self.ctrl.tall_sprites) 16 else 8;
                if (self.sprites.evaluate(self.scanline, sprite_height)) {
                    self.status.sprite_overflow = true;
                }
            }
        },
        289...304 => if (self.scanline == -1) self.transferY(),
        // unused nametable fetches
        338 => self.bg.next_tile_id = self.read(0x2000 | (@as(u16, @bitCast(self.v)) & 0x0FFF)),
        340 => {
            self.bg.next_tile_id = self.read(0x2000 | (@as(u16, @bitCast(self.v)) & 0x0FFF));
            self.sprites.fetchPatterns(self);
        },
        else => {},
    }

    self.renderPixel();
}

/// move to the next dot, called after every component has run for this one
pub fn advanceDot(self: *Ppu) void {
    self.dot += 1;
    if (self.renderingEnabled() and self.dot == 260 and self.scanline < 240) {
        self.cart.scanline();
    }

    if (self.dot >= 341) {
        self.dot = 0;
        self.scanline += 1;

        if (self.scanline >= 261) {
            self.scanline = -1;
            self.odd_frame = !self.odd_frame;
            self.frame_complete = true;
        }
    }
}

fn backgroundCycle(self: *Ppu) void {
    self.updateShifters();
    self.bg.fetch(self, @intCast((self.dot - 1) & 7));
}

fn updateShifters(self: *Ppu) void {
    if (self.mask.show_bg) self.bg.shift();
    if (self.mask.show_sprites and self.dot >= 1 and self.dot < 258) self.sprites.shift();
}

pub fn incrementScrollX(self: *Ppu) void {
    if (!self.renderingEnabled()) return;

    if (self.v.coarse_x == 31) {
        self.v.coarse_x = 0;
        self.v.nametable_x = !self.v.nametable_x;
    } else {
        self.v.coarse_x += 1;
    }
}

fn incrementScrollY(self: *Ppu) void {
    if (!self.renderingEnabled()) return;

    if (self.v.fine_y < 7) {
        self.v.fine_y += 1;
        return;
    }

    self.v.fine_y = 0;
    if (self.v.coarse_y == 29) {
        self.v.coarse_y = 0;
        self.v.nametable_y = !self.v.nametable_y;
    } else if (self.v.coarse_y == 31) {
        self.v.coarse_y = 0;
    } else {
        self.v.coarse_y += 1;
    }
}

fn transferX(self: *Ppu) void {
    if (!self.renderingEnabled()) return;
    self.v.nametable_x = self.t.nametable_x;
    self.v.coarse_x = self.t.coarse_x;
}

fn transferY(self: *Ppu) void {
    if (!self.renderingEnabled()) return;
    self.v.fine_y = self.t.fine_y;
    self.v.nametable_y = self.t.nametable_y;
    self.v.coarse_y = self.t.coarse_y;
}

/// mix the background and sprite pixel for the current dot
fn renderPixel(self: *Ppu) void {
    const bg: Background.Pixel = if (self.mask.show_bg) self.bg.pixel(self.fine_x) else .{};
    const fg: Sprites.Pixel = if (self.mask.show_sprites) self.sprites.pixel() else .{};

    var out: Background.Pixel = .{};
    if (bg.pixel == 0 and fg.pixel > 0) {
        out = .{ .pixel = fg.pixel, .palette = fg.palette };
    } else if (bg.pixel > 0 and fg.pixel == 0) {
        out = bg;
    } else if (bg.pixel > 0 and fg.pixel > 0) {
        out = if (fg.priority) .{ .pixel = fg.pixel, .palette = fg.palette } else bg;
        self.checkSpriteZeroHit();
    }

    const x = self.dot - 1;
    if (x < 0 or x >= width or self.scanline < 0 or self.scanline >= height) return;

    const index = @as(usize, @intCast(self.scanline)) * width + @as(usize, @intCast(x));
    const color_index = self.readPalette(0x3F00 + (@as(u16, out.palette) << 2) + out.pixel);
    self.framebuffer[index] = palette.colors[color_index & 0x3F];
}

/// called when an opaque sprite pixel overlaps an opaque background pixel
fn checkSpriteZeroHit(self: *Ppu) void {
    if (!(self.sprites.zero_on_line and self.sprites.zero_rendering)) return;
    if (!(self.mask.show_bg and self.mask.show_sprites)) return;

    // BUG: the left clip check should be `and`, see BUGS.md
    const first_dot: i16 = if (!(self.mask.show_bg_left or self.mask.show_sprites_left)) 9 else 1;
    if (self.dot >= first_dot and self.dot < 258) self.status.sprite_zero_hit = true;
}
