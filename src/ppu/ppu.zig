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
/// 2 KB of nametable RAM inside the console, mapped by the cartridge's
/// mirroring. Tables 2 and 3 stand in for the extra RAM four-screen carts have.
name_tables: [4][0x400]u8 = @splat(@splat(0)),
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
/// the PPU's data bus latch, write-only registers read back as this
io_latch: u8 = 0,
/// frame each `io_latch` bit was last driven, undriven bits decay to 0
io_latch_refreshed: [8]u32 = @splat(0),

bg: Background = .{},
sprites: Sprites = .{},

// timing
scanline: i16 = 0,
dot: i16 = 0,
odd_frame: bool = false,
frame_count: u32 = 0,
/// after power on / reset the PPU ignores writes to $2000, $2001, $2005 and
/// $2006 until the first pre-render line
reset_flag: bool = true,
/// a $2002 read just before vblank starts stops the flag (and NMI) this frame
suppress_vblank: bool = false,

// outputs
/// set when the last dot of a frame is done, cleared by `Nes`
frame_complete: bool = false,
framebuffer: [width * height]Color = @splat(palette.black),

/// frames until an undriven io latch bit reads as 0 (about 600 ms)
const io_latch_decay_frames = 36;

pub fn init(cart: *Cartridge) Ppu {
    return .{ .cart = cart };
}

/// the reset button only clears some state, VRAM and OAM are kept
pub fn reset(self: *Ppu) void {
    self.ctrl = .{};
    self.mask = .{};
    self.write_toggle = false;
    self.read_buffer = 0;
    self.t = .{};
    self.fine_x = 0;
    self.scanline = 0;
    self.dot = 0;
    self.odd_frame = false;
    self.reset_flag = true;
}

/// the NMI output, the CPU triggers on its rising edge
pub fn nmiLine(self: *const Ppu) bool {
    return self.status.vblank and self.ctrl.enable_nmi;
}

// CPU interface ($2000-$2007, mirrored up to $3FFF)

pub fn cpuWrite(self: *Ppu, addr: u16, value: u8) void {
    self.refreshLatch(value, 0xFF);

    const reg = addr & 7;
    if (self.reset_flag and (reg == 0 or reg == 1 or reg == 5 or reg == 6)) return;

    switch (reg) {
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
        4 => if (self.renderingOamBus()) {
            // while rendering, writes don't reach OAM but bump the address by a whole entry
            self.oam_addr = (self.oam_addr +% 4) & 0xFC;
        } else {
            self.sprites.writeOam(self.oam_addr, value);
            self.oam_addr +%= 1;
        },
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
            // only 14 address bits, the top two are cleared
            self.t = @bitCast((@as(u16, @bitCast(self.t)) & 0x00FF) | (@as(u16, value & 0x3F) << 8));
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
    switch (addr & 7) {
        // PPUSTATUS
        2 => {
            // reading just before vblank starts means the flag (and NMI) never
            // happen this frame. Reading just after clears it before the CPU
            // sees the NMI edge, that one falls out of `Nes.endCycle`.
            if (self.scanline == 241 and self.dot == 1) self.suppress_vblank = true;

            const value = (@as(u8, @bitCast(self.status)) & 0xE0) | (self.openBus() & 0x1F);
            self.status.vblank = false;
            self.write_toggle = false;
            self.refreshLatch(value, 0xE0);
            return value;
        },
        // OAMDATA
        4 => {
            const value = self.readOamData();
            self.refreshLatch(value, 0xFF);
            return value;
        },
        // PPUDATA
        7 => {
            const vram_addr = @as(u16, @bitCast(self.v)) & 0x3FFF;
            var value: u8 = undefined;
            if (vram_addr >= 0x3F00) {
                // palette reads aren't buffered, the buffer gets the nametable byte "underneath"
                value = (self.readPalette(vram_addr) & 0x3F) | (self.openBus() & 0xC0);
                self.read_buffer = self.read(vram_addr - 0x1000);
                self.refreshLatch(value, 0x3F);
            } else {
                // other reads return the previous read
                value = self.read_buffer;
                self.read_buffer = self.read(vram_addr);
                self.refreshLatch(value, 0xFF);
            }

            self.incrementAddr();
            return value;
        },
        // write only
        else => return self.openBus(),
    }
}

/// the io latch with decayed bits cleared
fn openBus(self: *Ppu) u8 {
    for (self.io_latch_refreshed, 0..) |refreshed, bit| {
        if (self.frame_count -% refreshed > io_latch_decay_frames) {
            self.io_latch &= ~(@as(u8, 1) << @intCast(bit));
        }
    }
    return self.io_latch;
}

/// drive the `mask` bits of the io latch with `value`
fn refreshLatch(self: *Ppu, value: u8, mask: u8) void {
    self.io_latch = (self.io_latch & ~mask) | (value & mask);
    for (&self.io_latch_refreshed, 0..) |*refreshed, bit| {
        if (mask & (@as(u8, 1) << @intCast(bit)) != 0) refreshed.* = self.frame_count;
    }
}

/// rendering owns the OAM bus on visible and pre-render lines
fn renderingOamBus(self: *const Ppu) bool {
    return self.renderingEnabled() and self.scanline < 240;
}

/// $2004 read: during rendering it returns whatever sprite evaluation is
/// looking at, secondary OAM clearing / sprite fetches read as $FF
fn readOamData(self: *Ppu) u8 {
    if (self.renderingOamBus() and self.scanline >= 0) {
        if ((self.dot >= 1 and self.dot <= 64) or (self.dot >= 257 and self.dot <= 320)) return 0xFF;
    }
    return self.sprites.oamBytes()[self.oam_addr];
}

fn incrementAddr(self: *Ppu) void {
    const increment: u16 = if (self.ctrl.increment_32) 32 else 1;
    self.v = @bitCast(@as(u16, @bitCast(self.v)) +% increment);
}

// PPU address space ($0000-$3FFF)

pub fn read(self: *Ppu, addr: u16) u8 {
    const address = addr & 0x3FFF;
    if (self.cart.ppuRead(address)) |value| return value;

    return switch (address) {
        0x0000...0x1FFF => 0,
        0x2000...0x3EFF => self.nameTable(address)[address & 0x03FF],
        0x3F00...0x3FFF => self.readPalette(address),
        else => unreachable,
    };
}

pub fn write(self: *Ppu, addr: u16, value: u8) void {
    const address = addr & 0x3FFF;
    if (self.cart.ppuWrite(address, value)) return;

    switch (address) {
        0x0000...0x1FFF => {},
        0x2000...0x3EFF => self.nameTable(address)[address & 0x03FF] = value,
        0x3F00...0x3FFF => self.palette_ram[paletteIndex(address)] = value,
        else => unreachable,
    }
}

/// the physical nametable a $2000-$3EFF address maps to
fn nameTable(self: *Ppu, addr: u16) *[0x400]u8 {
    return switch (self.cart.mirroring()) {
        .vertical => &self.name_tables[(addr >> 10) & 1],
        .horizontal => &self.name_tables[(addr >> 11) & 1],
        .single_lo => &self.name_tables[0],
        .single_hi => &self.name_tables[1],
        .four_screen => &self.name_tables[(addr >> 10) & 3],
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

/// run one dot
pub fn step(self: *Ppu) void {
    self.clock();
    self.advanceDot();
}

/// run the current dot
fn clock(self: *Ppu) void {
    if (self.scanline == 241 and self.dot == 1) {
        if (!self.suppress_vblank) self.status.vblank = true;
        self.suppress_vblank = false;
    }

    // only the pre-render and visible scanlines do any work
    if (self.scanline < -1 or self.scanline >= 240) return;

    switch (self.dot) {
        1 => if (self.scanline == -1) {
            self.reset_flag = false;
            self.status.vblank = false;
            self.status.sprite_zero_hit = false;
            self.status.sprite_overflow = false;
            self.sprites.clearPatterns();
        },
        2...255, 321...337 => {
            self.backgroundCycle();
            if (self.dot >= 65 and self.dot <= 256) self.spriteEvalCycle();
        },
        256 => {
            self.backgroundCycle();
            self.spriteEvalCycle();
            self.incrementScrollY();
        },
        257 => {
            self.backgroundCycle();
            self.bg.loadShifters();
            self.transferX();

            if (self.scanline >= 0 and self.renderingEnabled()) self.sprites.evalFinish();
            if (self.renderingEnabled()) self.oam_addr = 0;
        },
        258...320 => {
            // OAMADDR is held at 0 while the sprite tiles are loaded
            if (self.renderingEnabled()) self.oam_addr = 0;
            // the pre-render line copies the vertical scroll
            if (self.scanline == -1 and self.dot >= 280 and self.dot <= 304) self.transferY();
        },
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

/// move to the next dot
fn advanceDot(self: *Ppu) void {
    self.dot += 1;
    if (self.renderingEnabled() and self.dot == 260 and self.scanline < 240) {
        self.cart.scanline();
    }

    // odd frames are one dot shorter when rendering, the pre-render line skips its last dot
    if (self.scanline == -1 and self.dot == 340 and self.odd_frame and self.renderingEnabled()) {
        self.dot = 341;
    }

    if (self.dot >= 341) {
        self.dot = 0;
        self.scanline += 1;

        if (self.scanline >= 261) {
            self.scanline = -1;
            self.odd_frame = !self.odd_frame;
            self.frame_count +%= 1;
            self.frame_complete = true;
        }
    }
}

fn spriteEvalCycle(self: *Ppu) void {
    if (self.scanline < 0 or !self.renderingEnabled()) return;
    if (self.dot == 65) self.sprites.evalBegin();

    const sprite_height: u8 = if (self.ctrl.tall_sprites) 16 else 8;
    if (self.sprites.evalStep(&self.oam_addr, self.dot, self.scanline, sprite_height)) {
        self.status.sprite_overflow = true;
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
    const x = self.dot - 1;
    var bg: Background.Pixel = if (self.mask.show_bg) self.bg.pixel(self.fine_x) else .{};
    var fg: Sprites.Pixel = if (self.mask.show_sprites) self.sprites.pixel() else .{};

    // the left 8 pixels can be hidden separately for background and sprites
    if (x >= 0 and x < 8) {
        if (!self.mask.show_bg_left) bg = .{};
        if (!self.mask.show_sprites_left) fg = .{};
    }

    var out: Background.Pixel = .{};
    if (bg.pixel == 0 and fg.pixel > 0) {
        out = .{ .pixel = fg.pixel, .palette = fg.palette };
    } else if (bg.pixel > 0 and fg.pixel == 0) {
        out = bg;
    } else if (bg.pixel > 0 and fg.pixel > 0) {
        out = if (fg.priority) .{ .pixel = fg.pixel, .palette = fg.palette } else bg;
        self.checkSpriteZeroHit();
    }

    if (x < 0 or x >= width or self.scanline < 0 or self.scanline >= height) return;

    const index = @as(usize, @intCast(self.scanline)) * width + @as(usize, @intCast(x));
    const color_index = self.readPalette(0x3F00 + (@as(u16, out.palette) << 2) + out.pixel);
    self.framebuffer[index] = palette.colors[color_index & 0x3F];
}

/// called when an opaque sprite pixel overlaps an opaque background pixel
fn checkSpriteZeroHit(self: *Ppu) void {
    if (!(self.sprites.zero_on_line and self.sprites.zero_rendering)) return;
    if (!(self.mask.show_bg and self.mask.show_sprites)) return;

    // no hits in the left 8 pixels if either of them is clipped, or at x = 255
    const x = self.dot - 1;
    const first_x: i16 = if (self.mask.show_bg_left and self.mask.show_sprites_left) 0 else 8;
    if (x >= first_x and x < 255) self.status.sprite_zero_hit = true;
}
